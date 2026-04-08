#!/usr/bin/env bun

import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = join(dirname(fileURLToPath(import.meta.url)), '..');

const componentPaths = {
	route: join(projectRoot, 'src', 'pages', 'index.astro'),
	hero: join(projectRoot, 'src', 'components', 'website', 'HeroProof.astro'),
	proofToggle: join(projectRoot, 'src', 'components', 'website', 'ProofToggle.svelte'),
	docsHandoff: join(projectRoot, 'src', 'components', 'website', 'DocsHandoffSection.astro'),
	finalCta: join(projectRoot, 'src', 'components', 'website', 'FinalCTA.astro'),
	primitives: join(projectRoot, 'src', 'styles', 'primitives.css'),
};

const routeId = '/';
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
			'Restore the file and re-run the accessibility foundation validator.',
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
				'Restore the expected implementation content before building.',
			);
			return null;
		}

		return source;
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		fail(
			scope,
			filePath,
			`Unable to read file. ${message}`,
			'Resolve filesystem/read issues and retry validation.',
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

function expectNotMatches(source, pattern, scope, filePath, message, remediation) {
	if (pattern.test(source)) {
		fail(scope, filePath, message, remediation);
	}
}

function validateRouteSemantics(routeSource) {
	const scope = `route:${routeId}`;
	const filePath = componentPaths.route;

	expectIncludes(
		routeSource,
		'href="#main-content"',
		scope,
		filePath,
		'Missing skip-link target for keyboard users.',
		'Restore the skip link to #main-content at the top of the body.',
	);

	expectIncludes(
		routeSource,
		'<main id="main-content">',
		scope,
		filePath,
		'Missing main landmark with id="main-content".',
		'Restore the primary main landmark and keep skip-link target aligned.',
	);

	expectIncludes(
		routeSource,
		'<GlobalNav',
		scope,
		filePath,
		'Primary navigation component is not composed on the homepage route.',
		'Include GlobalNav in the route composition to preserve keyboard and landmark flow.',
	);

	expectIncludes(
		routeSource,
		'<HeroProof',
		scope,
		filePath,
		'Hero proof module is missing from homepage composition.',
		'Restore HeroProof composition so critical journey accessibility checks remain valid.',
	);

	expectIncludes(
		routeSource,
		'<DocsHandoffSection',
		scope,
		filePath,
		'Docs handoff module is missing from homepage composition.',
		'Restore DocsHandoffSection composition for supporting-path accessibility coverage.',
	);

	expectIncludes(
		routeSource,
		'<FinalCTA',
		scope,
		filePath,
		'Final CTA module is missing from homepage composition.',
		'Restore FinalCTA composition for install-handoff accessibility coverage.',
	);
}

function validateHeroProof(heroSource) {
	const scope = `component:HeroProof (${routeId})`;
	const filePath = componentPaths.hero;

	expectIncludes(
		heroSource,
		'labelledBy="hero-title"',
		scope,
		filePath,
		'Hero section missing labelled heading contract.',
		'Ensure SectionBlock is labelled by hero-title to keep heading/landmark semantics explicit.',
	);

	expectIncludes(
		heroSource,
		'id="install-section"',
		scope,
		filePath,
		'Hero install action region is missing id="install-section".',
		'Restore install action region id for consistent keyboard and conversion checks.',
	);

	expectIncludes(
		heroSource,
		'role="group"',
		scope,
		filePath,
		'Hero action group role is missing.',
		'Keep hero CTA group semantics for assistive-technology action context.',
	);

	expectIncludes(
		heroSource,
		'<ProofToggle',
		scope,
		filePath,
		'Proof toggle module is missing from HeroProof.',
		'Restore proof toggle composition to preserve keyboard-operable proof controls.',
	);
}

function validateProofToggle(toggleSource) {
	const scope = `component:ProofToggle (${routeId})`;
	const filePath = componentPaths.proofToggle;

	expectMatches(
		toggleSource,
		/<button[^>]*on:keydown={_handleToggleKeydown}/m,
		scope,
		filePath,
		'Proof toggle controls are missing keyboard arrow-key handling.',
		'Place on:keydown handler on proof toggle buttons and keep left/right selection logic.',
	);

	expectIncludes(
		toggleSource,
		'aria-pressed={snapshot.id === activeSnapshotId}',
		scope,
		filePath,
		'Proof toggle buttons are missing pressed-state semantics.',
		'Keep aria-pressed bound to active snapshot state for assistive technologies.',
	);

	expectIncludes(
		toggleSource,
		'moveFocus: true',
		scope,
		filePath,
		'Arrow-key snapshot switching does not request focus follow behavior.',
		'Move focus to the newly selected proof toggle option during arrow-key navigation.',
	);

	expectIncludes(
		toggleSource,
		'(selected)',
		scope,
		filePath,
		'Selected-state text marker is missing, creating a color-only state risk.',
		'Keep explicit selected-state text in toggle labels in addition to visual styling.',
	);

	expectIncludes(
		toggleSource,
		'role="status" aria-live="polite"',
		scope,
		filePath,
		'Proof status live-region announcement is missing.',
		'Keep polite status announcements for proof state changes.',
	);
}

function validateDocsHandoff(docsSource) {
	const scope = `component:DocsHandoffSection (${routeId})`;
	const filePath = componentPaths.docsHandoff;

	expectIncludes(
		docsSource,
		'data-docs-handoff-status',
		scope,
		filePath,
		'Docs handoff status node is missing.',
		'Restore handoff status node so fallback guidance is announced to assistive technologies.',
	);

	expectIncludes(
		docsSource,
		'role="status"',
		scope,
		filePath,
		'Docs handoff status role is missing.',
		'Keep status role on docs handoff feedback output.',
	);

	expectIncludes(
		docsSource,
		'aria-atomic="true"',
		scope,
		filePath,
		'Docs handoff status announcements are missing aria-atomic.',
		'Keep aria-atomic on status output so updates are announced coherently.',
	);

	expectIncludes(
		docsSource,
		'aria-label="Docs and workflow handoff links"',
		scope,
		filePath,
		'Docs handoff link region lacks explicit semantic label.',
		'Restore descriptive label for docs/workflow handoff card region.',
	);
}

function validateFinalCta(finalSource) {
	const scope = `component:FinalCTA (${routeId})`;
	const filePath = componentPaths.finalCta;

	expectNotMatches(
		finalSource,
		/<code\s+[^>]*tabindex\s*=\s*["']0["']/i,
		scope,
		filePath,
		'Command code is focusable via tabindex, which is not an acceptable semantic control.',
		'Use a properly labeled readonly command region and keep copy as the interactive control.',
	);

	expectIncludes(
		finalSource,
		'class="install-handoff-command"',
		scope,
		filePath,
		'Install handoff command region class is missing.',
		'Restore semantic install command region used by styling and keyboard focus checks.',
	);

	expectNotMatches(
		finalSource,
		/data-install-handoff-command[^>]*role="textbox"/m,
		scope,
		filePath,
		'Install command region should not expose textbox role semantics.',
		'Use semantic preformatted text with explicit label instead of textbox role.',
	);

	expectMatches(
		finalSource,
		/<pre[^>]*data-install-handoff-command[^>]*tabindex="0"[^>]*aria-label="Install command"[^>]*>/m,
		scope,
		filePath,
		'Install command region is missing required accessible attributes.',
		'Keep install command region as labeled focusable preformatted text.',
	);

	expectMatches(
		finalSource,
		/<[^>]*data-install-handoff-message[^>]*role="status"[^>]*aria-atomic="true"[^>]*>/m,
		scope,
		filePath,
		'Install handoff status messaging semantics are incomplete.',
		'Keep status/atomic semantics on handoff message node.',
	);

	expectMatches(
		finalSource,
		/<button[^>]*type="button"[^>]*data-copy-install-command/m,
		scope,
		filePath,
		'Copy command button contract is missing.',
		'Restore explicit button-based copy control for keyboard operability.',
	);
}

function validateFocusStyles(primitivesSource) {
	const scope = `styles:primitives (${routeId})`;
	const filePath = componentPaths.primitives;

	const requiredFocusSelectors = [
		'.action-link:focus-visible',
		'.proof-toggle-button:focus-visible',
		'.copy-command:focus-visible',
		'.install-handoff-command:focus-visible',
		'.handoff-link:focus-visible',
	];

	for (const selector of requiredFocusSelectors) {
		expectIncludes(
			primitivesSource,
			selector,
			scope,
			filePath,
			`Missing required visible focus selector: ${selector}`,
			'Restore visible focus selector coverage for all critical journey controls.',
		);
	}
}

function printFailuresAndExit() {
	console.error(`[accessibility foundation] Validation failed for route "${routeId}".`);
	console.error('[accessibility foundation] Remediation guidance follows:');

	for (let index = 0; index < failures.length; index += 1) {
		const failure = failures[index];
		console.error(
			`${index + 1}. [${failure.scope}] ${rel(failure.filePath)} :: ${failure.message}`,
		);
		console.error(`   Remediation: ${failure.remediation}`);
	}

	process.exit(1);
}

try {
	const routeSource = readRequiredFile(componentPaths.route, `route:${routeId}`);
	const heroSource = readRequiredFile(componentPaths.hero, `component:HeroProof (${routeId})`);
	const toggleSource = readRequiredFile(
		componentPaths.proofToggle,
		`component:ProofToggle (${routeId})`,
	);
	const docsSource = readRequiredFile(
		componentPaths.docsHandoff,
		`component:DocsHandoffSection (${routeId})`,
	);
	const finalSource = readRequiredFile(componentPaths.finalCta, `component:FinalCTA (${routeId})`);
	const primitivesSource = readRequiredFile(
		componentPaths.primitives,
		`styles:primitives (${routeId})`,
	);

	if (routeSource) validateRouteSemantics(routeSource);
	if (heroSource) validateHeroProof(heroSource);
	if (toggleSource) validateProofToggle(toggleSource);
	if (docsSource) validateDocsHandoff(docsSource);
	if (finalSource) validateFinalCta(finalSource);
	if (primitivesSource) validateFocusStyles(primitivesSource);

	if (failures.length > 0) {
		printFailuresAndExit();
	}

	console.log(
		'[accessibility foundation] Keyboard and semantic foundation checks passed for route "/".',
	);
} catch (error) {
	const message = error instanceof Error ? error.message : String(error);
	console.error(`[accessibility foundation] Unexpected validation error: ${message}`);
	process.exit(1);
}
