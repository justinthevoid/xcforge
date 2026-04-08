#!/usr/bin/env bun

import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = join(dirname(fileURLToPath(import.meta.url)), '..');

const paths = {
	index: join(projectRoot, 'src', 'pages', 'index.astro'),
	tokens: join(projectRoot, 'src', 'styles', 'tokens.css'),
	primitives: join(projectRoot, 'src', 'styles', 'primitives.css'),
	homepage: join(projectRoot, 'src', 'styles', 'homepage.css'),
	hero: join(projectRoot, 'src', 'components', 'website', 'HeroProof.astro'),
	finalCta: join(projectRoot, 'src', 'components', 'website', 'FinalCTA.astro'),
	docsHandoff: join(projectRoot, 'src', 'components', 'website', 'DocsHandoffSection.astro'),
	problem: join(projectRoot, 'src', 'components', 'website', 'ProblemSection.astro'),
	solution: join(projectRoot, 'src', 'components', 'website', 'SolutionSection.astro'),
	workflows: join(projectRoot, 'src', 'components', 'website', 'WorkflowsJourneysSection.astro'),
	differentiation: join(
		projectRoot,
		'src',
		'components',
		'website',
		'DifferentiationProofSection.astro',
	),
	globalNav: join(projectRoot, 'src', 'components', 'website', 'GlobalNav.astro'),
	actionLink: join(projectRoot, 'src', 'components', 'primitives', 'ActionLink.astro'),
	sectionBlock: join(projectRoot, 'src', 'components', 'primitives', 'SectionBlock.astro'),
};

const errors = [];

function rel(filePath) {
	return relative(projectRoot, filePath) || '.';
}

function fail(message) {
	errors.push(message);
}

function readRequired(filePath) {
	if (!existsSync(filePath)) {
		fail(`Missing required file ${rel(filePath)}.`);
		return null;
	}

	const source = readFileSync(filePath, 'utf8');
	if (!source.trim()) {
		fail(`${rel(filePath)} is empty.`);
		return null;
	}

	return source;
}

function validateTokenLayer(tokensSource) {
	const requiredFamilies = [
		/--xcf-color-/,
		/--xcf-font-/,
		/--xcf-space-/,
		/--xcf-radius-/,
		/--xcf-motion-/,
		/--xcf-breakpoint-/,
	];

	if (!tokensSource.includes(':root')) {
		fail(`${rel(paths.tokens)} must declare :root as the canonical token source.`);
	}

	for (const family of requiredFamilies) {
		if (!family.test(tokensSource)) {
			fail(`${rel(paths.tokens)} is missing required token family ${family}.`);
		}
	}
}

function validatePrimitiveLayer(primitivesSource) {
	const requiredSelectors = [
		'.action-link',
		'.action-link-primary',
		'.action-link-secondary',
		'.section-block',
	];

	for (const selector of requiredSelectors) {
		if (!primitivesSource.includes(selector)) {
			fail(`${rel(paths.primitives)} is missing required primitive selector ${selector}.`);
		}
	}
}

function validateTokenDeclarationsOutsideCanonical(sources) {
	const tokenDeclarationPattern = /--xcf-[a-z0-9-]+\s*:/gi;

	for (const [filePath, source] of sources) {
		const matches = source.match(tokenDeclarationPattern) ?? [];
		if (matches.length > 0) {
			fail(
				`${rel(filePath)} redeclares canonical tokens (${matches
					.slice(0, 3)
					.join(', ')}). Define tokens only in ${rel(paths.tokens)}.`,
			);
		}
	}
}

function validateImportOrder(indexSource) {
	const styleImports = [...indexSource.matchAll(/import\s+['"]([^'"]+\.css)['"];?/g)].map(
		(match) => match[1],
	);
	const requiredOrder = [
		'../styles/tokens.css',
		'../styles/primitives.css',
		'../styles/homepage.css',
	];

	if (requiredOrder.some((importPath) => !styleImports.includes(importPath))) {
		fail(
			`${rel(paths.index)} must import tokens.css, primitives.css, and homepage.css for explicit layer order.`,
		);
		return;
	}

	const tokensIndex = styleImports.indexOf(requiredOrder[0]);
	const primitivesIndex = styleImports.indexOf(requiredOrder[1]);
	const homepageIndex = styleImports.indexOf(requiredOrder[2]);

	if (!(tokensIndex < primitivesIndex && primitivesIndex < homepageIndex)) {
		fail(
			`${rel(paths.index)} must import styles in layer order: tokens.css -> primitives.css -> homepage.css.`,
		);
	}
}

function validateRequiredPrimitiveComposition(filePath, source) {
	const hasActionLinkImport = /import\s+ActionLink\s+from\s+['"][^'"]*ActionLink\.astro['"]/.test(
		source,
	);
	const hasActionLinkUsage = /<ActionLink\b/.test(source);
	if (!hasActionLinkImport || !hasActionLinkUsage) {
		fail(`${rel(filePath)} must compose action UI through ActionLink primitive.`);
	}

	const hasSectionBlockImport =
		/import\s+SectionBlock\s+from\s+['"][^'"]*SectionBlock\.astro['"]/.test(source);
	const hasSectionBlockUsage = /<SectionBlock\b/.test(source);
	if (!hasSectionBlockImport || !hasSectionBlockUsage) {
		fail(`${rel(filePath)} must compose section structure through SectionBlock primitive.`);
	}
}

function validateNoInlineStyleOrHex(filePath, source) {
	if (/\sstyle=/.test(source) || /<style[\s>]/.test(source)) {
		fail(`${rel(filePath)} contains inline/style-block styling. Use tokenized CSS layers instead.`);
	}

	if (/#[0-9a-fA-F]{3,8}/.test(source)) {
		fail(`${rel(filePath)} contains hardcoded hex colors. Use semantic token-driven classes.`);
	}
}

function main() {
	const indexSource = readRequired(paths.index);
	const tokensSource = readRequired(paths.tokens);
	const primitivesSource = readRequired(paths.primitives);
	const homepageSource = readRequired(paths.homepage);
	const heroSource = readRequired(paths.hero);
	const finalCtaSource = readRequired(paths.finalCta);
	const docsHandoffSource = readRequired(paths.docsHandoff);
	const problemSource = readRequired(paths.problem);
	const solutionSource = readRequired(paths.solution);
	const workflowsSource = readRequired(paths.workflows);
	const differentiationSource = readRequired(paths.differentiation);
	const globalNavSource = readRequired(paths.globalNav);
	const actionLinkSource = readRequired(paths.actionLink);
	const sectionBlockSource = readRequired(paths.sectionBlock);

	if (
		!indexSource ||
		!tokensSource ||
		!primitivesSource ||
		!homepageSource ||
		!heroSource ||
		!finalCtaSource ||
		!docsHandoffSource ||
		!problemSource ||
		!solutionSource ||
		!workflowsSource ||
		!differentiationSource ||
		!globalNavSource ||
		!actionLinkSource ||
		!sectionBlockSource
	) {
		process.exit(1);
	}

	validateTokenLayer(tokensSource);
	validatePrimitiveLayer(primitivesSource);
	validateTokenDeclarationsOutsideCanonical([
		[paths.primitives, primitivesSource],
		[paths.homepage, homepageSource],
	]);
	validateImportOrder(indexSource);

	validateRequiredPrimitiveComposition(paths.hero, heroSource);
	validateRequiredPrimitiveComposition(paths.finalCta, finalCtaSource);
	validateRequiredPrimitiveComposition(paths.docsHandoff, docsHandoffSource);

	const componentSources = [
		[paths.hero, heroSource],
		[paths.finalCta, finalCtaSource],
		[paths.docsHandoff, docsHandoffSource],
		[paths.problem, problemSource],
		[paths.solution, solutionSource],
		[paths.workflows, workflowsSource],
		[paths.differentiation, differentiationSource],
		[paths.globalNav, globalNavSource],
		[paths.actionLink, actionLinkSource],
		[paths.sectionBlock, sectionBlockSource],
	];

	for (const [filePath, source] of componentSources) {
		validateNoInlineStyleOrHex(filePath, source);
	}

	if (errors.length > 0) {
		console.error('\n[design-system-contract] Validation failed.\n');
		errors.forEach((error, index) => {
			console.error(`${index + 1}. ${error}`);
		});
		console.error('\n[design-system-contract] Release blocked.');
		process.exit(1);
	}

	console.log(
		'[design-system-contract] Token, primitive, and product-component layer contract checks passed.',
	);
}

main();
