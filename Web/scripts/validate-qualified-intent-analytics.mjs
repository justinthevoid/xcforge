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
	hero: join(projectRoot, 'src', 'components', 'web', 'Hero.astro'),
	finalCta: join(projectRoot, 'src', 'components', 'web', 'FinalCTA.astro'),
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
			'Restore the file and re-run analytics validation.',
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

	// Validate that source surfaces include all new homepage sections and exclude removed ones.
	const requiredSourceSurfaces = ['hero', 'final-cta', 'global-nav', 'install-handoff'];
	for (const surface of requiredSourceSurfaces) {
		expectIncludes(
			analyticsSource,
			`'${surface}'`,
			scope,
			filePath,
			`Missing analytics source surface "${surface}" in AnalyticsSourceSurface type.`,
			'Restore all required source surfaces in the AnalyticsSourceSurface union type.',
		);
	}

	// docs-handoff surface must not exist in the new homepage.
	if (analyticsSource.includes("'docs-handoff'")) {
		fail(
			scope,
			filePath,
			'Removed source surface "docs-handoff" is still present in analytics contract.',
			'Remove the docs-handoff surface from AnalyticsSourceSurface — it no longer exists in the new homepage.',
		);
	}
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

function validateTaggedInstrumentation(globalNavSource, heroSource, finalCtaSource) {
	const scope = 'instrumentation:homepage-links';

	// GlobalNav instrumentation.
	const navChecks = [
		{
			token: 'data-analytics-event-name',
			message: 'GlobalNav is missing data-analytics-event-name attributes.',
		},
		{
			token: 'homepage.install.cta.clicked',
			message: 'GlobalNav is missing homepage.install.cta.clicked event.',
		},
		{
			token: 'homepage.docs.clicked',
			message: 'GlobalNav is missing homepage.docs.clicked event.',
		},
		{
			token: 'homepage.workflow-guide.clicked',
			message: 'GlobalNav is missing homepage.workflow-guide.clicked event.',
		},
		{
			token: 'homepage.github.outbound.clicked',
			message: 'GlobalNav is missing homepage.github.outbound.clicked event.',
		},
	];

	for (const check of navChecks) {
		expectIncludes(
			globalNavSource,
			check.token,
			scope,
			paths.globalNav,
			check.message,
			'Restore explicit analytics data attributes for conversion-critical nav links.',
		);
	}

	// GlobalNav: source surface must resolve to "global-nav" or undefined.
	expectMatches(
		globalNavSource,
		/data-analytics-source-surface=\{[\s\S]*analyticsConfig[\s\S]*["']global-nav["'][\s\S]*undefined[\s\S]*\}/m,
		scope,
		paths.globalNav,
		"GlobalNav is missing data-analytics-source-surface={analyticsConfig ? 'global-nav' : undefined} binding.",
		'Restore conditional source-surface binding so untracked nav items do not emit surface attribution.',
	);

	// Hero instrumentation.
	const heroChecks = [
		'data-analytics-event-name="homepage.install.cta.clicked"',
		'data-analytics-event-name="homepage.docs.clicked"',
		'data-analytics-event-name="homepage.github.outbound.clicked"',
		'data-analytics-source-surface="hero"',
	];

	for (const token of heroChecks) {
		expectIncludes(
			heroSource,
			token,
			scope,
			paths.hero,
			`Hero is missing analytics instrumentation: ${token}`,
			'Restore explicit analytics data attributes for conversion-critical hero links.',
		);
	}

	// FinalCTA instrumentation.
	const finalCtaChecks = [
		'data-analytics-event-name="homepage.install.cta.clicked"',
		'data-analytics-event-name="homepage.docs.clicked"',
		'data-analytics-source-surface="final-cta"',
	];

	for (const token of finalCtaChecks) {
		expectIncludes(
			finalCtaSource,
			token,
			scope,
			paths.finalCta,
			`FinalCTA is missing analytics instrumentation: ${token}`,
			'Restore explicit analytics data attributes for conversion-critical final CTA links.',
		);
	}

	// TerminalDemo and FeatureGrid have no analytics — confirm Hero/FinalCTA are the only surfaces.
	// (No negative checks needed here; the positive checks above are sufficient.)
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

	expectIncludes(
		indexSource,
		'initializeInstallIntentHandoff',
		scope,
		filePath,
		'Missing install intent handoff initialization import/call.',
		'Restore initializeInstallIntentHandoff in index route startup script.',
	);

	const analyticsCallIndex = indexSource.indexOf('initializeHomepageAnalytics();');
	const installCallIndex = indexSource.indexOf('initializeInstallIntentHandoff();');

	if (
		analyticsCallIndex === -1 ||
		installCallIndex === -1 ||
		analyticsCallIndex > installCallIndex
	) {
		fail(
			scope,
			filePath,
			'Homepage analytics must initialize before install intent handoff.',
			'Move initializeHomepageAnalytics() before initializeInstallIntentHandoff().',
		);
	}

	// Ensure removed docs-handoff init is not present.
	if (indexSource.includes('initializeDocsHandoff')) {
		fail(
			scope,
			filePath,
			'Removed initializeDocsHandoff call is still present in index route.',
			'Remove initializeDocsHandoff — the docs-handoff module no longer exists.',
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
	const scope = 'build-gate:analytics-validator';
	const filePath = paths.packageJson;

	let parsed;
	try {
		parsed = JSON.parse(packageSource);
	} catch (error) {
		fail(
			scope,
			filePath,
			`Unable to parse package.json. ${error.message}`,
			'Restore valid package.json JSON before running analytics validation.',
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
			'Build script does not include analytics validation gate.',
			'Wire "bun run validate:story-5-5" into build before "astro build".',
		);
	}
}

function printFailuresAndExit() {
	console.error('[analytics] Validation failed.');
	console.error('[analytics] Remediation guidance follows:');

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
const heroSource = readRequiredFile(paths.hero, 'instrumentation:homepage-links');
const finalCtaSource = readRequiredFile(paths.finalCta, 'instrumentation:homepage-links');
const apiSource = readRequiredFile(paths.apiAnalytics, 'platform:analytics-relay');
const packageSource = readRequiredFile(paths.packageJson, 'build-gate:analytics-validator');

if (
	!analyticsSource ||
	!installIntentSource ||
	!indexSource ||
	!globalNavSource ||
	!heroSource ||
	!finalCtaSource ||
	!apiSource ||
	!packageSource
) {
	process.exit(1);
}

validateAnalyticsContract(analyticsSource);
validateInstallIntentBridge(installIntentSource);
validateTaggedInstrumentation(globalNavSource, heroSource, finalCtaSource);
validateInitializationOrdering(indexSource);
validateRelayApi(apiSource);
validatePackageScripts(packageSource);

if (failures.length > 0) {
	printFailuresAndExit();
}

console.log('[analytics] Validation passed.');
console.log(
	'[analytics] Canonical event contract, instrumentation, relay, and build gate are intact.',
);
