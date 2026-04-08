#!/usr/bin/env bun

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homepageContent, resolveNavigationMetadata } from '../src/data/homepage.ts';

const projectRoot = join(dirname(fileURLToPath(import.meta.url)), '..');

const componentPaths = {
	nav: join(projectRoot, 'src', 'components', 'website', 'GlobalNav.astro'),
	hero: join(projectRoot, 'src', 'components', 'website', 'HeroProof.astro'),
	finalCta: join(projectRoot, 'src', 'components', 'website', 'FinalCTA.astro'),
	docsHandoff: join(projectRoot, 'src', 'components', 'website', 'DocsHandoffSection.astro'),
	homepageCss: join(projectRoot, 'src', 'styles', 'homepage.css'),
	installIntent: join(projectRoot, 'src', 'lib', 'install-intent.ts'),
};

const errors = [];

function rel(filePath) {
	return relative(projectRoot, filePath) || '.';
}

function fail(message) {
	errors.push(message);
}

function readRequiredFile(filePath) {
	if (!existsSync(filePath)) {
		fail(`Missing required file ${rel(filePath)}.`);
		return null;
	}

	try {
		const source = readFileSync(filePath, 'utf8');
		if (!source.trim()) {
			fail(`${rel(filePath)} is empty.`);
			return null;
		}
		return source;
	} catch (error) {
		fail(`Unable to read ${rel(filePath)}. ${error.message}`);
		return null;
	}
}

function countMatches(source, pattern) {
	return [...source.matchAll(pattern)].length;
}

function countTierBindings(source, tier) {
	return (
		countMatches(source, new RegExp(`data-action-tier=["']${tier}["']`, 'g')) +
		countMatches(source, new RegExp(`<ActionLink\\b[^>]*\\btier=["']${tier}["'][^>]*\\/?>`, 'g'))
	);
}

function countSupportingBindings(source) {
	return (
		countMatches(source, /data-supporting-path=["']true["']/g) +
		countMatches(source, /<ActionLink\b[^>]*\bsupportingPath=\{true\}[^>]*\/?>/g)
	);
}

function toSnapshotPath(filePath) {
	return rel(filePath).replace(/[\\/]/g, '__');
}

function extractLinesContaining(source, token, limit = 6) {
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

function validateNavigationContract(navSource, snapshot) {
	const navigationState = resolveNavigationMetadata(homepageContent.navigation);
	snapshot.navigationMetadataAvailable = navigationState.isMetadataAvailable;

	if (!navigationState.isMetadataAvailable) {
		fail(
			'Navigation metadata fell back to defaults. Story 4.3 requires explicit nav metadata for conversion hierarchy checks.',
		);
		return;
	}

	const supportingIds = ['docs', 'workflow-guide', 'changelog', 'github'];
	snapshot.navigationItems = navigationState.items.map((item) => item.id);

	const installNavItem = navigationState.items.find((item) => item.id === 'install');
	if (!installNavItem) {
		fail('Navigation is missing the Install item.');
	}

	for (const id of supportingIds) {
		if (!navigationState.items.some((item) => item.id === id)) {
			fail(`Navigation is missing required supporting path "${id}".`);
		}
	}

	const navTierBindingCount = countMatches(navSource, /data-action-tier=/g);
	const navSupportingBindingCount = countMatches(navSource, /data-supporting-path=/g);
	const navPrimaryCount = installNavItem ? 1 : 0;
	const navSecondaryCount = navigationState.items.filter((item) => item.id !== 'install').length;
	const navSupportingCount = supportingIds.length;
	const hasTierBindingExpression =
		/data-action-tier=\{\s*isInstall\s*\?\s*["']primary["']\s*:\s*["']secondary["']\s*\}/s.test(
			navSource,
		);
	const hasSupportingBindingExpression =
		/data-supporting-path=\{[\s\S]*isSupportingSecondary[\s\S]*["']true["'][\s\S]*:[\s\S]*undefined[\s\S]*\}/s.test(
			navSource,
		);

	snapshot.desktop.nav = {
		primaryCount: navPrimaryCount,
		secondaryCount: navSecondaryCount,
		supportingCount: navSupportingCount,
		tierBindingCount: navTierBindingCount,
		supportingBindingCount: navSupportingBindingCount,
	};

	if (navPrimaryCount !== 1 || !installNavItem) {
		fail(
			`Global navigation must expose exactly one primary action-tier link; found ${navPrimaryCount}.`,
		);
	}

	if (navSecondaryCount < supportingIds.length) {
		fail(
			`Global navigation must expose secondary action-tier links for supporting paths; found ${navSecondaryCount}.`,
		);
	}

	if (navSupportingCount < supportingIds.length) {
		fail(
			`Global navigation must mark supporting paths with data-supporting-path="true"; found ${navSupportingCount}.`,
		);
	}

	if (!hasTierBindingExpression || navTierBindingCount < 1) {
		fail(
			'Global navigation must bind data-action-tier so install resolves primary and all other links resolve secondary.',
		);
	}

	if (!hasSupportingBindingExpression || navSupportingBindingCount < 1) {
		fail(
			'Global navigation must bind data-supporting-path for Docs, Workflow Guide, Changelog, and GitHub links.',
		);
	}

	if (!navSource.includes('global-nav-support-note')) {
		fail(
			'Global navigation is missing support-note semantics for secondary path assistive messaging.',
		);
	}
}

function validateHeroContract(heroSource, snapshot) {
	const heroPrimaryCount = countTierBindings(heroSource, 'primary');
	const heroSecondaryCount = countTierBindings(heroSource, 'secondary');
	const heroSupportingCount = countSupportingBindings(heroSource);

	snapshot.desktop.hero = {
		primaryCount: heroPrimaryCount,
		secondaryCount: heroSecondaryCount,
		supportingCount: heroSupportingCount,
	};

	if (heroPrimaryCount !== 1) {
		fail(
			`Hero actions must include exactly one primary action-tier link; found ${heroPrimaryCount}.`,
		);
	}

	if (heroSecondaryCount < 2) {
		fail(
			`Hero actions must include Docs and Workflow secondary links; found ${heroSecondaryCount}.`,
		);
	}

	if (heroSupportingCount < 2) {
		fail(
			`Hero secondary links must be marked as supporting paths; found ${heroSupportingCount} tagged links.`,
		);
	}

	if (!heroSource.includes('href="/docs"')) {
		fail('Hero actions are missing the Docs supporting path.');
	}

	if (!heroSource.includes('href="/docs/getting-started/"')) {
		fail('Hero actions are missing the Workflow Guide supporting path.');
	}

	if (!heroSource.includes('hero-supporting-path-note')) {
		fail('Hero actions are missing supporting-path assistive text.');
	}
}

function validateFinalCtaContract(finalCtaSource, snapshot) {
	const finalPrimaryCount = countTierBindings(finalCtaSource, 'primary');
	const finalSecondaryCount = countTierBindings(finalCtaSource, 'secondary');
	const finalSupportingCount = countSupportingBindings(finalCtaSource);

	snapshot.desktop.finalCta = {
		primaryCount: finalPrimaryCount,
		secondaryCount: finalSecondaryCount,
		supportingCount: finalSupportingCount,
	};

	if (finalPrimaryCount !== 1) {
		fail(
			`Final CTA must include exactly one primary action-tier link; found ${finalPrimaryCount}.`,
		);
	}

	if (finalSecondaryCount < 1) {
		fail('Final CTA must include a secondary workflow supporting link.');
	}

	if (finalSupportingCount < 1) {
		fail('Final CTA workflow link must be marked as a supporting path.');
	}

	if (!finalCtaSource.includes('final-supporting-path-note')) {
		fail('Final CTA is missing supporting-path assistive text.');
	}
}

function validateDocsHandoffContract(docsHandoffSource, snapshot) {
	const handoffSecondaryCount = countMatches(
		docsHandoffSource,
		/class(?:Name)?=["'][^"']*handoff-link[^"']*["']/g,
	);
	const handoffTierCount = countTierBindings(docsHandoffSource, 'secondary');
	const handoffSupportingCount = countSupportingBindings(docsHandoffSource);

	snapshot.desktop.docsHandoff = {
		handoffLinkCount: handoffSecondaryCount,
		secondaryTierCount: handoffTierCount,
		supportingCount: handoffSupportingCount,
	};

	if (handoffSecondaryCount === 0) {
		fail('Docs handoff section is missing handoff links.');
	}

	if (handoffTierCount < 1 || handoffSupportingCount < 1) {
		fail('Docs handoff links must be marked as secondary supporting conversion paths.');
	}

	if (!docsHandoffSource.includes('docs-handoff-support-note')) {
		fail('Docs handoff section is missing supporting-path assistive text.');
	}
}

function validateCssContract(cssSource, installIntentSource, snapshot) {
	const hasNavSecondaryStyle = cssSource.includes(
		'.nav-link[data-action-tier="secondary"][data-supporting-path="true"]',
	);
	const hasActionOrderRule =
		cssSource.includes('.hero-actions .cta-primary[data-action-tier="primary"]') &&
		cssSource.includes('.hero-actions [data-action-tier="secondary"]') &&
		cssSource.includes('.final-cta-actions .cta-primary[data-action-tier="primary"]') &&
		cssSource.includes('.final-cta-actions [data-action-tier="secondary"]');

	const hasRegionDeEmphasisRule =
		cssSource.includes('body[data-primary-cta-region="hero"] #final-cta .cta-primary') &&
		cssSource.includes('body[data-primary-cta-region="final"] #install-section .cta-primary');

	const mobileStart = cssSource.indexOf('@media (max-width: 767px)');
	const reducedMotionStart = cssSource.indexOf('@media (prefers-reduced-motion: reduce)');
	const mobileBlock =
		mobileStart >= 0
			? cssSource.slice(mobileStart, reducedMotionStart >= 0 ? reducedMotionStart : undefined)
			: '';

	const hasMobileStackingRule =
		mobileBlock.includes('.hero-actions') &&
		mobileBlock.includes('.final-cta-actions') &&
		mobileBlock.includes('flex-direction: column;');
	const hasMobileFullWidthRule =
		mobileBlock.includes('.cta-primary') &&
		mobileBlock.includes('.cta-secondary') &&
		mobileBlock.includes('width: 100%');

	const hasPrimaryRegionObserver =
		installIntentSource.includes("document.body.dataset.primaryCtaRegion = 'hero';") &&
		installIntentSource.includes("? 'final' : 'hero'");

	snapshot.desktop.css = {
		hasNavSecondaryStyle,
		hasActionOrderRule,
		hasRegionDeEmphasisRule,
	};
	snapshot.tablet.css = {
		hasRegionDeEmphasisRule,
		hasActionOrderRule,
	};
	snapshot.mobile.css = {
		hasMobileStackingRule,
		hasMobileFullWidthRule,
		hasPrimaryRegionObserver,
	};

	if (!hasNavSecondaryStyle) {
		fail('Homepage CSS is missing explicit secondary nav styling for supporting paths.');
	}

	if (!hasActionOrderRule) {
		fail('Homepage CSS is missing action-order rules that keep install before secondary links.');
	}

	if (!hasRegionDeEmphasisRule) {
		fail('Homepage CSS is missing primary-region de-emphasis selectors for inactive install CTA.');
	}

	if (!hasMobileStackingRule || !hasMobileFullWidthRule) {
		fail('Homepage CSS mobile breakpoint is missing stacked/full-width CTA hierarchy rules.');
	}

	if (!hasPrimaryRegionObserver) {
		fail(
			'Install intent script is missing primary-region observer logic for hero/final CTA state.',
		);
	}
}

function writeFailureSnapshots(snapshot, sourceMap) {
	const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
	const outputDir = join(projectRoot, '.artifacts', 'conversion-hierarchy', timestamp);
	mkdirSync(outputDir, { recursive: true });

	const summaryPath = join(outputDir, 'hierarchy-summary.json');
	writeFileSync(summaryPath, JSON.stringify(snapshot, null, 2));

	for (const [key, value] of Object.entries(sourceMap)) {
		const snippetLines = [
			`Source: ${rel(value.path)}`,
			'',
			...extractLinesContaining(value.source, 'data-action-tier'),
			...extractLinesContaining(value.source, 'data-supporting-path'),
			...extractLinesContaining(value.source, 'max-width: 767px'),
			...extractLinesContaining(value.source, 'data-primary-cta-region'),
		];

		const snapshotPath = join(outputDir, `${key}.${toSnapshotPath(value.path)}.snapshot.txt`);
		writeFileSync(snapshotPath, snippetLines.join('\n'));
	}

	return outputDir;
}

function main() {
	const navSource = readRequiredFile(componentPaths.nav);
	const heroSource = readRequiredFile(componentPaths.hero);
	const finalCtaSource = readRequiredFile(componentPaths.finalCta);
	const docsHandoffSource = readRequiredFile(componentPaths.docsHandoff);
	const cssSource = readRequiredFile(componentPaths.homepageCss);
	const installIntentSource = readRequiredFile(componentPaths.installIntent);

	if (
		!navSource ||
		!heroSource ||
		!finalCtaSource ||
		!docsHandoffSource ||
		!cssSource ||
		!installIntentSource
	) {
		process.exit(1);
	}

	const snapshot = {
		checkedAt: new Date().toISOString(),
		story: '4.3-supporting-path-hierarchy',
		desktop: {},
		tablet: {},
		mobile: {},
	};

	validateNavigationContract(navSource, snapshot);
	validateHeroContract(heroSource, snapshot);
	validateFinalCtaContract(finalCtaSource, snapshot);
	validateDocsHandoffContract(docsHandoffSource, snapshot);
	validateCssContract(cssSource, installIntentSource, snapshot);

	if (errors.length > 0) {
		const snapshotDir = writeFailureSnapshots(snapshot, {
			nav: { path: componentPaths.nav, source: navSource },
			hero: { path: componentPaths.hero, source: heroSource },
			finalCta: { path: componentPaths.finalCta, source: finalCtaSource },
			docsHandoff: { path: componentPaths.docsHandoff, source: docsHandoffSource },
			css: { path: componentPaths.homepageCss, source: cssSource },
			installIntent: { path: componentPaths.installIntent, source: installIntentSource },
		});

		console.error('\n[conversion-hierarchy] Validation failed.\n');
		for (const [index, error] of errors.entries()) {
			console.error(`${index + 1}. ${error}`);
		}

		console.error('\n[conversion-hierarchy] Release blocked.');
		console.error(
			`[conversion-hierarchy] Breakpoint snapshots written to ${rel(snapshotDir)}. Attach these files to the defect.`,
		);

		process.exit(1);
	}

	const summary = {
		navPrimary: snapshot.desktop.nav?.primaryCount ?? 0,
		navSecondary: snapshot.desktop.nav?.secondaryCount ?? 0,
		heroPrimary: snapshot.desktop.hero?.primaryCount ?? 0,
		heroSecondary: snapshot.desktop.hero?.secondaryCount ?? 0,
		finalPrimary: snapshot.desktop.finalCta?.primaryCount ?? 0,
		finalSecondary: snapshot.desktop.finalCta?.secondaryCount ?? 0,
	};

	console.log(
		`[conversion-hierarchy] Checks passed. nav(primary=${summary.navPrimary}, secondary=${summary.navSecondary}), hero(primary=${summary.heroPrimary}, secondary=${summary.heroSecondary}), final(primary=${summary.finalPrimary}, secondary=${summary.finalSecondary}).`,
	);
}

main();
