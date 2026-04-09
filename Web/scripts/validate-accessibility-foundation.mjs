#!/usr/bin/env bun

import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = join(dirname(fileURLToPath(import.meta.url)), '..');

const componentPaths = {
	route: join(projectRoot, 'src', 'pages', 'index.astro'),
	hero: join(projectRoot, 'src', 'components', 'web', 'Hero.astro'),
	terminalDemo: join(projectRoot, 'src', 'components', 'web', 'TerminalDemo.astro'),
	featureGrid: join(projectRoot, 'src', 'components', 'web', 'FeatureGrid.astro'),
	finalCta: join(projectRoot, 'src', 'components', 'web', 'FinalCTA.astro'),
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
		'<Hero',
		scope,
		filePath,
		'Hero component is missing from homepage composition.',
		'Restore Hero composition so critical journey accessibility checks remain valid.',
	);

	expectIncludes(
		routeSource,
		'<TerminalDemo',
		scope,
		filePath,
		'TerminalDemo component is missing from homepage composition.',
		'Restore TerminalDemo composition for section ordering accessibility coverage.',
	);

	expectIncludes(
		routeSource,
		'<FeatureGrid',
		scope,
		filePath,
		'FeatureGrid component is missing from homepage composition.',
		'Restore FeatureGrid composition for feature list accessibility coverage.',
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

function validateHero(heroSource) {
	const scope = `component:Hero (${routeId})`;
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
		'aria-label="Install commands"',
		scope,
		filePath,
		'Hero install terminal block is missing accessible label.',
		'Keep aria-label on the install-terminal div for screen reader context.',
	);
}

function validateTerminalDemo(demoSource) {
	const scope = `component:TerminalDemo (${routeId})`;
	const filePath = componentPaths.terminalDemo;

	expectIncludes(
		demoSource,
		'labelledBy="demo-title"',
		scope,
		filePath,
		'TerminalDemo section missing labelled heading contract.',
		'Ensure SectionBlock is labelled by demo-title to keep heading/landmark semantics explicit.',
	);

	expectIncludes(
		demoSource,
		'id="demo-title"',
		scope,
		filePath,
		'TerminalDemo section heading is missing id="demo-title".',
		'Restore demo-title id for consistent heading/landmark association.',
	);

	// Terminal window uses role="img" with an aria-label for meaningful non-interactive content.
	expectMatches(
		demoSource,
		/role="img"[^>]*aria-label=|aria-label=[^>]*role="img"/m,
		scope,
		filePath,
		'Terminal window is missing role="img" and aria-label for assistive technologies.',
		'Keep the terminal-window div labeled with role="img" and a descriptive aria-label.',
	);

	// Prompt characters are hidden from screen readers.
	expectIncludes(
		demoSource,
		'aria-hidden="true"',
		scope,
		filePath,
		'Terminal prompt characters are missing aria-hidden to suppress decorative repetition.',
		'Keep aria-hidden="true" on terminal prompt spans.',
	);
}

function validateFeatureGrid(gridSource) {
	const scope = `component:FeatureGrid (${routeId})`;
	const filePath = componentPaths.featureGrid;

	expectIncludes(
		gridSource,
		'labelledBy="features-title"',
		scope,
		filePath,
		'FeatureGrid section missing labelled heading contract.',
		'Ensure SectionBlock is labelled by features-title to keep heading/landmark semantics explicit.',
	);

	expectIncludes(
		gridSource,
		'id="features-title"',
		scope,
		filePath,
		'FeatureGrid section heading is missing id="features-title".',
		'Restore features-title id for consistent heading/landmark association.',
	);

	// Feature grid uses role="list" with role="listitem" on articles.
	expectIncludes(
		gridSource,
		'role="list"',
		scope,
		filePath,
		'Feature grid is missing role="list" semantics.',
		'Keep role="list" on the feature-grid div for list traversal by assistive technologies.',
	);

	expectIncludes(
		gridSource,
		'role="listitem"',
		scope,
		filePath,
		'Feature cards are missing role="listitem" semantics.',
		'Keep role="listitem" on feature-card articles.',
	);

	// Feature marker icons should be hidden from screen readers.
	expectIncludes(
		gridSource,
		'aria-hidden="true"',
		scope,
		filePath,
		'Feature marker icons are missing aria-hidden to suppress decorative content.',
		'Keep aria-hidden="true" on feature-marker spans.',
	);
}

function validateFinalCta(finalSource) {
	const scope = `component:FinalCTA (${routeId})`;
	const filePath = componentPaths.finalCta;

	expectIncludes(
		finalSource,
		'labelledBy="final-cta-title"',
		scope,
		filePath,
		'FinalCTA section missing labelled heading contract.',
		'Ensure SectionBlock is labelled by final-cta-title to keep heading/landmark semantics explicit.',
	);

	expectIncludes(
		finalSource,
		'id="final-cta-title"',
		scope,
		filePath,
		'FinalCTA heading is missing id="final-cta-title".',
		'Restore final-cta-title id for consistent heading/landmark association.',
	);

	// The standalone copy button in the install block must be a button, not a link.
	expectNotMatches(
		finalSource,
		/<code\s+[^>]*tabindex\s*=\s*["']0["']/i,
		scope,
		filePath,
		'Command code is focusable via tabindex, which is not an acceptable semantic control.',
		'Use a properly labeled readonly command region and keep copy as the interactive control.',
	);

	// Install handoff semantic region.
	expectIncludes(
		finalSource,
		'class="install-handoff-command"',
		scope,
		filePath,
		'Install handoff command region class is missing.',
		'Restore semantic install command region used by styling and keyboard focus checks.',
	);

	// The handoff install command must be a labeled, focusable preformatted region.
	expectMatches(
		finalSource,
		/<pre[^>]*data-install-handoff-command[^>]*tabindex="0"[^>]*aria-label="Install command"[^>]*>/m,
		scope,
		filePath,
		'Install command region is missing required accessible attributes.',
		'Keep install command region as labeled focusable preformatted text.',
	);

	// The handoff status message must have status role with aria-atomic.
	expectMatches(
		finalSource,
		/<[^>]*data-install-handoff-message[^>]*role="status"[^>]*aria-atomic="true"[^>]*>/m,
		scope,
		filePath,
		'Install handoff status messaging semantics are incomplete.',
		'Keep status/atomic semantics on handoff message node.',
	);

	// Copy button must be a proper button element.
	expectMatches(
		finalSource,
		/<button[^>]*type="button"[^>]*data-copy-install-command/m,
		scope,
		filePath,
		'Copy command button contract is missing.',
		'Restore explicit button-based copy control for keyboard operability.',
	);

	// Install handoff region uses aria-live for polite announcements.
	expectIncludes(
		finalSource,
		'aria-live="polite"',
		scope,
		filePath,
		'Install handoff region is missing aria-live="polite" for assistive technology updates.',
		'Keep aria-live="polite" on the install-handoff section.',
	);
}

function validateFocusStyles(primitivesSource) {
	const scope = `styles:primitives (${routeId})`;
	const filePath = componentPaths.primitives;

	const requiredFocusSelectors = [
		'.action-link:focus-visible',
		'.copy-command:focus-visible',
		'.install-handoff-command:focus-visible',
		'.install-handoff-link:focus-visible',
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
	const heroSource = readRequiredFile(componentPaths.hero, `component:Hero (${routeId})`);
	const demoSource = readRequiredFile(componentPaths.terminalDemo, `component:TerminalDemo (${routeId})`);
	const gridSource = readRequiredFile(componentPaths.featureGrid, `component:FeatureGrid (${routeId})`);
	const finalSource = readRequiredFile(componentPaths.finalCta, `component:FinalCTA (${routeId})`);
	const primitivesSource = readRequiredFile(
		componentPaths.primitives,
		`styles:primitives (${routeId})`,
	);

	if (routeSource) validateRouteSemantics(routeSource);
	if (heroSource) validateHero(heroSource);
	if (demoSource) validateTerminalDemo(demoSource);
	if (gridSource) validateFeatureGrid(gridSource);
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
