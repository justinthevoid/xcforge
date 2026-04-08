#!/usr/bin/env bun

import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = join(projectRoot, '..');
const remediationMarkdownPath = join(
  repoRoot,
  '_bmad-output',
  'implementation-artifacts',
  'story-5-3-remediation-tasks.md',
);
const remediationJsonPath = join(
  repoRoot,
  '_bmad-output',
  'implementation-artifacts',
  'story-5-3-remediation-tasks.json',
);

const paths = {
  hero: join(projectRoot, 'src', 'components', 'web', 'HeroProof.astro'),
  proofToggle: join(projectRoot, 'src', 'components', 'web', 'ProofToggle.svelte'),
  docsHandoff: join(projectRoot, 'src', 'components', 'web', 'DocsHandoffSection.astro'),
  finalCta: join(projectRoot, 'src', 'components', 'web', 'FinalCTA.astro'),
  tokens: join(projectRoot, 'src', 'styles', 'tokens.css'),
  primitives: join(projectRoot, 'src', 'styles', 'primitives.css'),
  homepage: join(projectRoot, 'src', 'styles', 'homepage.css'),
};

const failures = [];

function relFromRepo(filePath) {
  return relative(repoRoot, filePath) || '.';
}

function relFromWeb(filePath) {
  return relative(projectRoot, filePath) || '.';
}

function fail(scope, filePath, message, remediation) {
  failures.push({
    scope,
    filePath,
    message,
    remediation,
  });
}

function readRequired(filePath, scope) {
  if (!existsSync(filePath)) {
    fail(
      scope,
      filePath,
      'Required file is missing.',
      'Restore this file before running release checks.',
    );
    return null;
  }

  try {
    const source = readFileSync(filePath, 'utf8');
    if (!source.trim()) {
      fail(scope, filePath, 'Required file is empty.', 'Restore expected implementation content.');
      return null;
    }

    return source;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    fail(
      scope,
      filePath,
      `Unable to read file. ${message}`,
      'Resolve filesystem issues and rerun.',
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

function parseHexColor(hexColor) {
  const hex = hexColor.trim().replace(/^#/, '');
  if (![3, 6, 8].includes(hex.length)) {
    return null;
  }

  if (hex.length === 3) {
    const red = Number.parseInt(`${hex[0]}${hex[0]}`, 16);
    const green = Number.parseInt(`${hex[1]}${hex[1]}`, 16);
    const blue = Number.parseInt(`${hex[2]}${hex[2]}`, 16);

    if ([red, green, blue].some((value) => Number.isNaN(value))) {
      return null;
    }

    return { red, green, blue, alpha: 1 };
  }

  const normalized = hex.slice(0, 6);

  const red = Number.parseInt(normalized.slice(0, 2), 16);
  const green = Number.parseInt(normalized.slice(2, 4), 16);
  const blue = Number.parseInt(normalized.slice(4, 6), 16);
  const alpha = hex.length === 8 ? Number.parseInt(hex.slice(6, 8), 16) / 255 : 1;

  if ([red, green, blue, alpha].some((value) => Number.isNaN(value))) {
    return null;
  }

  return { red, green, blue, alpha };
}

function toLinearSrgb(channel) {
  const normalized = channel / 255;
  return normalized <= 0.03928 ? normalized / 12.92 : ((normalized + 0.055) / 1.055) ** 2.4;
}

function relativeLuminance(color) {
  const red = toLinearSrgb(color.red);
  const green = toLinearSrgb(color.green);
  const blue = toLinearSrgb(color.blue);
  return red * 0.2126 + green * 0.7152 + blue * 0.0722;
}

function contrastRatio(foreground, background) {
  const foregroundLuminance = relativeLuminance(foreground);
  const backgroundLuminance = relativeLuminance(background);
  const lighter = Math.max(foregroundLuminance, backgroundLuminance);
  const darker = Math.min(foregroundLuminance, backgroundLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

function parseTokenHexMap(tokensSource, scope, filePath) {
  const tokenMap = new Map();
  const tokenRegex =
    /(--xcf-[a-z0-9-]+)\s*:\s*(#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8}))\s*;/g;

  for (const match of tokensSource.matchAll(tokenRegex)) {
    tokenMap.set(match[1], match[2]);
  }

  if (tokenMap.size === 0) {
    fail(
      scope,
      filePath,
      'Unable to parse canonical color tokens.',
      'Ensure tokens.css declares hex-based --xcf-color-* values.',
    );
  }

  return tokenMap;
}

function extractReducedMotionBlocks(source) {
  const blocks = [];
  const mediaRegex = /@media\s+[^{]+\{/g;

  for (const match of source.matchAll(mediaRegex)) {
    const header = match[0];
    if (!/prefers-reduced-motion\s*:\s*reduce/i.test(header)) {
      continue;
    }

    const start = match.index ?? -1;
    if (start < 0) {
      continue;
    }

    const firstBrace = start + header.length - 1;
    if (firstBrace < 0 || firstBrace >= source.length || source[firstBrace] !== '{') {
      continue;
    }

    let depth = 0;
    let end = -1;
    for (let index = firstBrace; index < source.length; index += 1) {
      if (source[index] === '{') {
        depth += 1;
      } else if (source[index] === '}') {
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

    blocks.push(source.slice(firstBrace + 1, end));
  }

  return blocks;
}

function normalizeSelector(selector) {
  return selector.replace(/\s+/g, ' ').trim();
}

function extractReducedMotionRules(blocks) {
  const rules = [];
  const ruleRegex = /([^{}]+)\{([^{}]+)\}/g;

  for (const block of blocks) {
    for (const match of block.matchAll(ruleRegex)) {
      const selectorGroup = match[1] ?? '';
      const declarations = match[2] ?? '';
      const selectors = selectorGroup
        .split(',')
        .map((selector) => normalizeSelector(selector))
        .filter(Boolean);

      if (selectors.length === 0) {
        continue;
      }

      rules.push({
        selectors,
        hasTransitionNone: /transition\s*:\s*none\s*;/i.test(declarations),
        hasTransformNone: /transform\s*:\s*none\s*;/i.test(declarations),
      });
    }
  }

  return rules;
}

function selectorHasRuleProperty(rules, selector, property) {
  const normalizedSelector = normalizeSelector(selector);
  return rules.some((rule) => {
    if (!rule.selectors.includes(normalizedSelector)) {
      return false;
    }

    if (property === 'transition-none') {
      return rule.hasTransitionNone;
    }

    if (property === 'transform-none') {
      return rule.hasTransformNone;
    }

    return false;
  });
}

function validateAssistiveTechContracts({ heroSource, proofSource, docsSource, finalSource }) {
  const storyScope = 'assistive-tech-contracts';

  expectMatches(
    heroSource,
    /<aside[^>]*class="[^"]*\bproof-panel\b[^"]*"(?=[^>]*aria-live="polite")[^>]*>/m,
    storyScope,
    paths.hero,
    'Hero proof panel is missing polite live-region behavior.',
    'Keep proof panel announcements available to assistive technologies.',
  );

  expectMatches(
    proofSource,
    /aria-pressed=\{snapshot\.id === activeSnapshotId\}/m,
    storyScope,
    paths.proofToggle,
    'Proof toggle buttons are missing pressed-state semantics.',
    'Preserve aria-pressed bindings for current proof-state selection.',
  );

  expectIncludes(
    proofSource,
    `\${snapshot.label} (selected)`,
    storyScope,
    paths.proofToggle,
    'Proof selected-state text marker is missing.',
    'Keep explicit selected-state copy so state is not color-only.',
  );

  expectMatches(
    proofSource,
    /<p[^>]*class="[^"]*\bproof-toggle-status\b[^"]*"(?=[^>]*role="status")(?=[^>]*aria-live="polite")[^>]*>/m,
    storyScope,
    paths.proofToggle,
    'Proof state announcement live region is missing.',
    'Restore polite status announcement for proof state changes.',
  );

  expectIncludes(
    docsSource,
    'data-docs-handoff-status',
    storyScope,
    paths.docsHandoff,
    'Docs handoff status region is missing.',
    'Restore docs handoff status output for assistive-tech feedback.',
  );

  expectMatches(
    docsSource,
    /<[^>]*data-docs-handoff-status(?=[^>]*role="status")(?=[^>]*aria-atomic="true")[^>]*>/m,
    storyScope,
    paths.docsHandoff,
    'Docs handoff status semantics are incomplete.',
    'Keep role="status" with aria-atomic="true" for coherent updates.',
  );

  expectMatches(
    finalSource,
    /<pre[^>]*data-install-handoff-command(?=[^>]*tabindex="0")(?=[^>]*aria-label="Install command")[^>]*>/m,
    storyScope,
    paths.finalCta,
    'Final CTA install command region is missing required assistive-tech attributes.',
    'Keep the install command as a labeled, focusable preformatted region.',
  );

  expectMatches(
    finalSource,
    /<[^>]*data-install-handoff-message(?=[^>]*role="status")(?=[^>]*aria-atomic="true")[^>]*>/m,
    storyScope,
    paths.finalCta,
    'Final CTA status message semantics are incomplete.',
    'Keep role="status" and aria-atomic="true" on handoff status messaging.',
  );
}

function validateContrast(tokensSource) {
  const scope = 'contrast-wcag-aa';
  const tokenMap = parseTokenHexMap(tokensSource, scope, paths.tokens);

  const requiredPairs = [
    {
      name: 'Body text on page background',
      foregroundToken: '--xcf-color-text',
      backgroundToken: '--xcf-color-bg',
      minimumRatio: 4.5,
    },
    {
      name: 'Muted text on page background',
      foregroundToken: '--xcf-color-text-muted',
      backgroundToken: '--xcf-color-bg',
      minimumRatio: 4.5,
    },
    {
      name: 'Body text on panel background',
      foregroundToken: '--xcf-color-text',
      backgroundToken: '--xcf-color-panel',
      minimumRatio: 4.5,
    },
    {
      name: 'Muted text on panel background',
      foregroundToken: '--xcf-color-text-muted',
      backgroundToken: '--xcf-color-panel',
      minimumRatio: 4.5,
    },
    {
      name: 'Link text on page background',
      foregroundToken: '--xcf-color-link',
      backgroundToken: '--xcf-color-bg',
      minimumRatio: 4.5,
    },
    {
      name: 'Primary CTA text on conversion background',
      foregroundToken: '--xcf-color-inverse-text',
      backgroundToken: '--xcf-color-conversion',
      minimumRatio: 4.5,
    },
    {
      name: 'Focus ring on page background',
      foregroundToken: '--xcf-color-focus',
      backgroundToken: '--xcf-color-bg',
      minimumRatio: 3,
    },
  ];

  for (const pair of requiredPairs) {
    const foregroundHex = tokenMap.get(pair.foregroundToken);
    const backgroundHex = tokenMap.get(pair.backgroundToken);

    if (!foregroundHex || !backgroundHex) {
      fail(
        scope,
        paths.tokens,
        `${pair.name}: required token is missing (${pair.foregroundToken} or ${pair.backgroundToken}).`,
        'Restore required color tokens before release checks.',
      );
      continue;
    }

    const foregroundColor = parseHexColor(foregroundHex);
    const backgroundColor = parseHexColor(backgroundHex);

    if (!foregroundColor || !backgroundColor) {
      fail(
        scope,
        paths.tokens,
        `${pair.name}: unable to parse one or both token values (${foregroundHex}, ${backgroundHex}).`,
        'Use valid 3/6/8-digit hex color tokens.',
      );
      continue;
    }

    if (foregroundColor.alpha < 1 || backgroundColor.alpha < 1) {
      fail(
        scope,
        paths.tokens,
        `${pair.name}: translucent token values are unsupported for deterministic contrast checks (${foregroundHex}, ${backgroundHex}).`,
        'Use opaque hex color tokens for Story 5.3 required contrast pairs.',
      );
      continue;
    }

    const ratio = contrastRatio(foregroundColor, backgroundColor);
    if (ratio < pair.minimumRatio) {
      fail(
        scope,
        paths.tokens,
        `${pair.name}: contrast ratio ${ratio.toFixed(2)} is below required ${pair.minimumRatio.toFixed(1)}.`,
        `Adjust ${pair.foregroundToken} or ${pair.backgroundToken} to meet WCAG 2.1 AA requirements.`,
      );
    }
  }
}

function validateMotionSafeContracts(primitivesSource, homepageSource) {
  const scope = 'motion-safe-contracts';

  const primitiveReducedMotionBlocks = extractReducedMotionBlocks(primitivesSource);
  if (primitiveReducedMotionBlocks.length === 0) {
    fail(
      scope,
      paths.primitives,
      'primitives.css is missing a prefers-reduced-motion block.',
      'Add reduced-motion overrides for primitive action transitions.',
    );
  } else {
    const primitiveReducedMotionSource = primitiveReducedMotionBlocks.join('\n');
    const primitiveRules = extractReducedMotionRules(primitiveReducedMotionBlocks);
    const primitiveTransitionSelectors = ['.action-link', '.cta-primary', '.cta-secondary'];
    const primitiveTransformSelectors = ['.action-link-primary:hover', '.cta-primary:hover'];

    for (const selector of primitiveTransitionSelectors) {
      if (!primitiveReducedMotionSource.includes(selector)) {
        fail(
          scope,
          paths.primitives,
          `Reduced-motion block is missing selector ${selector}.`,
          'Add selector coverage so interaction motion is reduced consistently.',
        );
      }

      if (!selectorHasRuleProperty(primitiveRules, selector, 'transition-none')) {
        fail(
          scope,
          paths.primitives,
          `Reduced-motion selector ${selector} is missing transition neutralization.`,
          'Add transition: none; on the same reduced-motion selector rule.',
        );
      }
    }

    for (const selector of primitiveTransformSelectors) {
      if (!primitiveReducedMotionSource.includes(selector)) {
        fail(
          scope,
          paths.primitives,
          `Reduced-motion block is missing selector ${selector}.`,
          'Add selector coverage so interaction motion is reduced consistently.',
        );
      }

      if (!selectorHasRuleProperty(primitiveRules, selector, 'transform-none')) {
        fail(
          scope,
          paths.primitives,
          `Reduced-motion selector ${selector} is missing transform neutralization.`,
          'Add transform: none; on the same reduced-motion selector rule.',
        );
      }
    }
  }

  const homepageReducedMotionBlocks = extractReducedMotionBlocks(homepageSource);
  if (homepageReducedMotionBlocks.length === 0) {
    fail(
      scope,
      paths.homepage,
      'homepage.css is missing a prefers-reduced-motion block.',
      'Add reduced-motion overrides for proof and CTA modules.',
    );
    return;
  }

  const homepageReducedMotionSource = homepageReducedMotionBlocks.join('\n');
  const homepageRules = extractReducedMotionRules(homepageReducedMotionBlocks);

  const homepageTransitionSelectors = [
    '.hero-actions .cta-primary[data-action-tier="primary"]',
    '.hero-actions .cta-secondary[data-action-tier="secondary"]',
    '.final-cta-actions .cta-primary[data-action-tier="primary"]',
    '.final-cta-actions .cta-secondary[data-action-tier="secondary"]',
    '.proof-toggle-button',
    '.proof-snapshot-card',
  ];

  const homepageTransformSelectors = [
    'body[data-primary-cta-region="hero"] #install-section .cta-primary:hover',
    'body[data-primary-cta-region="final"] #final-cta .cta-primary:hover',
    '.proof-toggle[data-reduced-motion="false"] .proof-snapshot-card[data-selected="true"]',
  ];

  for (const selector of homepageTransitionSelectors) {
    if (!homepageReducedMotionSource.includes(selector)) {
      fail(
        scope,
        paths.homepage,
        `Reduced-motion block is missing selector ${selector}.`,
        'Restore required selector coverage to keep proof and CTA motion-safe behavior.',
      );
    }

    if (!selectorHasRuleProperty(homepageRules, selector, 'transition-none')) {
      fail(
        scope,
        paths.homepage,
        `Reduced-motion selector ${selector} is missing transition neutralization.`,
        'Add transition: none; on the same reduced-motion selector rule.',
      );
    }
  }

  for (const selector of homepageTransformSelectors) {
    if (!homepageReducedMotionSource.includes(selector)) {
      fail(
        scope,
        paths.homepage,
        `Reduced-motion block is missing selector ${selector}.`,
        'Restore required selector coverage to keep proof and CTA motion-safe behavior.',
      );
    }

    if (!selectorHasRuleProperty(homepageRules, selector, 'transform-none')) {
      fail(
        scope,
        paths.homepage,
        `Reduced-motion selector ${selector} is missing transform neutralization.`,
        'Add transform: none; on the same reduced-motion selector rule.',
      );
    }
  }
}

function writeRemediationArtifact() {
  mkdirSync(dirname(remediationMarkdownPath), { recursive: true });

  const markdownLines = [
    '# Story 5.3 Remediation Tasks',
    '',
    'Generated by `Web/scripts/validate-assistive-tech-contrast-motion.mjs`.',
    '',
    `Total findings: ${failures.length}`,
    '',
    '## Tasks',
    '',
  ];

  failures.forEach((failure, index) => {
    markdownLines.push(`${index + 1}. [ ] ${failure.scope}: ${failure.message}`);
    markdownLines.push(`   - File: ${relFromRepo(failure.filePath)}`);
    markdownLines.push(`   - Remediation: ${failure.remediation}`);
    markdownLines.push('');
  });

  const machineReadablePayload = {
    generatedAt: new Date().toISOString(),
    story: '5.3',
    validator: 'validate-assistive-tech-contrast-motion.mjs',
    findings: failures.map((failure, index) => ({
      id: index + 1,
      scope: failure.scope,
      file: relFromRepo(failure.filePath),
      message: failure.message,
      remediation: failure.remediation,
    })),
  };

  writeFileSync(remediationMarkdownPath, markdownLines.join('\n'), 'utf8');
  writeFileSync(remediationJsonPath, JSON.stringify(machineReadablePayload, null, 2), 'utf8');
}

function removeStaleRemediationArtifact() {
  if (existsSync(remediationMarkdownPath)) {
    rmSync(remediationMarkdownPath, { force: true });
  }

  if (existsSync(remediationJsonPath)) {
    rmSync(remediationJsonPath, { force: true });
  }
}

function reportAndExitIfFailures() {
  if (failures.length === 0) {
    removeStaleRemediationArtifact();
    console.log('[story-5-3] Assistive-tech, contrast, and motion-safe checks passed.');
    return;
  }

  writeRemediationArtifact();

  console.error('[story-5-3] Validation failed.');
  console.error('[story-5-3] Remediation guidance follows:');
  failures.forEach((failure, index) => {
    console.error(
      `${index + 1}. [${failure.scope}] ${relFromWeb(failure.filePath)} :: ${failure.message}`,
    );
    console.error(`   Remediation: ${failure.remediation}`);
  });
  console.error(
    `[story-5-3] Remediation tasks written to ${relFromRepo(remediationMarkdownPath)} and ${relFromRepo(remediationJsonPath)}.`,
  );
  process.exit(1);
}

function main() {
  const heroSource = readRequired(paths.hero, 'assistive-tech-contracts');
  const proofSource = readRequired(paths.proofToggle, 'assistive-tech-contracts');
  const docsSource = readRequired(paths.docsHandoff, 'assistive-tech-contracts');
  const finalSource = readRequired(paths.finalCta, 'assistive-tech-contracts');
  const tokensSource = readRequired(paths.tokens, 'contrast-wcag-aa');
  const primitivesSource = readRequired(paths.primitives, 'motion-safe-contracts');
  const homepageSource = readRequired(paths.homepage, 'motion-safe-contracts');

  if (heroSource && proofSource && docsSource && finalSource) {
    validateAssistiveTechContracts({ heroSource, proofSource, docsSource, finalSource });
  }

  if (tokensSource) {
    validateContrast(tokensSource);
  }

  if (primitivesSource && homepageSource) {
    validateMotionSafeContracts(primitivesSource, homepageSource);
  }

  reportAndExitIfFailures();
}

main();
