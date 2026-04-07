#!/usr/bin/env bun

import {
  formatHomepageNarrativeValidationReport,
  homepageContent,
  validateHomepageNarrativeSections,
} from '../src/data/homepage.ts';

try {
  const validation = validateHomepageNarrativeSections(homepageContent);

  if (!validation.isValid) {
    console.error(formatHomepageNarrativeValidationReport(validation));
    process.exit(1);
  }

  console.log('[homepage narrative] Section contract validation passed.');
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`[homepage narrative] Unexpected validation error: ${message}`);
  process.exit(1);
}
