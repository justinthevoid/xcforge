#!/usr/bin/env bun

import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse as parseJsonc, printParseErrorCode } from 'jsonc-parser';

const REQUIRED_VAR_BINDINGS = [
	'XCFORGE_INSTALL_INTENT_TARGET',
];

const EXPECTED_ASSETS_BINDING = 'ASSETS';
const EXPECTED_OUTPUT_MODE = 'server';
const silentSuccess = process.argv.includes('--silent-success');
const requireGeneratedConfig = process.argv.includes('--require-generated-config');

const projectRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const wranglerPath = join(projectRoot, 'wrangler.jsonc');
const astroConfigPath = join(projectRoot, 'astro.config.mjs');
const generatedWranglerPath = join(projectRoot, 'dist', 'server', 'wrangler.json');

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

	let source;
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

function parseJsoncText(source, fileLabel) {
	const parseErrors = [];
	const parsed = parseJsonc(source, parseErrors, {
		allowTrailingComma: true,
		disallowComments: false,
	});

	if (parseErrors.length > 0) {
		const diagnostics = parseErrors
			.map((entry) => `${printParseErrorCode(entry.error)} at offset ${entry.offset}`)
			.join('; ');
		fail(`${fileLabel} could not be parsed as JSONC. ${diagnostics}`);
		return null;
	}

	return parsed;
}

function readWranglerConfig() {
	const source = readTextFile(
		wranglerPath,
		`Missing ${relativeToProject(wranglerPath)}. Add a Workers config file before running preview/deploy commands.`,
		`${relativeToProject(wranglerPath)} is empty. Define name, compatibility_date, vars, and env.preview.vars for Workers parity checks.`,
	);
	if (!source) {
		return null;
	}

	const parsed = parseJsoncText(source, relativeToProject(wranglerPath));
	if (parsed && typeof parsed !== 'object') {
		fail(`${relativeToProject(wranglerPath)} must contain a JSON object at the top level.`);
		return null;
	}

	return parsed;
}

function validateAstroCloudflareContract() {
	const astroConfigSource = readTextFile(
		astroConfigPath,
		`Missing ${relativeToProject(astroConfigPath)}. Configure Astro with the Cloudflare adapter and server output mode.`,
		`${relativeToProject(astroConfigPath)} is empty. Configure Astro with @astrojs/cloudflare and output: '${EXPECTED_OUTPUT_MODE}'.`,
	);
	if (!astroConfigSource) {
		return;
	}

	const cloudflareImportMatch = astroConfigSource.match(
		/import\s+([A-Za-z_$][\w$]*)\s+from\s+['"]@astrojs\/cloudflare['"]/,
	);

	if (!cloudflareImportMatch) {
		fail(
			`${relativeToProject(astroConfigPath)} must import @astrojs/cloudflare to enforce Workers-only deployment.`,
		);
		return;
	}

	const cloudflareIdentifier = cloudflareImportMatch[1];
	const adapterRegex = new RegExp(`adapter\\s*:\\s*${cloudflareIdentifier}\\s*\\(`);

	if (!adapterRegex.test(astroConfigSource)) {
		fail(
			`${relativeToProject(astroConfigPath)} must set adapter: ${cloudflareIdentifier}(). This contract is required for Workers runtime output.`,
		);
	}

	const outputModeRegex = new RegExp(`output\\s*:\\s*['"]${EXPECTED_OUTPUT_MODE}['"]`);
	if (!outputModeRegex.test(astroConfigSource)) {
		fail(
			`${relativeToProject(astroConfigPath)} must set output: '${EXPECTED_OUTPUT_MODE}' so Astro builds a Workers-compatible server bundle.`,
		);
	}
}

function toKeySet(record) {
	if (!record || typeof record !== 'object') {
		return new Set();
	}

	return new Set(Object.keys(record));
}

function validateWranglerContract(wranglerConfig) {
	if (!wranglerConfig || typeof wranglerConfig !== 'object') {
		return;
	}

	if (typeof wranglerConfig.name !== 'string' || wranglerConfig.name.trim().length === 0) {
		fail(`${relativeToProject(wranglerPath)} must define a non-empty top-level name field.`);
	}

	if (typeof wranglerConfig.pages_build_output_dir === 'string') {
		fail(
			`${relativeToProject(wranglerPath)} includes pages_build_output_dir, which is a Cloudflare Pages setting. Remove it to keep Workers as the only deployment target.`,
		);
	}

	if (
		'main' in wranglerConfig &&
		(typeof wranglerConfig.main !== 'string' || wranglerConfig.main.trim().length === 0)
	) {
		fail(
			`${relativeToProject(wranglerPath)} has an invalid main field. Remove it or set it to a non-empty worker entry path.`,
		);
	}

	if (
		typeof wranglerConfig.compatibility_date !== 'string' ||
		!/^\d{4}-\d{2}-\d{2}$/.test(wranglerConfig.compatibility_date)
	) {
		fail(
			`${relativeToProject(wranglerPath)} must include compatibility_date in YYYY-MM-DD format.`,
		);
	}

	if (!wranglerConfig.assets || typeof wranglerConfig.assets !== 'object') {
		fail(
			`${relativeToProject(wranglerPath)} must define assets.directory and assets.binding so static output is available in Workers runtime.`,
		);
	} else {
		if (wranglerConfig.assets.binding !== EXPECTED_ASSETS_BINDING) {
			fail(
				`${relativeToProject(wranglerPath)} assets.binding must be '${EXPECTED_ASSETS_BINDING}'. Current value: ${JSON.stringify(
					wranglerConfig.assets.binding,
				)}.`,
			);
		}

		if (
			typeof wranglerConfig.assets.directory !== 'string' ||
			wranglerConfig.assets.directory.length === 0
		) {
			fail(
				`${relativeToProject(wranglerPath)} assets.directory must be a non-empty string (for example './dist/client').`,
			);
		}
	}

	if (!wranglerConfig.env || typeof wranglerConfig.env !== 'object') {
		fail(
			`${relativeToProject(wranglerPath)} must define env.preview with mirrored runtime bindings for preview parity.`,
		);
		return;
	}

	if (!wranglerConfig.env.preview || typeof wranglerConfig.env.preview !== 'object') {
		fail(`${relativeToProject(wranglerPath)} must define env.preview for workers parity checks.`);
		return;
	}

	if (
		typeof wranglerConfig.env.preview.name !== 'string' ||
		wranglerConfig.env.preview.name.trim().length === 0
	) {
		fail(`${relativeToProject(wranglerPath)} env.preview.name must be a non-empty string.`);
	}

	const defaultVarKeys = toKeySet(wranglerConfig.vars);
	const previewVarKeys = toKeySet(wranglerConfig.env.preview.vars);

	const missingDefaultRequired = REQUIRED_VAR_BINDINGS.filter((name) => !defaultVarKeys.has(name));
	if (missingDefaultRequired.length > 0) {
		fail(
			`${relativeToProject(wranglerPath)} is missing required default vars: ${missingDefaultRequired.join(
				', ',
			)}. Add them under the top-level vars object.`,
		);
	}

	const missingPreviewRequired = REQUIRED_VAR_BINDINGS.filter((name) => !previewVarKeys.has(name));
	if (missingPreviewRequired.length > 0) {
		fail(
			`${relativeToProject(wranglerPath)} is missing required preview vars: ${missingPreviewRequired.join(
				', ',
			)}. Add them under env.preview.vars.`,
		);
	}

	const missingInPreview = [...defaultVarKeys].filter((name) => !previewVarKeys.has(name));
	if (missingInPreview.length > 0) {
		fail(
			`Binding parity mismatch: default vars missing from env.preview.vars: ${missingInPreview.join(
				', ',
			)}. Keep default and preview binding names aligned.`,
		);
	}

	const missingInDefault = [...previewVarKeys].filter((name) => !defaultVarKeys.has(name));
	if (missingInDefault.length > 0) {
		fail(
			`Binding parity mismatch: env.preview.vars includes names not present in default vars: ${missingInDefault.join(
				', ',
			)}. Keep default and preview binding names aligned.`,
		);
	}
}

function validateGeneratedWranglerConfig() {
	if (!requireGeneratedConfig) {
		return;
	}

	const generatedSource = readTextFile(
		generatedWranglerPath,
		`Missing ${relativeToProject(generatedWranglerPath)}. Run 'bun run build' before workers preview/deploy commands.`,
		`${relativeToProject(generatedWranglerPath)} is empty. Re-run 'bun run build' before workers preview/deploy commands.`,
	);
	if (!generatedSource) {
		return;
	}

	let generatedWranglerConfig;
	try {
		generatedWranglerConfig = JSON.parse(generatedSource);
	} catch (error) {
		fail(
			`${relativeToProject(generatedWranglerPath)} could not be parsed as JSON. Re-run 'bun run build' to regenerate it. Parser error: ${error.message}`,
		);
		return;
	}

	if (
		typeof generatedWranglerConfig.main !== 'string' ||
		generatedWranglerConfig.main.trim().length === 0
	) {
		fail(
			`${relativeToProject(generatedWranglerPath)} must include a non-empty main field generated by Astro Cloudflare adapter output.`,
		);
		return;
	}

	const generatedMainPath = join(dirname(generatedWranglerPath), generatedWranglerConfig.main);
	if (!existsSync(generatedMainPath)) {
		fail(
			`${relativeToProject(generatedWranglerPath)} points to missing main '${generatedWranglerConfig.main}'. Re-run 'bun run build' before workers preview/deploy commands.`,
		);
	}
}

const wranglerConfig = readWranglerConfig();
validateAstroCloudflareContract();
validateWranglerContract(wranglerConfig);
validateGeneratedWranglerConfig();

if (errors.length > 0) {
	console.error('\n[workers:check] Workers preflight checks failed.\n');
	for (const [index, error] of errors.entries()) {
		console.error(`${index + 1}. ${error}`);
	}

	console.error('\n[workers:check] Remediation steps:');
	console.error(
		'- Add or repair Web/wrangler.jsonc with default and env.preview binding parity.',
	);
	console.error(
		'- Ensure Web/astro.config.mjs imports @astrojs/cloudflare and sets adapter: cloudflare().',
	);
	console.error(`- Ensure Web/astro.config.mjs sets output: '${EXPECTED_OUTPUT_MODE}'.`);
	if (requireGeneratedConfig) {
		console.error('- Ensure Web build output exists: bun run build');
	}
	console.error('- Re-run checks: bun run workers:check');

	process.exit(1);
}

if (!silentSuccess) {
	console.log('[workers:check] Workers preflight checks passed.');
}
