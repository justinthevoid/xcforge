type HandoffDestinationId = 'docs' | 'workflow-guide';

type HandoffState = 'deep-dive' | 'fallback';

const HANDOFF_LINK_SELECTOR = 'a[data-docs-handoff-link="true"]';
const HANDOFF_STATUS_SELECTOR = '[data-docs-handoff-status]';
const DEFAULT_FALLBACK_HREF = '/docs';
const DEFAULT_UNAVAILABLE_MESSAGE =
	'Requested docs destination is temporarily unavailable. You were redirected to Docs overview.';

function isBrowserRuntime(): boolean {
	return typeof window !== 'undefined' && typeof document !== 'undefined';
}

function isPrimaryUnmodifiedClick(event: MouseEvent): boolean {
	return (
		event.button === 0 &&
		!event.defaultPrevented &&
		!event.metaKey &&
		!event.ctrlKey &&
		!event.shiftKey &&
		!event.altKey
	);
}

function resolveDestinationId(value: string | undefined): HandoffDestinationId {
	return value === 'workflow-guide' ? 'workflow-guide' : 'docs';
}

function resolveDestinationLabel(destinationId: HandoffDestinationId): string {
	return destinationId === 'workflow-guide' ? 'Workflow Guide' : 'Docs overview';
}

function toAbsoluteUrl(rawHref: string): URL | null {
	try {
		return new URL(rawHref, window.location.origin);
	} catch {
		return null;
	}
}

function buildHandoffHref(
	url: URL,
	handoffState: HandoffState,
	destinationId: HandoffDestinationId,
	unavailableMessage?: string,
): string {
	const nextUrl = new URL(url.toString());
	nextUrl.searchParams.set('handoff', handoffState);
	nextUrl.searchParams.set('destination', destinationId);
	nextUrl.searchParams.set('source', 'homepage');

	if (handoffState === 'fallback' && unavailableMessage) {
		nextUrl.searchParams.set('unavailableMessage', unavailableMessage);
	}

	return `${nextUrl.pathname}${nextUrl.search}${nextUrl.hash}`;
}

function showHandoffStatus(statusNode: HTMLElement | null, message: string): void {
	if (!statusNode || !message.trim()) {
		return;
	}

	statusNode.hidden = false;
	statusNode.textContent = '';
	window.requestAnimationFrame(() => {
		statusNode.textContent = message;
	});
}

async function isDestinationAvailable(destinationHref: string): Promise<boolean> {
	try {
		const headResponse = await fetch(destinationHref, {
			method: 'HEAD',
			cache: 'no-store',
			credentials: 'same-origin',
			redirect: 'follow',
		});

		if (headResponse.ok) {
			return true;
		}

		if (headResponse.status !== 405 && headResponse.status !== 501) {
			return false;
		}

		const getResponse = await fetch(destinationHref, {
			method: 'GET',
			cache: 'no-store',
			credentials: 'same-origin',
			redirect: 'follow',
			headers: {
				'x-xcforge-handoff-check': '1',
			},
		});

		return getResponse.ok;
	} catch {
		return false;
	}
}

function bindHandoffLink(link: HTMLAnchorElement, statusNode: HTMLElement | null): void {
	link.addEventListener('click', async (event) => {
		if (!isPrimaryUnmodifiedClick(event)) {
			return;
		}

		const destinationUrl = toAbsoluteUrl(link.href);
		if (!destinationUrl || destinationUrl.origin !== window.location.origin) {
			return;
		}

		event.preventDefault();

		const destinationId = resolveDestinationId(link.dataset.handoffDestinationId);
		const fallbackUrl =
			toAbsoluteUrl(link.dataset.handoffFallbackHref || DEFAULT_FALLBACK_HREF) ||
			toAbsoluteUrl(DEFAULT_FALLBACK_HREF);
		const unavailableMessage =
			link.dataset.handoffUnavailableMessage?.trim() ||
			`${resolveDestinationLabel(destinationId)} is temporarily unavailable. You were redirected to Docs overview.` ||
			DEFAULT_UNAVAILABLE_MESSAGE;

		if (!fallbackUrl) {
			showHandoffStatus(statusNode, unavailableMessage);
			window.location.assign(DEFAULT_FALLBACK_HREF);
			return;
		}

		const destinationHref = `${destinationUrl.pathname}${destinationUrl.search}`;
		const available = await isDestinationAvailable(destinationHref);
		if (available) {
			window.location.assign(buildHandoffHref(destinationUrl, 'deep-dive', destinationId));
			return;
		}

		showHandoffStatus(statusNode, unavailableMessage);
		window.location.assign(
			buildHandoffHref(fallbackUrl, 'fallback', destinationId, unavailableMessage),
		);
	});
}

export function initializeDocsHandoff(): void {
	if (!isBrowserRuntime()) {
		return;
	}

	const links = Array.from(document.querySelectorAll<HTMLAnchorElement>(HANDOFF_LINK_SELECTOR));
	if (links.length === 0) {
		return;
	}

	const statusNode = document.querySelector<HTMLElement>(HANDOFF_STATUS_SELECTOR);
	for (const link of links) {
		bindHandoffLink(link, statusNode);
	}
}
