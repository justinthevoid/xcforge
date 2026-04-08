#!/usr/bin/env bun

import { existsSync, lstatSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, extname, join, relative } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { homepageContent, resolveNavigationMetadata } from '../src/data/homepage.ts';

const projectRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const astroConfigPath = join(projectRoot, 'astro.config.mjs');
const pagesPath = join(projectRoot, 'src', 'pages');
const docsContentPath = join(projectRoot, 'src', 'content', 'docs');

const errors = [];

function relativeToProject(filePath) {
	return relative(projectRoot, filePath) || '.';
}

function fail(message) {
	errors.push(message);
}

function readTextFile(filePath, missingMessage, emptyMessage) {
	if (!existsSync(filePath)) {
		fail(missingMessage);
		return null;
	}

	let source = '';
	try {
		source = readFileSync(filePath, 'utf8');
	} catch (error) {
		fail(`Unable to read ${relativeToProject(filePath)}. ${error.message}`);
		return null;
	}

	if (!source.trim()) {
		fail(emptyMessage);
		return null;
	}

	return source;
}

function walkFiles(rootPath, filter) {
	if (!existsSync(rootPath)) {
		return [];
	}

	const queue = [rootPath];
	const discovered = [];

	while (queue.length > 0) {
		const currentPath = queue.shift();
		if (!currentPath) {
			continue;
		}

		let entryNames = [];
		try {
			entryNames = readdirSync(currentPath);
		} catch (error) {
			fail(
				`Unable to read directory ${relativeToProject(currentPath)} while collecting routes. ${error.message}`,
			);
			continue;
		}

		for (const entryName of entryNames) {
			const entryPath = join(currentPath, entryName);
			let entryStats;
			try {
				entryStats = lstatSync(entryPath);
			} catch (error) {
				fail(
					`Unable to stat ${relativeToProject(entryPath)} while collecting routes. ${error.message}`,
				);
				continue;
			}

			if (entryStats.isSymbolicLink()) {
				continue;
			}

			if (entryStats.isDirectory()) {
				queue.push(entryPath);
				continue;
			}

			if (!entryStats.isFile()) {
				continue;
			}

			if (filter(entryPath)) {
				discovered.push(entryPath);
			}
		}
	}

	return discovered;
}

function normalizeRoutePath(pathname) {
	const trimmed = pathname.trim();
	if (!trimmed.startsWith('/')) {
		return null;
	}

	let normalized = trimmed;
	try {
		normalized = new URL(trimmed, 'https://xcforge.local').pathname;
	} catch {
		return null;
	}

	normalized = normalized.replace(/\/+$/, '');
	return normalized.length === 0 ? '/' : normalized;
}

function isDocsRoute(routePath) {
	return routePath === '/docs' || routePath.startsWith('/docs/');
}

function parseFrontmatterSlug(source) {
	const normalizedSource = source.replace(/\r\n/g, '\n');
	const frontmatterMatch = normalizedSource.match(/^---\s*\n([\s\S]*?)\n---\s*(?:\n|$)/);
	if (!frontmatterMatch) {
		return null;
	}

	const slugMatch = frontmatterMatch[1].match(/^\s*slug:\s*['"]?([^'"\n#]+?)['"]?\s*(?:#.*)?$/m);
	return slugMatch ? slugMatch[1].trim() : null;
}

function deriveDocsSlugFromPath(filePath) {
	const relativePath = relative(docsContentPath, filePath).replace(/\\/g, '/');
	const withoutExtension = relativePath.replace(/\.(md|mdx)$/i, '');

	if (withoutExtension === 'index') {
		return 'docs';
	}

	if (withoutExtension.endsWith('/index')) {
		return `docs/${withoutExtension.slice(0, -'/index'.length)}`;
	}

	return `docs/${withoutExtension}`;
}

function collectDocsRoutes() {
	const docsFiles = walkFiles(docsContentPath, (filePath) => /\.(md|mdx)$/i.test(filePath));
	if (docsFiles.length === 0) {
		fail(
			`No docs content files were found under ${relativeToProject(docsContentPath)}. Starlight route validation cannot run.`,
		);
		return new Set();
	}

	const docsRoutes = new Set();
	for (const docsFile of docsFiles) {
		const source = readTextFile(
			docsFile,
			`Missing docs file: ${relativeToProject(docsFile)}.`,
			`${relativeToProject(docsFile)} is empty.`,
		);
		if (!source) {
			continue;
		}

		const slug = parseFrontmatterSlug(source) ?? deriveDocsSlugFromPath(docsFile);
		const normalizedSlug = slug.replace(/^\/+/, '');
		const docsQualifiedSlug =
			normalizedSlug === 'docs' || normalizedSlug.startsWith('docs/')
				? normalizedSlug
				: `docs/${normalizedSlug}`;
		const normalizedRoute = normalizeRoutePath(`/${docsQualifiedSlug}`);
		if (!normalizedRoute) {
			fail(
				`${relativeToProject(docsFile)} has invalid slug "${slug}". Slugs must resolve to an absolute route path.`,
			);
			continue;
		}

		if (!isDocsRoute(normalizedRoute)) {
			fail(
				`${relativeToProject(docsFile)} resolves to "${normalizedRoute}". Docs slugs must stay within the /docs route family.`,
			);
			continue;
		}

		docsRoutes.add(normalizedRoute);
	}

	if (!docsRoutes.has('/docs')) {
		fail(
			`Docs route inventory is missing /docs. Ensure an overview docs slug exists in ${relativeToProject(docsContentPath)}.`,
		);
	}

	const docsDepthCount = [...docsRoutes].filter((routePath) => routePath !== '/docs').length;
	if (docsDepthCount === 0) {
		fail(
			'Docs route inventory has no depth routes under /docs/. Add at least one technical depth page.',
		);
	}

	return docsRoutes;
}

function escapeRegexLiteral(value) {
	return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function createDynamicRouteMatcher(routePattern) {
	const segments = routePattern.split('/').filter(Boolean);
	if (segments.length === 0) {
		return /^\/$/;
	}

	if (segments.length === 1 && segments[0].startsWith('[[...') && segments[0].endsWith(']]')) {
		return /^\/(?:.*)?$/;
	}

	if (segments.length === 1 && segments[0].startsWith('[[') && segments[0].endsWith(']]')) {
		return /^\/(?:[^/]+)?$/;
	}

	let expression = '^';
	for (const segment of segments) {
		if (segment.startsWith('[[...') && segment.endsWith(']]')) {
			expression += '(?:/.+)?';
			continue;
		}

		if (segment.startsWith('[...') && segment.endsWith(']')) {
			expression += '/.+';
			continue;
		}

		if (segment.startsWith('[[') && segment.endsWith(']]')) {
			expression += '(?:/[^/]+)?';
			continue;
		}

		if (segment.startsWith('[') && segment.endsWith(']')) {
			expression += '/[^/]+';
			continue;
		}

		expression += `/${escapeRegexLiteral(segment)}`;
	}

	expression += '$';
	return new RegExp(expression);
}

function collectMarketingRoutes() {
	const pageFiles = walkFiles(pagesPath, (filePath) => {
		const extension = extname(filePath).toLowerCase();
		return extension === '.astro' || extension === '.md' || extension === '.mdx';
	});

	if (pageFiles.length === 0) {
		fail(`No marketing pages were found under ${relativeToProject(pagesPath)}.`);
		return { staticRoutes: new Set(), dynamicMatchers: [] };
	}

	const staticRoutes = new Set();
	const dynamicMatchers = [];

	for (const pageFile of pageFiles) {
		const relativePath = relative(pagesPath, pageFile).replace(/\\/g, '/');
		const extension = extname(relativePath);
		const withoutExtension = relativePath.slice(0, -extension.length);

		let routePath = '/';
		if (withoutExtension === 'index') {
			routePath = '/';
		} else if (withoutExtension.endsWith('/index')) {
			routePath = `/${withoutExtension.slice(0, -'/index'.length)}`;
		} else {
			routePath = `/${withoutExtension}`;
		}

		const normalizedRoute = normalizeRoutePath(routePath);
		if (!normalizedRoute) {
			fail(`${relativeToProject(pageFile)} resolves to an invalid route path.`);
			continue;
		}

		if (normalizedRoute.includes('[')) {
			dynamicMatchers.push({
				routePattern: normalizedRoute,
				matcher: createDynamicRouteMatcher(normalizedRoute),
				source: relativeToProject(pageFile),
			});
			continue;
		}

		staticRoutes.add(normalizedRoute);
	}

	const hasHomepageRoute =
		staticRoutes.has('/') || dynamicMatchers.some((routeMatcher) => routeMatcher.matcher.test('/'));
	if (!hasHomepageRoute) {
		fail('Marketing routes are missing /. The homepage entry route must remain available.');
	}

	return { staticRoutes, dynamicMatchers };
}

function hasMarketingRoute(routePath, marketingRoutes) {
	if (marketingRoutes.staticRoutes.has(routePath)) {
		return true;
	}

	return marketingRoutes.dynamicMatchers.some((routeMatcher) =>
		routeMatcher.matcher.test(routePath),
	);
}

function validateRouteOwnership(marketingRoutes, docsRoutes) {
	for (const routePath of marketingRoutes.staticRoutes) {
		if (isDocsRoute(routePath)) {
			fail(
				`Route ownership violation: marketing page route "${routePath}" overlaps with the docs route family (/docs).`,
			);
		}
	}

	for (const routeMatcher of marketingRoutes.dynamicMatchers) {
		if (isDocsRoute(routeMatcher.routePattern)) {
			fail(
				`Route ownership violation: marketing page route pattern "${routeMatcher.routePattern}" (${routeMatcher.source}) overlaps with the docs route family (/docs).`,
			);
			continue;
		}

		const overlappingDocsRoute = [...docsRoutes].find((routePath) =>
			routeMatcher.matcher.test(routePath),
		);
		if (overlappingDocsRoute) {
			fail(
				`Route ownership violation: marketing page route pattern "${routeMatcher.routePattern}" (${routeMatcher.source}) matches docs route "${overlappingDocsRoute}".`,
			);
		}
	}

	for (const routePath of docsRoutes) {
		if (!isDocsRoute(routePath)) {
			fail(`Route ownership violation: docs route "${routePath}" is outside /docs.`);
		}
	}
}

function hasKnownIntegration(integrations, token) {
	const normalizedToken = token.toLowerCase();
	return integrations.some((integration) => {
		if (!integration || typeof integration !== 'object') {
			return false;
		}

		if (typeof integration.name === 'string') {
			return integration.name.toLowerCase().includes(normalizedToken);
		}

		return false;
	});
}

async function validateAstroComposition() {
	const astroConfigSource = readTextFile(
		astroConfigPath,
		`Missing ${relativeToProject(astroConfigPath)}. Route boundary checks require Astro integration contracts.`,
		`${relativeToProject(astroConfigPath)} is empty.`,
	);

	if (!astroConfigSource) {
		return;
	}

	if (!astroConfigSource.includes('@astrojs/starlight')) {
		fail(
			`${relativeToProject(astroConfigPath)} must reference @astrojs/starlight to preserve docs ownership under /docs.`,
		);
	}

	if (!astroConfigSource.includes('@astrojs/svelte')) {
		fail(
			`${relativeToProject(astroConfigPath)} must reference @astrojs/svelte to preserve Astro + Svelte marketing composition.`,
		);
	}

	let astroConfig = null;
	try {
		const configModule = await import(
			`${pathToFileURL(astroConfigPath).href}?routeBoundaryValidation=${Date.now()}`
		);
		astroConfig = configModule?.default ?? null;
	} catch (error) {
		fail(
			`Unable to evaluate ${relativeToProject(astroConfigPath)} while validating integrations. ${error.message}`,
		);
		return;
	}

	if (!astroConfig || typeof astroConfig !== 'object') {
		fail(
			`${relativeToProject(astroConfigPath)} must export a valid Astro config object with integrations.`,
		);
		return;
	}

	const integrations = Array.isArray(astroConfig.integrations) ? astroConfig.integrations : [];
	if (integrations.length === 0) {
		fail(
			`${relativeToProject(astroConfigPath)} must define integrations for Starlight and Svelte.`,
		);
		return;
	}

	if (!hasKnownIntegration(integrations, 'starlight')) {
		fail(
			`${relativeToProject(astroConfigPath)} integrations are missing @astrojs/starlight. Docs route ownership checks require Starlight.`,
		);
	}

	if (!hasKnownIntegration(integrations, 'svelte')) {
		fail(
			`${relativeToProject(astroConfigPath)} integrations are missing @astrojs/svelte. Marketing composition checks require Svelte integration.`,
		);
	}
}

function classifyHref(hrefValue) {
	if (typeof hrefValue !== 'string') {
		return { kind: 'invalid', detail: String(hrefValue) };
	}

	const trimmed = hrefValue.trim();
	if (trimmed.length === 0) {
		return { kind: 'invalid', detail: '(empty)' };
	}

	if (trimmed.startsWith('#')) {
		return { kind: 'anchor', href: trimmed };
	}

	if (/^[A-Za-z][A-Za-z\d+.-]*:/.test(trimmed) || trimmed.startsWith('//')) {
		return { kind: 'external', href: trimmed };
	}

	if (!trimmed.startsWith('/')) {
		return { kind: 'relative', href: trimmed };
	}

	const normalizedRoute = normalizeRoutePath(trimmed);
	if (!normalizedRoute) {
		return { kind: 'invalid', detail: trimmed };
	}

	return { kind: 'route', href: trimmed, routePath: normalizedRoute };
}

function collectHrefEntries(node, sourcePath = 'homepageContent') {
	const entries = [];

	if (!node || typeof node !== 'object') {
		return entries;
	}

	if (Array.isArray(node)) {
		node.forEach((value, index) => {
			entries.push(...collectHrefEntries(value, `${sourcePath}[${index}]`));
		});
		return entries;
	}

	for (const [key, value] of Object.entries(node)) {
		const valuePath = `${sourcePath}.${key}`;
		if (key === 'href') {
			entries.push({ sourcePath: valuePath, href: value });
			continue;
		}

		if (value && typeof value === 'object') {
			entries.push(...collectHrefEntries(value, valuePath));
		}
	}

	return entries;
}

function validateHomepageStaticHrefLiterals(marketingRoutes, docsRoutes) {
	const homepageFiles = [
		join(projectRoot, 'src', 'components', 'website', 'HeroProof.astro'),
		join(projectRoot, 'src', 'components', 'website', 'GlobalNav.astro'),
		join(projectRoot, 'src', 'components', 'website', 'DocsHandoffSection.astro'),
		join(projectRoot, 'src', 'components', 'website', 'FinalCTA.astro'),
		join(projectRoot, 'src', 'components', 'website', 'DifferentiationProofSection.astro'),
		join(projectRoot, 'src', 'pages', 'index.astro'),
	];

	for (const filePath of homepageFiles) {
		if (!existsSync(filePath)) {
			continue;
		}

		const source = readTextFile(
			filePath,
			`Missing homepage file ${relativeToProject(filePath)} while scanning static href literals.`,
			`${relativeToProject(filePath)} is empty while scanning static href literals.`,
		);
		if (!source) {
			continue;
		}

		const hrefLiteralPattern = /href\s*=\s*["']([^"']+)["']/g;
		for (const match of source.matchAll(hrefLiteralPattern)) {
			const hrefValue = match[1];
			const classification = classifyHref(hrefValue);

			if (classification.kind === 'external' || classification.kind === 'anchor') {
				continue;
			}

			const sourceLabel = `${relativeToProject(filePath)} static href "${hrefValue}"`;
			if (classification.kind !== 'route') {
				fail(`${sourceLabel} is invalid. Use an absolute internal route or a valid external URL.`);
				continue;
			}

			if (isDocsRoute(classification.routePath)) {
				if (!docsRoutes.has(classification.routePath)) {
					fail(`${sourceLabel} points to missing docs route "${classification.routePath}".`);
				}
				continue;
			}

			if (!hasMarketingRoute(classification.routePath, marketingRoutes)) {
				fail(`${sourceLabel} points to missing marketing route "${classification.routePath}".`);
			}
		}
	}
}

function assertDocsRouteExists(sourceLabel, hrefValue, docsRoutes, requireDepth = false) {
	const hrefClassification = classifyHref(hrefValue);
	if (hrefClassification.kind !== 'route') {
		fail(`${sourceLabel} must be an internal absolute route. Received "${String(hrefValue)}".`);
		return;
	}

	if (!isDocsRoute(hrefClassification.routePath)) {
		fail(
			`${sourceLabel} must target docs-owned routes under /docs. Received "${hrefClassification.routePath}".`,
		);
		return;
	}

	if (!docsRoutes.has(hrefClassification.routePath)) {
		fail(
			`${sourceLabel} points to missing docs route "${hrefClassification.routePath}". Add the destination docs slug or correct the link.`,
		);
		return;
	}

	if (requireDepth && hrefClassification.routePath === '/docs') {
		fail(`${sourceLabel} must target a docs depth route under /docs/.`);
	}
}

function validateHomepageRoutes(marketingRoutes, docsRoutes) {
	const hrefEntries = collectHrefEntries(homepageContent);
	for (const entry of hrefEntries) {
		const classification = classifyHref(entry.href);

		if (classification.kind === 'external' || classification.kind === 'anchor') {
			continue;
		}

		if (classification.kind === 'relative') {
			fail(
				`${entry.sourcePath} uses relative href "${classification.href}". Use absolute internal routes beginning with '/'.`,
			);
			continue;
		}

		if (classification.kind === 'invalid') {
			fail(`${entry.sourcePath} has invalid href "${classification.detail}".`);
			continue;
		}

		if (isDocsRoute(classification.routePath)) {
			if (!docsRoutes.has(classification.routePath)) {
				fail(
					`${entry.sourcePath} points to missing docs route "${classification.routePath}". Route boundary checks block release for dead-end depth links.`,
				);
			}
			continue;
		}

		if (!hasMarketingRoute(classification.routePath, marketingRoutes)) {
			fail(
				`${entry.sourcePath} points to missing marketing route "${classification.routePath}". Add the page route or correct the link.`,
			);
		}
	}

	const navigationState = resolveNavigationMetadata(homepageContent.navigation);
	if (!navigationState.isMetadataAvailable) {
		fail(
			'Navigation metadata fell back to safe defaults. Route boundary checks require explicit navigation metadata.',
		);
		return;
	}

	const docsNavItem = navigationState.items.find((item) => item.id === 'docs');
	const workflowNavItem = navigationState.items.find((item) => item.id === 'workflow-guide');
	if (!docsNavItem || !workflowNavItem) {
		fail(
			'Navigation must include Docs and Workflow Guide items for one-click technical depth transitions.',
		);
	} else {
		assertDocsRouteExists('navigation.docs', docsNavItem.href, docsRoutes, false);
		assertDocsRouteExists('navigation.workflow-guide', workflowNavItem.href, docsRoutes, true);
	}

	assertDocsRouteExists(
		'finalCta.workflowHref',
		homepageContent.finalCta.workflowHref,
		docsRoutes,
		true,
	);
	assertDocsRouteExists(
		'hero.provenanceUnavailableDocsHref',
		homepageContent.hero.provenanceUnavailableDocsHref,
		docsRoutes,
		false,
	);

	const differentiationSection = homepageContent.narrativeSections.find(
		(section) => section.id === 'differentiation',
	);
	if (!differentiationSection || !('provenanceUnavailableDocsHref' in differentiationSection)) {
		fail(
			'Narrative section differentiation is missing provenance fallback metadata required for warning-state route handoff.',
		);
	} else {
		assertDocsRouteExists(
			'differentiation.provenanceUnavailableDocsHref',
			differentiationSection.provenanceUnavailableDocsHref,
			docsRoutes,
			false,
		);
	}

	const docsHandoffSection = homepageContent.narrativeSections.find(
		(section) => section.id === 'docs-handoff',
	);
	if (!docsHandoffSection || !Array.isArray(docsHandoffSection.handoffLinks)) {
		fail(
			'Narrative section docs-handoff is missing. One-click depth transitions must remain present on the homepage.',
		);
		return;
	}

	const docsHandoffInternalRoutes = docsHandoffSection.handoffLinks
		.map((link) => classifyHref(link.href))
		.filter((classification) => classification.kind === 'route')
		.map((classification) => classification.routePath);

	if (!docsHandoffInternalRoutes.includes('/docs')) {
		fail('docs-handoff links must include /docs as a one-click technical entry point.');
	}

	if (
		!docsHandoffInternalRoutes.some((routePath) => isDocsRoute(routePath) && routePath !== '/docs')
	) {
		fail('docs-handoff links must include at least one docs depth route under /docs/.');
	}

	for (const [index, link] of docsHandoffSection.handoffLinks.entries()) {
		const linkClassification = classifyHref(link.href);
		if (linkClassification.kind !== 'route' || !isDocsRoute(linkClassification.routePath)) {
			continue;
		}

		const sourceLabel = `docs-handoff.handoffLinks[${index}]`;
		if (
			typeof link.unavailableMessage !== 'string' ||
			link.unavailableMessage.trim().length === 0
		) {
			fail(
				`${sourceLabel}.unavailableMessage is required for internal docs handoff links so destination-unavailable fallbacks can be explicit.`,
			);
		}

		if (link.destinationId !== 'docs' && link.destinationId !== 'workflow-guide') {
			fail(
				`${sourceLabel}.destinationId must be "docs" or "workflow-guide" for handoff orientation messaging.`,
			);
		}

		if (typeof link.fallbackHref !== 'string' || link.fallbackHref.trim().length === 0) {
			fail(
				`${sourceLabel}.fallbackHref is required for internal docs handoff links and must target a valid docs fallback destination.`,
			);
			continue;
		}

		assertDocsRouteExists(`${sourceLabel}.fallbackHref`, link.fallbackHref, docsRoutes, false);
	}
}

async function main() {
	const docsRoutes = collectDocsRoutes();
	const marketingRoutes = collectMarketingRoutes();

	validateRouteOwnership(marketingRoutes, docsRoutes);
	await validateAstroComposition();
	validateHomepageRoutes(marketingRoutes, docsRoutes);
	validateHomepageStaticHrefLiterals(marketingRoutes, docsRoutes);

	if (errors.length > 0) {
		console.error('\n[route-boundaries] Route boundary validation failed.\n');
		for (const [index, message] of errors.entries()) {
			console.error(`${index + 1}. ${message}`);
		}

		console.error('\n[route-boundaries] Remediation steps:');
		console.error(
			'- Keep marketing routes in src/pages and docs routes under /docs via src/content/docs slugs.',
		);
		console.error(
			'- Ensure astro.config.mjs includes both @astrojs/starlight and @astrojs/svelte integrations.',
		);
		console.error(
			'- Correct broken internal href values in homepage content or add missing route destinations.',
		);
		console.error('- Re-run checks: bun run validate:routes');

		process.exit(1);
	}

	const internalHrefCount = collectHrefEntries(homepageContent)
		.map((entry) => classifyHref(entry.href))
		.filter((classification) => classification.kind === 'route').length;
	const marketingRouteCount =
		marketingRoutes.staticRoutes.size + marketingRoutes.dynamicMatchers.length;

	console.log(
		`[route-boundaries] Checks passed. Marketing routes: ${marketingRouteCount}. Docs routes: ${docsRoutes.size}. Internal hrefs validated: ${internalHrefCount}.`,
	);
}

await main();
