#!/usr/bin/env bun

import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = join(dirname(fileURLToPath(import.meta.url)), '..');

const paths = {
	analyticsLib: join(projectRoot, 'src', 'lib', 'analytics.ts'),
	installIntent: join(projectRoot, 'src', 'lib', 'install-intent.ts'),
	indexRoute: join(projectRoot, 'src', 'pages', 'index.astro'),
	globalNav: join(projectRoot, 'src', 'components', 'web', 'GlobalNav.astro'),
	heroProof: join(projectRoot, 'src', 'components', 'web', 'HeroProof.astro'),
	finalCta: join(projectRoot, 'src', 'components', 'web', 'FinalCTA.astro'),
	docsHandoff: join(projectRoot, 'src', 'components', 'web', 'DocsHandoffSection.astro'),
	apiAnalytics: join(projectRoot, 'src', 'pages', 'api', 'analytics.ts'),
	packageJson: join(projectRoot, 'package.json'),
};

const failures = [];

function rel(filePath) {
	return relative(projectRoot, filePath) || '.';
}

function fail(scope, filePath, message, remediation) {
	failures.push({ scope, filePath, message, remediation });
}

function readRequiredFile(filePath, scope) {
	if (!existsSync(filePath)) {
		fail(
			scope,
			filePath,
			'Required file is missing.',
			'Restore the file and re-run Story 5.5 analytics validation.',
		);
		return null;
	}

	try {
		const source = readFileSync(filePath, 'utf8');
		if (!source.trim()) {
			fail(
				scope,
				filePath,
				'Required file is empty.',
				'Restore implementation content before build.',
			);
			return null;
		}
		return source;
	} catch (error) {
		fail(
			scope,
			filePath,
			`Unable to read file. ${error.message}`,
			'Resolve filesystem issues and retry validation.',
		);
		return null;
	}
}

function expectIncludes(source, token, scope, filePath, message, remediation) {
	if (!source.includes(token)) {
		fail(scope, filePath, message, remediation);
	}
}

function expectMatches(source, pattern, scope, filePath, message, remediation) {
	if (!pattern.test(source)) {
		fail(scope, filePath, message, remediation);
	}
}

function validateAnalyticsContract(analyticsSource) {
	const scope = 'contract:analytics-schema';
	const filePath = paths.analyticsLib;

	const canonicalEventNames = [
		'homepage.install.cta.clicked',
		'homepage.docs.clicked',
		'homepage.workflow-guide.clicked',
		'homepage.github.outbound.clicked',
		'homepage.install-intent.captured',
	];

	for (const eventName of canonicalEventNames) {
		expectIncludes(
			analyticsSource,
			eventName,
			scope,
			filePath,
			`Missing canonical analytics event name "${eventName}".`,
			'Restore canonical event taxonomy in src/lib/analytics.ts.',
		);
	}

	expectIncludes(
		analyticsSource,
		'canonicalHomepageAnalyticsEventNames',
		scope,
		filePath,
		'Missing exported canonical event list.',
		'Export canonicalHomepageAnalyticsEventNames for validator and runtime contract visibility.',
	);

	expectIncludes(
		analyticsSource,
		'isAnalyticsRelayEnvelope',
		scope,
		filePath,
		'Missing relay envelope validator.',
		'Preserve schema guard for API relay payload validation.',
	);

	expectIncludes(
		analyticsSource,
		'enqueueInstallIntentCapturedEvent',
		scope,
		filePath,
		'Missing install-intent analytics bridge.',
		'Restore install-intent event emission through the centralized analytics boundary.',
	);

	expectIncludes(
		analyticsSource,
		'enqueueTaggedAnchorClickEvent',
		scope,
		filePath,
		'Missing tagged anchor click emitter.',
		'Restore conversion-link event emitter for homepage analytics tags.',
	);

	expectIncludes(
		analyticsSource,
		'ANALYTICS_QUEUE_MAX_ITEMS',
		scope,
		filePath,
		'Missing queue-size policy constant.',
		'Restore queue-size limit for safe-drop behavior.',
	);

	expectIncludes(
		analyticsSource,
		'ANALYTICS_MAX_RETRY_COUNT',
		scope,
		filePath,
		'Missing retry-cap policy constant.',
		'Restore retry-cap contract for relay outage handling.',
	);

	expectIncludes(
		analyticsSource,
		'ANALYTICS_MAX_EVENT_AGE_MS',
		scope,
		filePath,
		'Missing event-age TTL policy constant.',
		'Restore TTL-based safe-drop policy for stale analytics entries.',
	);

	expectIncludes(
		analyticsSource,
		"ANALYTICS_RELAY_PATH = '/api/analytics'",
		scope,
		filePath,
		'Missing same-origin analytics relay path.',
		'Restore /api/analytics relay path to preserve non-blocking client instrumentation.',
	);

	expectIncludes(
		analyticsSource,
		'dropBatch',
		scope,
		filePath,
		'Missing safe-drop branch for non-retryable relay failures.',
		'Restore safe-drop logic so user interactions are never blocked by non-retryable telemetry failures.',
	);
}

function validateInstallIntentBridge(installIntentSource) {
	const scope = 'bridge:install-intent';
	const filePath = paths.installIntent;

	expectIncludes(
		installIntentSource,
		"from './analytics'",
		scope,
		filePath,
		'Missing analytics import in install-intent module.',
		'Restore install-intent to analytics bridge import.',
	);

	expectIncludes(
		installIntentSource,
		'return enqueueInstallIntentCapturedEvent(payload);',
		scope,
		filePath,
		'Missing centralized install-intent enqueue call.',
		'Restore enqueueInstallIntentRelay to use enqueueInstallIntentCapturedEvent.',
	);

	expectIncludes(
		installIntentSource,
		"const state = persisted ? 'ready' : 'failure';",
		scope,
		filePath,
		'Install handoff state appears coupled to telemetry success.',
		'Keep install handoff success dependent on intent persistence only, not relay availability.',
	);
}

function validateTaggedInstrumentation(
	globalNavSource,
	heroSource,
	finalCtaSource,
	docsHandoffSource,
) {
	const scope = 'instrumentation:homepage-links';

	const requiredChecks = [
		{
			filePath: paths.globalNav,
			source: globalNavSource,
			tokens: [
				'data-analytics-event-name',
				'homepage.install.cta.clicked',
				'homepage.docs.clicked',
				'homepage.workflow-guide.clicked',
				'homepage.github.outbound.clicked',
			],
			patterns: [
				{
					pattern:
						/data-analytics-source-surface=\{[\s\S]*analyticsConfig[\s\S]*["']global-nav["'][\s\S]*undefined[\s\S]*\}/m,
					label: "data-analytics-source-surface={analyticsConfig ? 'global-nav' : undefined}",
				},
			],
		},
		{
			filePath: paths.heroProof,
			source: heroSource,
			tokens: [
				'data-analytics-event-name="homepage.install.cta.clicked"',
				'data-analytics-event-name="homepage.docs.clicked"',
				'data-analytics-event-name="homepage.workflow-guide.clicked"',
				'data-analytics-source-surface="hero"',
			],
		},
		{
			filePath: paths.finalCta,
			source: finalCtaSource,
			tokens: [
				'data-analytics-event-name="homepage.install.cta.clicked"',
				'data-analytics-event-name="homepage.workflow-guide.clicked"',
				'data-analytics-source-surface="final-cta"',
			],
		},
		{
			filePath: paths.docsHandoff,
			source: docsHandoffSource,
			tokens: [
				'data-analytics-intent-signal="depth-navigation"',
				'data-analytics-source-surface="docs-handoff"',
			],
			patterns: [
				{
					pattern: /data-analytics-event-name=\{analyticsEventName\}/m,
					label: 'data-analytics-event-name={analyticsEventName}',
				},
				{
					pattern: /data-analytics-destination=\{analyticsDestination\}/m,
					label: 'data-analytics-destination={analyticsDestination}',
				},
			],
		},
	];

	for (const check of requiredChecks) {
		for (const token of check.tokens) {
			expectIncludes(
				check.source,
				token,
				scope,
				check.filePath,
				`Missing analytics instrumentation token: ${token}`,
				'Restore explicit analytics data attributes for conversion-critical links.',
			);
		}

		for (const matcher of check.patterns ?? []) {
			expectMatches(
				check.source,
				matcher.pattern,
				scope,
				check.filePath,
				`Missing analytics instrumentation token: ${matcher.label}`,
				'Restore explicit analytics data attributes for conversion-critical links.',
			);
		}
	}
}

function validateInitializationOrdering(indexSource) {
	const scope = 'runtime:init-order';
	const filePath = paths.indexRoute;

	expectIncludes(
		indexSource,
		'initializeHomepageAnalytics',
		scope,
		filePath,
		'Missing homepage analytics initialization import/call.',
		'Restore initializeHomepageAnalytics in index route startup script.',
	);

	const analyticsCallIndex = indexSource.indexOf('initializeHomepageAnalytics();');
	const docsCallIndex = indexSource.indexOf('initializeDocsHandoff();');
	const installCallIndex = indexSource.indexOf('initializeInstallIntentHandoff();');

	if (
		analyticsCallIndex === -1 ||
		docsCallIndex === -1 ||
		installCallIndex === -1 ||
		analyticsCallIndex > docsCallIndex ||
		analyticsCallIndex > installCallIndex
	) {
		fail(
			scope,
			filePath,
			'Homepage analytics must initialize before docs/install click interceptors.',
			'Move initializeHomepageAnalytics() before initializeDocsHandoff() and initializeInstallIntentHandoff().',
		);
	}
}

function validateRelayApi(apiSource) {
	const scope = 'platform:analytics-relay';
	const filePath = paths.apiAnalytics;

	expectIncludes(
		apiSource,
		'isAnalyticsRelayEnvelope',
		scope,
		filePath,
		'Missing typed relay request validation.',
		'Restore relay envelope validation before forwarding events.',
	);

	expectIncludes(
		apiSource,
		'XCFORGE_ANALYTICS_ENDPOINT',
		scope,
		filePath,
		'Missing runtime endpoint binding usage.',
		'Restore runtime analytics endpoint binding usage for relay forwarding.',
	);

	expectIncludes(
		apiSource,
		'XCFORGE_ANALYTICS_DATASET',
		scope,
		filePath,
		'Missing runtime dataset binding usage.',
		'Restore dataset binding usage to preserve reporting taxonomy partitioning.',
	);

	expectIncludes(
		apiSource,
		'retryable',
		scope,
		filePath,
		'Missing retryability signaling in relay responses.',
		'Restore retryable response semantics for queue retry/safe-drop policy.',
	);
}

function validatePackageScripts(packageSource) {
	const scope = 'build-gate:story-5-5';
	const filePath = paths.packageJson;

	let parsed;
	try {
		parsed = JSON.parse(packageSource);
	} catch (error) {
		fail(
			scope,
			filePath,
			`Unable to parse package.json. ${error.message}`,
			'Restore valid package.json JSON before running Story 5.5 validation.',
		);
		return;
	}

	const scripts = parsed.scripts || {};
	if (scripts['validate:story-5-5'] !== 'bun run scripts/validate-qualified-intent-analytics.mjs') {
		fail(
			scope,
			filePath,
			'Missing or incorrect validate:story-5-5 script.',
			'Add "validate:story-5-5": "bun run scripts/validate-qualified-intent-analytics.mjs" to package scripts.',
		);
	}

	if (typeof scripts.build !== 'string' || !scripts.build.includes('bun run validate:story-5-5')) {
		fail(
			scope,
			filePath,
			'Build script does not include Story 5.5 validation gate.',
			'Wire "bun run validate:story-5-5" into build before "astro build".',
		);
	}
}

function printFailuresAndExit() {
	console.error('[story-5-5 analytics] Validation failed.');
	console.error('[story-5-5 analytics] Remediation guidance follows:');

	for (let index = 0; index < failures.length; index += 1) {
		const failure = failures[index];
		console.error(
			`${index + 1}. [${failure.scope}] ${rel(failure.filePath)} :: ${failure.message}`,
		);
		console.error(`   Remediation: ${failure.remediation}`);
	}

	process.exit(1);
}

const analyticsSource = readRequiredFile(paths.analyticsLib, 'contract:analytics-schema');
const installIntentSource = readRequiredFile(paths.installIntent, 'bridge:install-intent');
const indexSource = readRequiredFile(paths.indexRoute, 'runtime:init-order');
const globalNavSource = readRequiredFile(paths.globalNav, 'instrumentation:homepage-links');
const heroSource = readRequiredFile(paths.heroProof, 'instrumentation:homepage-links');
const finalCtaSource = readRequiredFile(paths.finalCta, 'instrumentation:homepage-links');
const docsHandoffSource = readRequiredFile(paths.docsHandoff, 'instrumentation:homepage-links');
const apiSource = readRequiredFile(paths.apiAnalytics, 'platform:analytics-relay');
const packageSource = readRequiredFile(paths.packageJson, 'build-gate:story-5-5');

if (
	!analyticsSource ||
	!installIntentSource ||
	!indexSource ||
	!globalNavSource ||
	!heroSource ||
	!finalCtaSource ||
	!docsHandoffSource ||
	!apiSource ||
	!packageSource
) {
	process.exit(1);
}

validateAnalyticsContract(analyticsSource);
validateInstallIntentBridge(installIntentSource);
validateTaggedInstrumentation(globalNavSource, heroSource, finalCtaSource, docsHandoffSource);
validateInitializationOrdering(indexSource);
validateRelayApi(apiSource);
validatePackageScripts(packageSource);

if (failures.length > 0) {
	printFailuresAndExit();
}

console.log('[story-5-5 analytics] Validation passed.');
console.log(
	'[story-5-5 analytics] Canonical event contract, instrumentation, relay, and build gate are intact.',
);
