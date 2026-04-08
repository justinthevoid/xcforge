export const claimPolicyClasses = [
	'allowed-now',
	'benchmark-gated',
	'disallowed-until-validated',
] as const;

export type ClaimPolicyClass = (typeof claimPolicyClasses)[number];

export type ClaimSupportLink = {
	label: string;
	href: string;
	summary: string;
	evidenceCapturedAt: string;
	maxAgeDays: number;
};

export type ClaimBenchmarkEvidence = {
	label: string;
	href: string;
	summary: string;
	evidenceCapturedAt: string;
	maxAgeDays: number;
};

export type ClaimPolicyRule = {
	description: string;
	publishableByDefault: boolean;
	requiresSourceMetadata: boolean;
	requiresBenchmarkEvidence: boolean;
};

export const claimsPolicySchema: Readonly<Record<ClaimPolicyClass, ClaimPolicyRule>> = {
	'allowed-now': {
		description: 'Claim is currently publishable when required source metadata is valid and fresh.',
		publishableByDefault: true,
		requiresSourceMetadata: true,
		requiresBenchmarkEvidence: false,
	},
	'benchmark-gated': {
		description:
			'Claim requires benchmark evidence metadata before it can be considered publishable.',
		publishableByDefault: false,
		requiresSourceMetadata: true,
		requiresBenchmarkEvidence: true,
	},
	'disallowed-until-validated': {
		description:
			'Claim is explicitly blocked from publication until it is reclassified through policy review.',
		publishableByDefault: false,
		requiresSourceMetadata: true,
		requiresBenchmarkEvidence: false,
	},
};

const evidenceTimestampPattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;

function hasNonEmptyText(value: unknown): value is string {
	return typeof value === 'string' && value.trim().length > 0;
}

function isClaimSupportHrefValid(href: string): boolean {
	if (href.startsWith('//')) {
		return false;
	}

	if (href.startsWith('/')) {
		return true;
	}

	try {
		const parsed = new URL(href);
		return parsed.protocol === 'http:' || parsed.protocol === 'https:';
	} catch {
		return false;
	}
}

function parseEvidenceCapturedAt(value: unknown): Date | null {
	if (!hasNonEmptyText(value) || !evidenceTimestampPattern.test(value)) {
		return null;
	}

	const parsed = new Date(value);
	if (Number.isNaN(parsed.getTime())) {
		return null;
	}

	return parsed;
}

export type ClaimSourceMetadataValidationResult = {
	hasRequiredSourceMetadata: boolean;
	hasFreshSourceMetadata: boolean;
};

export function isClaimPolicyClass(value: unknown): value is ClaimPolicyClass {
	return typeof value === 'string' && claimPolicyClasses.includes(value as ClaimPolicyClass);
}

export function validateClaimSourceMetadata(
	sectionId: string,
	claimId: string,
	links: unknown,
	messages: string[],
	now: Date,
	remediation: string,
): ClaimSourceMetadataValidationResult {
	let hasRequiredSourceMetadata = true;
	let hasFreshSourceMetadata = true;

	if (!Array.isArray(links)) {
		hasRequiredSourceMetadata = false;
		hasFreshSourceMetadata = false;
		messages.push(
			`Section "${sectionId}" claim "${claimId}" has malformed support links (expected an array). Mark this claim non-publishable. ${remediation}`,
		);
		return { hasRequiredSourceMetadata, hasFreshSourceMetadata };
	}

	if (links.length === 0) {
		hasRequiredSourceMetadata = false;
		hasFreshSourceMetadata = false;
		messages.push(
			`Section "${sectionId}" claim "${claimId}" has no supporting proof links. Mark this claim non-publishable. ${remediation}`,
		);
		return { hasRequiredSourceMetadata, hasFreshSourceMetadata };
	}

	links.forEach((rawLink, index) => {
		if (!rawLink || typeof rawLink !== 'object') {
			hasRequiredSourceMetadata = false;
			hasFreshSourceMetadata = false;
			messages.push(
				`Section "${sectionId}" claim "${claimId}" has malformed support link metadata at index ${index}. Mark this claim non-publishable. ${remediation}`,
			);
			return;
		}

		const link = rawLink as Partial<ClaimSupportLink>;

		if (
			!hasNonEmptyText(link.label) ||
			!hasNonEmptyText(link.summary) ||
			!hasNonEmptyText(link.href)
		) {
			hasRequiredSourceMetadata = false;
			hasFreshSourceMetadata = false;
			messages.push(
				`Section "${sectionId}" claim "${claimId}" support link at index ${index} is missing label, href, or summary. Mark this claim non-publishable. ${remediation}`,
			);
			return;
		}

		if (!isClaimSupportHrefValid(link.href)) {
			hasRequiredSourceMetadata = false;
			hasFreshSourceMetadata = false;
			messages.push(
				`Section "${sectionId}" claim "${claimId}" support link at index ${index} has an invalid href "${link.href}". Mark this claim non-publishable. ${remediation}`,
			);
			return;
		}

		if (
			typeof link.maxAgeDays !== 'number' ||
			!Number.isInteger(link.maxAgeDays) ||
			link.maxAgeDays < 1 ||
			link.maxAgeDays > 365
		) {
			hasRequiredSourceMetadata = false;
			hasFreshSourceMetadata = false;
			messages.push(
				`Section "${sectionId}" claim "${claimId}" support link at index ${index} has invalid maxAgeDays "${link.maxAgeDays}". Mark this claim non-publishable. ${remediation}`,
			);
			return;
		}

		const capturedAt = parseEvidenceCapturedAt(link.evidenceCapturedAt);
		if (!capturedAt) {
			hasRequiredSourceMetadata = false;
			hasFreshSourceMetadata = false;
			messages.push(
				`Section "${sectionId}" claim "${claimId}" support link at index ${index} has invalid evidenceCapturedAt "${link.evidenceCapturedAt}". Mark this claim non-publishable. ${remediation}`,
			);
			return;
		}

		const maxAgeMs = link.maxAgeDays * 24 * 60 * 60 * 1000;
		const ageMs = now.getTime() - capturedAt.getTime();
		if (ageMs < 0) {
			hasRequiredSourceMetadata = false;
			hasFreshSourceMetadata = false;
			messages.push(
				`Section "${sectionId}" claim "${claimId}" support link at index ${index} has a future evidenceCapturedAt value. Mark this claim non-publishable. ${remediation}`,
			);
			return;
		}

		if (ageMs > maxAgeMs) {
			hasFreshSourceMetadata = false;
			const ageDays = Math.ceil(ageMs / (24 * 60 * 60 * 1000));
			messages.push(
				`Section "${sectionId}" claim "${claimId}" support link at index ${index} is stale (${ageDays} days old; max ${link.maxAgeDays}). Mark this claim non-publishable. ${remediation}`,
			);
		}
	});

	return { hasRequiredSourceMetadata, hasFreshSourceMetadata };
}

function hasBenchmarkEvidence(
	benchmarkEvidence: unknown,
	messages: string[],
	sectionId: string,
	claimId: string,
	remediation: string,
): boolean {
	if (!benchmarkEvidence || typeof benchmarkEvidence !== 'object') {
		messages.push(
			`Section "${sectionId}" claim "${claimId}" is benchmark-gated but benchmarkEvidence is missing. Mark this claim non-publishable. ${remediation}`,
		);
		return false;
	}

	const benchmark = benchmarkEvidence as Partial<ClaimBenchmarkEvidence>;
	if (
		!hasNonEmptyText(benchmark.label) ||
		!hasNonEmptyText(benchmark.summary) ||
		!hasNonEmptyText(benchmark.href)
	) {
		messages.push(
			`Section "${sectionId}" claim "${claimId}" is benchmark-gated but benchmarkEvidence is missing label, href, or summary. Mark this claim non-publishable. ${remediation}`,
		);
		return false;
	}

	if (!isClaimSupportHrefValid(benchmark.href)) {
		messages.push(
			`Section "${sectionId}" claim "${claimId}" benchmarkEvidence has invalid href "${benchmark.href}". Mark this claim non-publishable. ${remediation}`,
		);
		return false;
	}

	if (
		typeof benchmark.maxAgeDays !== 'number' ||
		!Number.isInteger(benchmark.maxAgeDays) ||
		benchmark.maxAgeDays < 1 ||
		benchmark.maxAgeDays > 365
	) {
		messages.push(
			`Section "${sectionId}" claim "${claimId}" benchmarkEvidence has invalid maxAgeDays "${benchmark.maxAgeDays}". Mark this claim non-publishable. ${remediation}`,
		);
		return false;
	}

	const capturedAt = parseEvidenceCapturedAt(benchmark.evidenceCapturedAt);
	if (!capturedAt) {
		messages.push(
			`Section "${sectionId}" claim "${claimId}" benchmarkEvidence has invalid evidenceCapturedAt "${benchmark.evidenceCapturedAt}". Mark this claim non-publishable. ${remediation}`,
		);
		return false;
	}

	return true;
}

export type ValidateNarrativeClaimPolicyInput = {
	sectionId: string;
	claimId: string;
	policyClass: unknown;
	supportLinks: unknown;
	benchmarkEvidence: unknown;
	messages: string[];
	now: Date;
	claimSupportRemediation: string;
	claimPolicyRemediation: string;
	benchmarkRemediation: string;
};

export function validateNarrativeClaimPolicy({
	sectionId,
	claimId,
	policyClass,
	supportLinks,
	benchmarkEvidence,
	messages,
	now,
	claimSupportRemediation,
	claimPolicyRemediation,
	benchmarkRemediation,
}: ValidateNarrativeClaimPolicyInput): void {
	if (!isClaimPolicyClass(policyClass)) {
		messages.push(
			`Section "${sectionId}" claim "${claimId}" has invalid policy class "${String(policyClass)}". Expected one of: ${claimPolicyClasses.join(', ')}. Mark this claim non-publishable. ${claimPolicyRemediation}`,
		);
		return;
	}

	const policyRule = claimsPolicySchema[policyClass];

	const sourceMetadata = validateClaimSourceMetadata(
		sectionId,
		claimId,
		supportLinks,
		messages,
		now,
		claimSupportRemediation,
	);
	const hasPublishableSourceMetadata =
		sourceMetadata.hasRequiredSourceMetadata && sourceMetadata.hasFreshSourceMetadata;

	if (policyRule.requiresSourceMetadata && !hasPublishableSourceMetadata) {
		messages.push(
			`Section "${sectionId}" claim "${claimId}" policy class "${policyClass}" is treated as "disallowed-until-validated" because required source metadata is missing, malformed, or stale. ${claimPolicyRemediation}`,
		);
	}

	if (policyClass === 'disallowed-until-validated') {
		messages.push(
			`Section "${sectionId}" claim "${claimId}" is explicitly classed as "disallowed-until-validated" and cannot be published. ${claimPolicyRemediation}`,
		);
		return;
	}

	if (policyRule.requiresBenchmarkEvidence) {
		const benchmarkPresent = hasBenchmarkEvidence(
			benchmarkEvidence,
			messages,
			sectionId,
			claimId,
			benchmarkRemediation,
		);
		if (!benchmarkPresent) {
			messages.push(
				`Section "${sectionId}" claim "${claimId}" remains non-publishable until benchmark metadata is complete and policy review confirms promotion. ${benchmarkRemediation}`,
			);
		}
	}
}
