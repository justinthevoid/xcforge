#!/usr/bin/env bun

import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const MIN_BUN_VERSION = '1.3.10';
const MIN_NODE_VERSION = '22.12.0';

const phaseArg = process.argv.find((arg) => arg.startsWith('--phase='));
const phase = phaseArg ? phaseArg.split('=')[1] : 'default';
const isPreinstall = phase === 'preinstall';
const isWorkersPhase = phase === 'workers';
const projectRoot = join(dirname(fileURLToPath(import.meta.url)), '..');

const failures = [];
const warnings = [];

function parseVersion(value) {
	return value
		.replace(/^v/, '')
		.split('.')
		.map((segment) => Number.parseInt(segment, 10) || 0);
}

function compareSemver(left, right) {
	const leftParts = parseVersion(left);
	const rightParts = parseVersion(right);
	const length = Math.max(leftParts.length, rightParts.length);

	for (let index = 0; index < length; index += 1) {
		const leftValue = leftParts[index] ?? 0;
		const rightValue = rightParts[index] ?? 0;
		if (leftValue > rightValue) return 1;
		if (leftValue < rightValue) return -1;
	}

	return 0;
}

function isVersionAtLeast(version, minimum) {
	return compareSemver(version, minimum) >= 0;
}

const bunVersion = process.versions.bun;
if (!bunVersion) {
	failures.push(
		'Bun runtime was not detected. Run commands with Bun (for example: bun install, bun run validate).',
	);
} else if (!isVersionAtLeast(bunVersion, MIN_BUN_VERSION)) {
	failures.push(`Detected Bun ${bunVersion}. Minimum supported version is ${MIN_BUN_VERSION}.`);
}

const nodeVersionResult = spawnSync('node', ['--version'], { encoding: 'utf8' });
const nodeVersion = nodeVersionResult.status === 0 ? nodeVersionResult.stdout.trim() : '';

if (!nodeVersion) {
	failures.push(
		`Node.js was not detected. Minimum supported version is ${MIN_NODE_VERSION}. Install Node.js ${MIN_NODE_VERSION}+ to match Astro baseline compatibility.`,
	);
} else if (!isVersionAtLeast(nodeVersion, MIN_NODE_VERSION)) {
	failures.push(
		`Detected Node.js ${nodeVersion.replace(/^v/, '')}. Minimum supported version is ${MIN_NODE_VERSION}.`,
	);
}

if (!isPreinstall) {
	const requiredDependencyPaths = [
		'node_modules/astro/package.json',
		'node_modules/@astrojs/starlight/package.json',
		'node_modules/@astrojs/svelte/package.json',
		'node_modules/@biomejs/biome/package.json',
	];

	if (isWorkersPhase) {
		requiredDependencyPaths.push(
			'node_modules/@astrojs/cloudflare/package.json',
			'node_modules/wrangler/package.json',
		);
	}

	const missingPaths = requiredDependencyPaths.filter(
		(relativePath) => !existsSync(join(projectRoot, relativePath)),
	);

	if (missingPaths.length > 0) {
		failures.push(
			`Dependencies are missing or bootstrap is incomplete. Missing: ${missingPaths.join(
				', ',
			)}. Reinstall dependencies with Bun before running checks.`,
		);
	}
}

if (isWorkersPhase && failures.length === 0) {
	const workersCheck = spawnSync(
		'bun',
		['run', 'scripts/validate-workers-config.mjs', '--silent-success'],
		{
			cwd: projectRoot,
			stdio: 'inherit',
		},
	);

	if (workersCheck.error) {
		failures.push(`Workers preflight command could not execute: ${workersCheck.error.message}.`);
	} else if (workersCheck.status !== 0) {
		process.exit(workersCheck.status ?? 1);
	}
}

if (failures.length > 0) {
	console.error('\n[doctor] Setup checks failed.\n');
	for (const [index, failure] of failures.entries()) {
		console.error(`${index + 1}. ${failure}`);
	}

	console.error('\n[doctor] Recommended remediation steps:');
	console.error('- Install or upgrade Bun: brew install bun && brew upgrade bun');
	console.error(`- Install Node.js ${MIN_NODE_VERSION}+: brew install node@22`);
	console.error('- Reinstall Web workspace dependencies: rm -rf node_modules && bun install');
	console.error('- If lockfile regeneration is required: rm -f bun.lock && bun install');
	console.error('- Re-run diagnostics: bun run doctor && bun run validate');
	console.error('- If install still fails: bun install --verbose');
	console.error('- Troubleshooting guide: README.md');

	process.exit(1);
}

if (warnings.length > 0) {
	console.warn('\n[doctor] Warnings:');
	for (const warning of warnings) {
		console.warn(`- ${warning}`);
	}
}

const checkScope = isPreinstall
	? 'runtime'
	: isWorkersPhase
		? 'runtime + dependency + workers contract'
		: 'runtime + dependency';
console.log(`[doctor] ${checkScope} checks passed.`);
