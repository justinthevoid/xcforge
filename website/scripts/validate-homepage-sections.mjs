#!/usr/bin/env bun

import {
	formatHomepageNarrativeValidationReport,
	homepageContent,
	validateHomepageNarrativeSections,
} from '../src/data/homepage.ts';

try {
	const validation = validateHomepageNarrativeSections(homepageContent);

	if (!validation.isValid) {
		const report = formatHomepageNarrativeValidationReport(validation);
		console.error(report);
		const normalizedReport = report.toLowerCase();

		if (
			normalizedReport.includes('non-publishable') ||
			normalizedReport.includes('disallowed-until-validated') ||
			normalizedReport.includes('benchmark-gated')
		) {
			console.error(
				'[homepage narrative] Release blocked: resolve claims-policy diagnostics (class, metadata, or benchmark evidence) and update release notes remediation before publishing.',
			);
		} else {
			console.error(
				'[homepage narrative] Release blocked: resolve narrative section contract diagnostics before publishing.',
			);
		}

		process.exit(1);
	}

	console.log('[homepage narrative] Section contract validation passed.');
} catch (error) {
	const message = error instanceof Error ? error.message : String(error);
	console.error(`[homepage narrative] Unexpected validation error: ${message}`);
	process.exit(1);
}
