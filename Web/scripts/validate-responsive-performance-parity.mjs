#!/usr/bin/env bun

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const findings = [];

const paths = {
	route: join(projectRoot, 'src', 'pages', 'index.astro'),
	homepageCss: join(projectRoot, 'src', 'styles', 'homepage.css'),
	tokensCss: join(projectRoot, 'src', 'styles', 'tokens.css'),
	primitivesCss: join(projectRoot, 'src', 'styles', 'primitives.css'),
	hero: join(projectRoot, 'src', 'components', 'web', 'Hero.astro'),
	terminalDemo: join(projectRoot, 'src', 'components', 'web', 'TerminalDemo.astro'),
	featureGrid: join(projectRoot, 'src', 'components', 'web', 'FeatureGrid.astro'),
	finalCta: join(projectRoot, 'src', 'components', 'web', 'FinalCTA.astro'),
};

function rel(filePath) {
	return relative(projectRoot, filePath) || '.';
}

function fail(scope, filePath, message, remediation) {
	findings.push({ scope, filePath, message, remediation });
}

function readRequiredFile(filePath, scope) {
	if (!existsSync(filePath)) {
		fail(
			scope,
			filePath,
			'Required file is missing.',
			'Restore the file before running responsive/performance parity checks.',
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
				'Restore expected implementation content before release validation.',
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
			'Resolve filesystem access issues and retry.',
		);
		return null;
	}
}

function countMatches(source, pattern) {
	return [...source.matchAll(pattern)].length;
}

function countTierBindings(source, tier) {
	const dataAttributeCount = countMatches(
		source,
		new RegExp(`data-action-tier=["']${tier}["']`, 'g'),
	);
	const actionLinkPropCount = countMatches(
		source,
		new RegExp(`<ActionLink\\b[^>]*\\btier=["']${tier}["'][^>]*\\/?>`, 'g'),
	);

	return Math.max(dataAttributeCount, actionLinkPropCount);
}

function extractMediaBlocks(source, mediaPattern) {
	const blocks = [];
	const pattern = new RegExp(
		mediaPattern.source,
		mediaPattern.flags.includes('g') ? mediaPattern.flags : `${mediaPattern.flags}g`,
	);

	for (const match of source.matchAll(pattern)) {
		const startIndex = match.index ?? -1;
		if (startIndex < 0) {
			continue;
		}

		const firstBraceIndex = source.indexOf('{', startIndex);
		if (firstBraceIndex < 0) {
			continue;
		}

		let depth = 0;
		let end = -1;

		for (let index = firstBraceIndex; index < source.length; index += 1) {
			const char = source[index];
			if (char === '{') {
				depth += 1;
			} else if (char === '}') {
				depth -= 1;
				if (depth === 0) {
					end = index;
					break;
				}
			}
		}

		if (end < 0) {
			continue;
		}

		blocks.push(source.slice(firstBraceIndex + 1, end));
	}

	return blocks;
}

function extractLinesContaining(source, token, limit = 4) {
	const lines = source.split(/\r?\n/);
	const matched = [];

	for (let index = 0; index < lines.length; index += 1) {
		if (lines[index].includes(token)) {
			matched.push(`${index + 1}: ${lines[index]}`);
		}

		if (matched.length >= limit) {
			break;
		}
	}

	return matched;
}

/**
 * Validates that index.astro composes the four new sections in order:
 * Hero -> TerminalDemo -> FeatureGrid -> FinalCTA
 */
function validateNarrativeOrder(routeSource, snapshot) {
	const scope = 'responsive-hierarchy:narrative-order';
	const filePath = paths.route;

	const orderedModules = ['<Hero', '<TerminalDemo', '<FeatureGrid', '<FinalCTA'];
	const positions = orderedModules.map((moduleToken) => routeSource.indexOf(moduleToken));

	snapshot.routeOrder = orderedModules.map((moduleToken, index) => ({
		module: moduleToken,
		position: positions[index],
	}));

	for (let index = 0; index < positions.length; index += 1) {
		if (positions[index] < 0) {
			fail(
				scope,
				filePath,
				`Homepage composition is missing required module ${orderedModules[index]}.`,
				'Restore the required section module so narrative ordering remains intact across breakpoints.',
			);
			return;
		}
	}

	for (let index = 1; index < positions.length; index += 1) {
		if (positions[index] <= positions[index - 1]) {
			fail(
				scope,
				filePath,
				'Homepage narrative section order no longer follows the required Hero -> TerminalDemo -> FeatureGrid -> FinalCTA sequence.',
				'Reorder homepage module composition to preserve required narrative hierarchy.',
			);
			return;
		}
	}
}

/**
 * Validates the primary/secondary action-tier counts in Hero and FinalCTA.
 * Hero: 1 primary install CTA + 2 secondary links (Docs, GitHub).
 * FinalCTA: 1 primary install CTA + 1 secondary docs link.
 */
function validateCtaTierContracts(heroSource, finalSource, snapshot) {
	const scope = 'responsive-hierarchy:cta-tier-contract';

	const heroPrimary = countTierBindings(heroSource, 'primary');
	const heroSecondary = countTierBindings(heroSource, 'secondary');

	const finalPrimary = countTierBindings(finalSource, 'primary');
	const finalSecondary = countTierBindings(finalSource, 'secondary');

	snapshot.ctaContract = {
		hero: { primary: heroPrimary, secondary: heroSecondary },
		final: { primary: finalPrimary, secondary: finalSecondary },
	};

	if (heroPrimary !== 1 || heroSecondary < 2) {
		fail(
			scope,
			paths.hero,
			`Hero CTA contract drifted (primary=${heroPrimary}, secondary=${heroSecondary}).`,
			'Restore one primary install action plus Docs/GitHub secondary actions in Hero.',
		);
	}

	if (finalPrimary !== 1 || finalSecondary < 1) {
		fail(
			scope,
			paths.finalCta,
			`Final CTA contract drifted (primary=${finalPrimary}, secondary=${finalSecondary}).`,
			'Restore one primary install action plus one secondary docs link in FinalCTA.',
		);
	}
}

/**
 * Validates that homepage.css has the expected breakpoint contracts.
 */
function validateResponsiveCssContracts(homepageSource, snapshot) {
	const scope = 'responsive-hierarchy:breakpoint-contracts';

	// Desktop: hero should be a flex column layout.
	const hasDesktopHeroLayout =
		homepageSource.includes('.hero {') &&
		homepageSource.includes('.hero-content {') &&
		homepageSource.includes('.hero-actions {');

	// Desktop: feature grid should be a multi-column grid.
	const hasDesktopFeatureGrid =
		homepageSource.includes('.feature-grid {') &&
		homepageSource.includes('grid-template-columns: repeat(3,');

	const tabletBlocks = extractMediaBlocks(
		homepageSource,
		/@media\s*\(\s*max-width:\s*1023px\s*\)/g,
	);
	const mobileBlocks = extractMediaBlocks(homepageSource, /@media\s*\(\s*max-width:\s*767px\s*\)/g);
	const tabletContent = tabletBlocks.join('\n');
	const mobileContent = mobileBlocks.join('\n');

	const tabletChecks = {
		blockPresent: tabletBlocks.length > 0,
		featureGridTwoColumn:
			tabletBlocks.length > 0 &&
			tabletContent.includes('.feature-grid') &&
			tabletContent.includes('repeat(2, minmax(0, 1fr))'),
	};

	const mobileChecks = {
		blockPresent: mobileBlocks.length > 0,
		ctaStacking:
			mobileBlocks.length > 0 &&
			mobileContent.includes('.hero-actions') &&
			mobileContent.includes('.final-cta-actions') &&
			mobileContent.includes('flex-direction: column;'),
		ctaFullWidth:
			mobileBlocks.length > 0 &&
			mobileContent.includes('.hero-actions .cta-primary[data-action-tier="primary"]') &&
			mobileContent.includes('.hero-actions .cta-secondary[data-action-tier="secondary"]') &&
			mobileContent.includes('.final-cta-actions .cta-primary[data-action-tier="primary"]') &&
			mobileContent.includes('.final-cta-actions .cta-secondary[data-action-tier="secondary"]') &&
			mobileContent.includes('width: 100%') &&
			mobileContent.includes('justify-content: center;'),
		featureGridSingleColumn:
			mobileBlocks.length > 0 &&
			mobileContent.includes('.feature-grid') &&
			mobileContent.includes('grid-template-columns: 1fr;'),
		navStacks:
			mobileBlocks.length > 0 &&
			mobileContent.includes('.global-nav') &&
			mobileContent.includes('flex-direction: column;'),
	};

	snapshot.breakpoints = {
		desktop: { hasDesktopHeroLayout, hasDesktopFeatureGrid },
		tablet: tabletChecks,
		mobile: mobileChecks,
	};

	if (!hasDesktopHeroLayout) {
		fail(
			scope,
			paths.homepageCss,
			'Desktop hero layout contract is missing expected .hero, .hero-content, and .hero-actions rules.',
			'Restore the desktop Hero layout rules so the hero renders headline and install steps correctly.',
		);
	}

	if (!hasDesktopFeatureGrid) {
		fail(
			scope,
			paths.homepageCss,
			'Desktop feature grid contract is missing expected 3-column grid-template-columns rule.',
			'Restore the desktop FeatureGrid 3-column layout rule.',
		);
	}

	for (const [check, pass] of Object.entries(tabletChecks)) {
		if (!pass) {
			fail(
				scope,
				paths.homepageCss,
				`Tablet breakpoint contract failed: ${check}.`,
				'Restore tablet breakpoint hierarchy contracts in @media (max-width: 1023px).',
			);
		}
	}

	for (const [check, pass] of Object.entries(mobileChecks)) {
		if (!pass) {
			fail(
				scope,
				paths.homepageCss,
				`Mobile breakpoint contract failed: ${check}.`,
				'Restore mobile breakpoint hierarchy and CTA parity contracts in @media (max-width: 767px).',
			);
		}
	}
}

/**
 * Validates that critical source files stay within size budgets.
 */
function validatePerformanceBudgets(sources, snapshot) {
	const scope = 'performance-budget:critical-source-size';

	const measured = {
		homepageCss: Buffer.byteLength(sources.homepageSource, 'utf8'),
		tokensCss: Buffer.byteLength(sources.tokensSource, 'utf8'),
		primitivesCss: Buffer.byteLength(sources.primitivesSource, 'utf8'),
		indexRoute: Buffer.byteLength(sources.routeSource, 'utf8'),
		heroComponent: Buffer.byteLength(sources.heroSource, 'utf8'),
		terminalDemoComponent: Buffer.byteLength(sources.terminalDemoSource, 'utf8'),
		featureGridComponent: Buffer.byteLength(sources.featureGridSource, 'utf8'),
		finalCtaComponent: Buffer.byteLength(sources.finalSource, 'utf8'),
	};

	measured.totalCritical =
		measured.homepageCss +
		measured.tokensCss +
		measured.primitivesCss +
		measured.indexRoute +
		measured.heroComponent +
		measured.terminalDemoComponent +
		measured.featureGridComponent +
		measured.finalCtaComponent;

	// Budgets (bytes): the new homepage is leaner — no proof panels, no workflow grids.
	const budgets = {
		homepageCss: 24000,
		tokensCss: 4000,
		primitivesCss: 5000,
		indexRoute: 3500,
		heroComponent: 4000,
		terminalDemoComponent: 3500,
		featureGridComponent: 3000,
		finalCtaComponent: 4000,
		totalCritical: 45000,
	};

	const pathByKey = {
		homepageCss: paths.homepageCss,
		tokensCss: paths.tokensCss,
		primitivesCss: paths.primitivesCss,
		indexRoute: paths.route,
		heroComponent: paths.hero,
		terminalDemoComponent: paths.terminalDemo,
		featureGridComponent: paths.featureGrid,
		finalCtaComponent: paths.finalCta,
		totalCritical: paths.homepageCss,
	};

	snapshot.performance = { measured, budgets };

	for (const [key, budget] of Object.entries(budgets)) {
		const actual = measured[key];
		if (actual > budget) {
			fail(
				scope,
				pathByKey[key] ?? paths.route,
				`Performance budget exceeded for ${key}: ${actual} bytes (budget ${budget} bytes).`,
				'Reduce conversion-critical source size or simplify non-essential styles/content to preserve first-impression performance.',
			);
		}
	}

	if (/<script[^>]*\bsrc\s*=\s*["'][^"']+["'][^>]*>/i.test(sources.routeSource)) {
		fail(
			'performance-budget:blocking-script-contract',
			paths.route,
			'Homepage route introduced a script src tag that can block first impression and CTA access.',
			'Keep conversion-critical homepage script loading local-module based and avoid external blocking script tags.',
		);
	}
}

/**
 * Validates that the install handoff runtime contract is intact (data attributes
 * and static-safe structure) so the conversion flow works after JS hydration.
 */
function validateInstallHandoffContracts(routeSource, finalSource, snapshot) {
	const scope = 'degraded-mode:install-handoff-contract';

	const checks = {
		finalHasHandoffDataAttr: finalSource.includes('data-install-handoff'),
		finalHasCommandNode: finalSource.includes('data-install-handoff-command'),
		finalHasCopyButton: finalSource.includes('data-copy-install-command'),
		finalHasMessageNode: finalSource.includes('data-install-handoff-message'),
		finalHasGuideLinkNode: finalSource.includes('data-install-handoff-guide-link'),
		routeImportsInstallIntent: routeSource.includes('initializeInstallIntentHandoff'),
		routeImportsAnalytics: routeSource.includes('initializeHomepageAnalytics'),
	};

	snapshot.installHandoff = checks;

	for (const [check, pass] of Object.entries(checks)) {
		if (!pass) {
			const filePath = check.startsWith('route') ? paths.route : paths.finalCta;
			fail(
				scope,
				filePath,
				`Install handoff contract failed: ${check}.`,
				'Restore install handoff data attributes and initialization calls so conversion flows remain usable.',
			);
		}
	}
}

function writeFailureArtifacts(snapshot, sources) {
	const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
	const outputDir = join(projectRoot, '.artifacts', 'responsive-performance-parity', timestamp);
	mkdirSync(outputDir, { recursive: true });

	const summaryPath = join(outputDir, 'summary.json');
	writeFileSync(
		summaryPath,
		JSON.stringify(
			{
				checkedAt: new Date().toISOString(),
				homepage: 'hero-terminal-features-finalcta',
				findings,
				snapshot,
			},
			null,
			2,
		),
	);

	const snippetSpecs = [
		{
			label: 'route',
			path: paths.route,
			source: sources.routeSource,
			tokens: ['<Hero', '<FinalCTA', 'initializeInstallIntentHandoff', '<script'],
		},
		{
			label: 'homepage-css',
			path: paths.homepageCss,
			source: sources.homepageSource,
			tokens: [
				'max-width: 1023px',
				'max-width: 767px',
				'.feature-grid',
				'flex-direction: column',
			],
		},
		{
			label: 'hero',
			path: paths.hero,
			source: sources.heroSource,
			tokens: ['tier="primary"', 'install-intent-trigger', 'id="install-section"'],
		},
		{
			label: 'final-cta',
			path: paths.finalCta,
			source: sources.finalSource,
			tokens: ['data-install-handoff-command', 'data-copy-install-command', 'tier="primary"'],
		},
	];

	for (const spec of snippetSpecs) {
		const lines = [`Source: ${rel(spec.path)}`, ''];
		for (const token of spec.tokens) {
			lines.push(...extractLinesContaining(spec.source, token));
		}

		writeFileSync(join(outputDir, `${spec.label}.snapshot.txt`), lines.join('\n'));
	}

	return outputDir;
}

function main() {
	const routeSource = readRequiredFile(paths.route, 'preflight');
	const homepageSource = readRequiredFile(paths.homepageCss, 'preflight');
	const tokensSource = readRequiredFile(paths.tokensCss, 'preflight');
	const primitivesSource = readRequiredFile(paths.primitivesCss, 'preflight');
	const heroSource = readRequiredFile(paths.hero, 'preflight');
	const terminalDemoSource = readRequiredFile(paths.terminalDemo, 'preflight');
	const featureGridSource = readRequiredFile(paths.featureGrid, 'preflight');
	const finalSource = readRequiredFile(paths.finalCta, 'preflight');

	if (
		!routeSource ||
		!homepageSource ||
		!tokensSource ||
		!primitivesSource ||
		!heroSource ||
		!terminalDemoSource ||
		!featureGridSource ||
		!finalSource
	) {
		const snapshot = {
			checkedAt: new Date().toISOString(),
			homepage: 'hero-terminal-features-finalcta',
			preflightFailed: true,
		};

		const artifactDir = writeFailureArtifacts(snapshot, {
			routeSource: routeSource ?? '',
			homepageSource: homepageSource ?? '',
			heroSource: heroSource ?? '',
			finalSource: finalSource ?? '',
		});

		console.error(
			'\n[responsive-performance-parity] Validation failed during preflight.\n',
		);
		for (const [index, finding] of findings.entries()) {
			console.error(`${index + 1}. [${finding.scope}] ${rel(finding.filePath)}`);
			console.error(`   Issue: ${finding.message}`);
			console.error(`   Fix: ${finding.remediation}`);
		}

		console.error('\n[responsive-performance-parity] Release blocked.');
		console.error(
			`[responsive-performance-parity] Failure artifacts written to ${rel(artifactDir)}. Attach these files to remediation tasks.`,
		);
		process.exit(1);
	}

	const snapshot = {
		checkedAt: new Date().toISOString(),
		homepage: 'hero-terminal-features-finalcta',
	};

	validateNarrativeOrder(routeSource, snapshot);
	validateCtaTierContracts(heroSource, finalSource, snapshot);
	validateResponsiveCssContracts(homepageSource, snapshot);
	validatePerformanceBudgets(
		{
			routeSource,
			homepageSource,
			tokensSource,
			primitivesSource,
			heroSource,
			terminalDemoSource,
			featureGridSource,
			finalSource,
		},
		snapshot,
	);
	validateInstallHandoffContracts(routeSource, finalSource, snapshot);

	if (findings.length > 0) {
		const artifactDir = writeFailureArtifacts(snapshot, {
			routeSource,
			homepageSource,
			heroSource,
			finalSource,
		});

		console.error('\n[responsive-performance-parity] Validation failed.\n');
		for (const [index, finding] of findings.entries()) {
			console.error(`${index + 1}. [${finding.scope}] ${rel(finding.filePath)}`);
			console.error(`   Issue: ${finding.message}`);
			console.error(`   Fix: ${finding.remediation}`);
		}

		console.error('\n[responsive-performance-parity] Release blocked.');
		console.error(
			`[responsive-performance-parity] Failure artifacts written to ${rel(artifactDir)}. Attach these files to remediation tasks.`,
		);
		process.exit(1);
	}

	const perf = snapshot.performance;
	console.log(
		`[responsive-performance-parity] Checks passed. totalCritical=${perf.measured.totalCritical}/${perf.budgets.totalCritical} bytes, homepageCss=${perf.measured.homepageCss}/${perf.budgets.homepageCss} bytes, hero=${perf.measured.heroComponent}/${perf.budgets.heroComponent} bytes.`,
	);
}

main();
