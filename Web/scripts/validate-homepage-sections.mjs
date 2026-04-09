#!/usr/bin/env bun

import { homepageContent, resolveNavigationMetadata } from '../src/data/homepage.ts';

const errors = [];

function fail(message) {
	errors.push(message);
}

try {
	// Validate navigation metadata resolves cleanly.
	const navigationState = resolveNavigationMetadata(homepageContent.navigation);

	if (!navigationState.isMetadataAvailable) {
		fail(
			'Navigation metadata fell back to defaults. Ensure homepageContent.navigation matches the required nav order.',
		);
	}

	// Validate required nav items are present.
	const requiredNavIds = ['product', 'docs', 'workflow-guide', 'changelog', 'github', 'install'];
	for (const id of requiredNavIds) {
		if (!navigationState.items.some((item) => item.id === id)) {
			fail(`Navigation is missing required item "${id}".`);
		}
	}

	// Validate the install nav item has a valid href.
	const installItem = navigationState.items.find((item) => item.id === 'install');
	if (!installItem?.href) {
		fail('Navigation install item is missing a required href.');
	}

	// Validate hero content shape.
	const { hero } = homepageContent;
	if (!hero.headline || typeof hero.headline !== 'string' || hero.headline.trim() === '') {
		fail('homepageContent.hero.headline is missing or empty.');
	}

	if (!hero.subtitle || typeof hero.subtitle !== 'string' || hero.subtitle.trim() === '') {
		fail('homepageContent.hero.subtitle is missing or empty.');
	}

	if (!hero.tapCommand || typeof hero.tapCommand !== 'string' || hero.tapCommand.trim() === '') {
		fail('homepageContent.hero.tapCommand is missing or empty.');
	}

	if (
		!hero.installCommand ||
		typeof hero.installCommand !== 'string' ||
		hero.installCommand.trim() === ''
	) {
		fail('homepageContent.hero.installCommand is missing or empty.');
	}

	if (
		!hero.fullInstallCommand ||
		typeof hero.fullInstallCommand !== 'string' ||
		hero.fullInstallCommand.trim() === ''
	) {
		fail('homepageContent.hero.fullInstallCommand is missing or empty.');
	}

	if (!hero.installHref || typeof hero.installHref !== 'string' || hero.installHref.trim() === '') {
		fail('homepageContent.hero.installHref is missing or empty.');
	}

	// Validate terminal demo content shape.
	const { terminalDemo } = homepageContent;
	if (
		!terminalDemo.heading ||
		typeof terminalDemo.heading !== 'string' ||
		terminalDemo.heading.trim() === ''
	) {
		fail('homepageContent.terminalDemo.heading is missing or empty.');
	}

	if (
		!terminalDemo.subtitle ||
		typeof terminalDemo.subtitle !== 'string' ||
		terminalDemo.subtitle.trim() === ''
	) {
		fail('homepageContent.terminalDemo.subtitle is missing or empty.');
	}

	if (!Array.isArray(terminalDemo.steps) || terminalDemo.steps.length === 0) {
		fail('homepageContent.terminalDemo.steps must be a non-empty array.');
	} else {
		const hasCommandStep = terminalDemo.steps.some((step) => step.prompt && step.command);
		const hasOutputStep = terminalDemo.steps.some((step) => step.output);

		if (!hasCommandStep) {
			fail('homepageContent.terminalDemo.steps must include at least one prompt/command step.');
		}

		if (!hasOutputStep) {
			fail('homepageContent.terminalDemo.steps must include at least one output step.');
		}
	}

	// Validate features content shape.
	const { features } = homepageContent;
	if (!Array.isArray(features) || features.length === 0) {
		fail('homepageContent.features must be a non-empty array.');
	} else {
		for (const [index, feature] of features.entries()) {
			if (!feature.id || typeof feature.id !== 'string') {
				fail(`homepageContent.features[${index}].id is missing or invalid.`);
			}

			if (!feature.marker || typeof feature.marker !== 'string') {
				fail(`homepageContent.features[${index}].marker is missing or invalid.`);
			}

			if (!feature.title || typeof feature.title !== 'string' || feature.title.trim() === '') {
				fail(`homepageContent.features[${index}].title is missing or empty.`);
			}

			if (
				!feature.description ||
				typeof feature.description !== 'string' ||
				feature.description.trim() === ''
			) {
				fail(`homepageContent.features[${index}].description is missing or empty.`);
			}
		}
	}

	// Validate finalCta content shape.
	const { finalCta } = homepageContent;
	const requiredFinalCtaStrings = [
		'heading',
		'summary',
		'installLabel',
		'installCommand',
		'installHref',
		'docsLabel',
		'docsHref',
		'handoffTitle',
		'handoffReadyMessage',
		'handoffFailureMessage',
		'handoffRestoredMessage',
		'handoffCopyButtonLabel',
		'handoffGuideLabel',
	];

	for (const field of requiredFinalCtaStrings) {
		if (
			!finalCta[field] ||
			typeof finalCta[field] !== 'string' ||
			finalCta[field].trim() === ''
		) {
			fail(`homepageContent.finalCta.${field} is missing or empty.`);
		}
	}

	if (errors.length > 0) {
		console.error('\n[homepage sections] Validation failed.\n');
		for (const [index, error] of errors.entries()) {
			console.error(`${index + 1}. ${error}`);
		}
		console.error('\n[homepage sections] Release blocked: resolve content contract diagnostics.');
		process.exit(1);
	}

	console.log(
		`[homepage sections] Content contract validation passed (nav=${navigationState.items.length}, features=${features.length}, terminalSteps=${terminalDemo.steps.length}).`,
	);
} catch (error) {
	const message = error instanceof Error ? error.message : String(error);
	console.error(`[homepage sections] Unexpected validation error: ${message}`);
	process.exit(1);
}
