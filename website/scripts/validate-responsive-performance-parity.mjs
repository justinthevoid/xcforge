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
	hero: join(projectRoot, 'src', 'components', 'website', 'HeroProof.astro'),
	finalCta: join(projectRoot, 'src', 'components', 'website', 'FinalCTA.astro'),
	docsHandoff: join(projectRoot, 'src', 'components', 'website', 'DocsHandoffSection.astro'),
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
			'Restore the file before running Story 5.4 release checks.',
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

function countSupportingBindings(source) {
	const dataAttributeCount = countMatches(source, /data-supporting-path=["']true["']/g);
	const actionLinkPropCount = countMatches(
		source,
		/<ActionLink\b[^>]*\bsupportingPath=\{true\}[^>]*\/?>/g,
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

function validateNarrativeOrder(routeSource, snapshot) {
	const scope = 'responsive-hierarchy:narrative-order';
	const filePath = paths.route;
	const orderedModules = [
		'<HeroProof',
		'<ProblemSection',
		'<SolutionSection',
		'<WorkflowsJourneysSection',
		'<DifferentiationProofSection',
		'<DocsHandoffSection',
		'<FinalCTA',
	];

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
				'Homepage narrative section order no longer follows the required Hero -> Problem -> Solution -> Workflows -> Differentiation/Proof -> Docs Handoff -> Final CTA sequence.',
				'Reorder homepage module composition to preserve required narrative hierarchy.',
			);
			return;
		}
	}
}

function validateCtaTierContracts(heroSource, finalSource, snapshot) {
	const scope = 'responsive-hierarchy:cta-tier-contract';

	const heroPrimary = countTierBindings(heroSource, 'primary');
	const heroSecondary = countTierBindings(heroSource, 'secondary');
	const heroSupporting = countSupportingBindings(heroSource);

	const finalPrimary = countTierBindings(finalSource, 'primary');
	const finalSecondary = countTierBindings(finalSource, 'secondary');
	const finalSupporting = countSupportingBindings(finalSource);

	snapshot.ctaContract = {
		hero: { primary: heroPrimary, secondary: heroSecondary, supporting: heroSupporting },
		final: { primary: finalPrimary, secondary: finalSecondary, supporting: finalSupporting },
	};

	if (heroPrimary !== 1 || heroSecondary < 2 || heroSupporting < 2) {
		fail(
			scope,
			paths.hero,
			`Hero CTA contract drifted (primary=${heroPrimary}, secondary=${heroSecondary}, supporting=${heroSupporting}).`,
			'Restore one primary install action plus Docs/Workflow secondary supporting actions in HeroProof.',
		);
	}

	if (finalPrimary !== 1 || finalSecondary < 1 || finalSupporting < 1) {
		fail(
			scope,
			paths.finalCta,
			`Final CTA contract drifted (primary=${finalPrimary}, secondary=${finalSecondary}, supporting=${finalSupporting}).`,
			'Restore one primary install action plus one supporting workflow secondary action in FinalCTA.',
		);
	}
}

function validateResponsiveCssContracts(homepageSource, snapshot) {
	const scope = 'responsive-hierarchy:breakpoint-contracts';

	const hasDesktopHeroGrid =
		homepageSource.includes('.hero-proof {') &&
		homepageSource.includes('grid-template-columns: 1.18fr 1fr;');

	const tabletBlocks = extractMediaBlocks(
		homepageSource,
		/@media\s*\(\s*max-width:\s*1023px\s*\)/g,
	);
	const mobileBlocks = extractMediaBlocks(homepageSource, /@media\s*\(\s*max-width:\s*767px\s*\)/g);
	const tabletContent = tabletBlocks.join('\n');
	const mobileContent = mobileBlocks.join('\n');

	const tabletChecks = {
		blockPresent: tabletBlocks.length > 0,
		heroSingleColumn:
			tabletBlocks.length > 0 &&
			tabletContent.includes('.hero-proof') &&
			tabletContent.includes('grid-template-columns: 1fr;'),
		supportGridTwoColumn:
			tabletBlocks.length > 0 &&
			tabletContent.includes('.differentiation-grid,') &&
			tabletContent.includes('.handoff-grid') &&
			tabletContent.includes('grid-template-columns: repeat(2, minmax(0, 1fr));'),
		proofSnapshotSingleColumn:
			tabletBlocks.length > 0 &&
			tabletContent.includes('.proof-snapshot-grid') &&
			tabletContent.includes('grid-template-columns: 1fr;'),
		proofPanelRefinement:
			tabletBlocks.length > 0 &&
			tabletContent.includes('.proof-panel') &&
			tabletContent.includes('padding: 24px;'),
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
		supportGridSingleColumn:
			mobileBlocks.length > 0 &&
			mobileContent.includes('.differentiation-grid,') &&
			mobileContent.includes('.handoff-grid') &&
			mobileContent.includes('grid-template-columns: 1fr;'),
		proofSnapshotSingleColumn:
			mobileBlocks.length > 0 &&
			mobileContent.includes('.proof-snapshot-grid') &&
			mobileContent.includes('grid-template-columns: 1fr;'),
	};

	snapshot.breakpoints = {
		desktop: { hasDesktopHeroGrid },
		tablet: tabletChecks,
		mobile: mobileChecks,
	};

	if (!hasDesktopHeroGrid) {
		fail(
			scope,
			paths.homepageCss,
			'Desktop hero proof grid contract is missing the expected two-column baseline.',
			'Restore the desktop HeroProof grid baseline so conversion hierarchy remains coherent before breakpoint shifts.',
		);
	}

	for (const [check, pass] of Object.entries(tabletChecks)) {
		if (!pass) {
			fail(
				scope,
				paths.homepageCss,
				`Tablet breakpoint contract failed: ${check}.`,
				'Restore Story 5.4 tablet breakpoint hierarchy and proof legibility CSS contracts in @media (max-width: 1023px).',
			);
		}
	}

	for (const [check, pass] of Object.entries(mobileChecks)) {
		if (!pass) {
			fail(
				scope,
				paths.homepageCss,
				`Mobile breakpoint contract failed: ${check}.`,
				'Restore Story 5.4 mobile breakpoint hierarchy and CTA/proof parity contracts in @media (max-width: 767px).',
			);
		}
	}
}

function validatePerformanceBudgets(sources, snapshot) {
	const scope = 'performance-budget:critical-source-size';

	const measured = {
		homepageCss: Buffer.byteLength(sources.homepageSource, 'utf8'),
		tokensCss: Buffer.byteLength(sources.tokensSource, 'utf8'),
		primitivesCss: Buffer.byteLength(sources.primitivesSource, 'utf8'),
		indexRoute: Buffer.byteLength(sources.routeSource, 'utf8'),
		heroComponent: Buffer.byteLength(sources.heroSource, 'utf8'),
		finalCtaComponent: Buffer.byteLength(sources.finalSource, 'utf8'),
		docsHandoffComponent: Buffer.byteLength(sources.docsSource, 'utf8'),
	};

	measured.totalCritical =
		measured.homepageCss +
		measured.tokensCss +
		measured.primitivesCss +
		measured.indexRoute +
		measured.heroComponent +
		measured.finalCtaComponent +
		measured.docsHandoffComponent;

	const budgets = {
		homepageCss: 24000,
		tokensCss: 4000,
		primitivesCss: 5000,
		indexRoute: 3500,
		heroComponent: 6000,
		finalCtaComponent: 3500,
		docsHandoffComponent: 4000,
		totalCritical: 45000,
	};

	snapshot.performance = {
		measured,
		budgets,
	};

	for (const [key, budget] of Object.entries(budgets)) {
		const actual = measured[key];
		if (actual > budget) {
			fail(
				scope,
				key === 'homepageCss'
					? paths.homepageCss
					: key === 'tokensCss'
						? paths.tokensCss
						: key === 'primitivesCss'
							? paths.primitivesCss
							: key === 'indexRoute'
								? paths.route
								: key === 'heroComponent'
									? paths.hero
									: key === 'finalCtaComponent'
										? paths.finalCta
										: key === 'docsHandoffComponent'
											? paths.docsHandoff
											: paths.route,
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

function validateDegradedModeContracts(routeSource, heroSource, finalSource, docsSource, snapshot) {
	const scope = 'degraded-mode:operability-contract';

	const checks = {
		routeComputesFallback:
			routeSource.includes('const useProofFallback =') &&
			routeSource.includes('!isProofMetadataAvailable(homepageContent.hero)'),
		routePassesFallbackProp: /<HeroProof\b[^>]*\buseFallback=\{useProofFallback\}/m.test(
			routeSource,
		),
		heroFallbackBranch:
			heroSource.includes('useFallback ? (') &&
			heroSource.includes('hero.fallbackProofText') &&
			heroSource.includes('safeFallbackDocsHref'),
		heroInstallPrimaryAlwaysPresent:
			heroSource.includes('tier="primary"') &&
			heroSource.includes('install-intent-trigger') &&
			heroSource.includes('installCommand={hero.installCommand}'),
		finalInstallHandoffSemantic:
			finalSource.includes('data-install-handoff-command') &&
			finalSource.includes('data-copy-install-command') &&
			finalSource.includes('data-install-handoff-message'),
		docsLinksRemainRenderable:
			docsSource.includes('href={link.href}') &&
			docsSource.includes('data-handoff-fallback-href={') &&
			docsSource.includes('data-handoff-unavailable-message={'),
	};

	snapshot.degradedMode = checks;

	for (const [check, pass] of Object.entries(checks)) {
		if (!pass) {
			const filePath = check.startsWith('route')
				? paths.route
				: check.startsWith('hero')
					? paths.hero
					: check.startsWith('final')
						? paths.finalCta
						: paths.docsHandoff;

			fail(
				scope,
				filePath,
				`Degraded-mode contract failed: ${check}.`,
				'Restore static-safe fallback and install/supporting action operability contracts so conversion flows remain usable when optional dependencies degrade.',
			);
		}
	}
}

function writeFailureArtifacts(snapshot, sources) {
	const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
	const outputDir = join(projectRoot, '.artifacts', 'responsive-performance-parity', timestamp);
	mkdirSync(outputDir, { recursive: true });

	const summaryPath = join(outputDir, 'story-5-4-summary.json');
	writeFileSync(
		summaryPath,
		JSON.stringify(
			{
				checkedAt: new Date().toISOString(),
				story: '5.4-responsive-performance-parity',
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
			tokens: ['<HeroProof', '<FinalCTA', 'useProofFallback', '<script'],
		},
		{
			label: 'homepage-css',
			path: paths.homepageCss,
			source: sources.homepageSource,
			tokens: [
				'max-width: 1023px',
				'max-width: 767px',
				'.proof-snapshot-grid',
				'flex-direction: column',
			],
		},
		{
			label: 'hero-proof',
			path: paths.hero,
			source: sources.heroSource,
			tokens: ['useFallback ?', 'fallbackProofText', 'tier="primary"', 'install-intent-trigger'],
		},
		{
			label: 'final-cta',
			path: paths.finalCta,
			source: sources.finalSource,
			tokens: ['data-install-handoff-command', 'data-copy-install-command', 'tier="primary"'],
		},
		{
			label: 'docs-handoff',
			path: paths.docsHandoff,
			source: sources.docsSource,
			tokens: ['href={link.href}', 'fallbackHref', 'data-docs-handoff-link'],
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
	const finalSource = readRequiredFile(paths.finalCta, 'preflight');
	const docsSource = readRequiredFile(paths.docsHandoff, 'preflight');

	if (
		!routeSource ||
		!homepageSource ||
		!tokensSource ||
		!primitivesSource ||
		!heroSource ||
		!finalSource ||
		!docsSource
	) {
		const snapshot = {
			checkedAt: new Date().toISOString(),
			story: '5.4-responsive-performance-parity',
			preflightFailed: true,
		};

		const artifactDir = writeFailureArtifacts(snapshot, {
			routeSource: routeSource ?? '',
			homepageSource: homepageSource ?? '',
			heroSource: heroSource ?? '',
			finalSource: finalSource ?? '',
			docsSource: docsSource ?? '',
		});

		console.error(
			'\n[story-5-4] Responsive/performance parity validation failed during preflight.\n',
		);
		for (const [index, finding] of findings.entries()) {
			console.error(`${index + 1}. [${finding.scope}] ${rel(finding.filePath)}`);
			console.error(`   Issue: ${finding.message}`);
			console.error(`   Fix: ${finding.remediation}`);
		}

		console.error('\n[story-5-4] Release blocked.');
		console.error(
			`[story-5-4] Failure artifacts written to ${rel(artifactDir)}. Attach these files to remediation tasks.`,
		);
		process.exit(1);
	}

	const snapshot = {
		checkedAt: new Date().toISOString(),
		story: '5.4-responsive-performance-parity',
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
			finalSource,
			docsSource,
		},
		snapshot,
	);
	validateDegradedModeContracts(routeSource, heroSource, finalSource, docsSource, snapshot);

	if (findings.length > 0) {
		const artifactDir = writeFailureArtifacts(snapshot, {
			routeSource,
			homepageSource,
			heroSource,
			finalSource,
			docsSource,
		});

		console.error('\n[story-5-4] Responsive/performance parity validation failed.\n');
		for (const [index, finding] of findings.entries()) {
			console.error(`${index + 1}. [${finding.scope}] ${rel(finding.filePath)}`);
			console.error(`   Issue: ${finding.message}`);
			console.error(`   Fix: ${finding.remediation}`);
		}

		console.error('\n[story-5-4] Release blocked.');
		console.error(
			`[story-5-4] Failure artifacts written to ${rel(artifactDir)}. Attach these files to remediation tasks.`,
		);
		process.exit(1);
	}

	const perf = snapshot.performance;
	console.log(
		`[story-5-4] Checks passed. totalCritical=${perf.measured.totalCritical}/${perf.budgets.totalCritical} bytes, homepageCss=${perf.measured.homepageCss}/${perf.budgets.homepageCss} bytes, hero=${perf.measured.heroComponent}/${perf.budgets.heroComponent} bytes.`,
	);
}

main();
