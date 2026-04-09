import type { APIRoute } from 'astro';
import { env } from 'cloudflare:workers';
import { isAnalyticsRelayEnvelope } from '../../lib/analytics';

export const prerender = false;

const JSON_HEADERS = {
	'content-type': 'application/json; charset=utf-8',
};

function asJsonResponse(status: number, body: Record<string, unknown>): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: JSON_HEADERS,
	});
}

function isRetryableStatus(status: number): boolean {
	return status === 408 || status === 429 || status >= 500;
}

function isValidAnalyticsEndpoint(endpoint: string): boolean {
	try {
		const endpointUrl = new URL(endpoint);
		return endpointUrl.protocol === 'https:' || endpointUrl.protocol === 'http:';
	} catch {
		return false;
	}
}

export const POST: APIRoute = async ({ request }) => {
	let payload: unknown;
	try {
		payload = await request.json();
	} catch {
		return asJsonResponse(400, {
			accepted: false,
			retryable: false,
			error: 'invalid-json',
		});
	}

	if (!isAnalyticsRelayEnvelope(payload)) {
		return asJsonResponse(400, {
			accepted: false,
			retryable: false,
			error: 'invalid-relay-envelope',
		});
	}

	const endpoint = (env as Record<string, string | undefined>).XCFORGE_ANALYTICS_ENDPOINT?.trim();
	const dataset = ((env as Record<string, string | undefined>).XCFORGE_ANALYTICS_DATASET?.trim()) || 'web-default';

	if (!endpoint || endpoint.includes('example.invalid') || !isValidAnalyticsEndpoint(endpoint)) {
		return asJsonResponse(503, {
			accepted: false,
			retryable: true,
			error: 'relay-endpoint-unavailable',
		});
	}

	try {
		const relayResponse = await fetch(endpoint, {
			method: 'POST',
			headers: {
				'content-type': 'application/json',
			},
			body: JSON.stringify({
				schemaVersion: 1,
				dataset,
				receivedAt: new Date().toISOString(),
				events: payload.events,
			}),
		});

		if (relayResponse.ok) {
			return asJsonResponse(202, {
				accepted: true,
				eventCount: payload.events.length,
			});
		}

		if (isRetryableStatus(relayResponse.status)) {
			return asJsonResponse(503, {
				accepted: false,
				retryable: true,
				error: 'relay-retryable-failure',
				status: relayResponse.status,
			});
		}

		return asJsonResponse(422, {
			accepted: false,
			retryable: false,
			error: 'relay-rejected-event-batch',
			status: relayResponse.status,
		});
	} catch {
		return asJsonResponse(503, {
			accepted: false,
			retryable: true,
			error: 'relay-network-failure',
		});
	}
};
