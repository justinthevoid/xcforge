import {
	type ClaimBenchmarkEvidence,
	type ClaimPolicyClass,
	type ClaimSupportLink,
	validateNarrativeClaimPolicy,
} from './claims-policy';

export type NavItemId = 'product' | 'docs' | 'workflow-guide' | 'changelog' | 'github' | 'install';

export type NavItem = {
	id: NavItemId;
	label: string;
	href: string;
	external?: boolean;
};

export type HeroCopy = {
	problemLine: string;
	productRole: string;
	installCommand: string;
	installHref: string;
	installExternal?: boolean;
	proofHeadline: string;
	proofClaims: ApprovedTrustClaim[];
	proofSnapshots: ProofSnapshot[];
	defaultProofSnapshotId: ProofSnapshotId;
	provenanceUnavailableDocsHref: string;
	fallbackProofText: string;
};

export const approvedTrustClaimCatalog = {
	'mcp-tools': '103 MCP tools',
	'cli-command-groups': '17 CLI command groups',
	'native-swift-binary': 'Native Swift binary',
	'no-external-runtime-dependencies': 'No external runtime dependencies',
} as const;

export type ApprovedTrustClaimId = keyof typeof approvedTrustClaimCatalog;

export type ApprovedTrustClaim = {
	id: ApprovedTrustClaimId;
	text: (typeof approvedTrustClaimCatalog)[ApprovedTrustClaimId];
	policyClass: 'allowed-now';
	supportLinks: ClaimSupportLink[];
};

export type ProofSnapshotId = 'manual-baseline' | 'xcforge-proof';

export type ProofSnapshot = {
	id: ProofSnapshotId;
	label: string;
	summary: string;
	announcement: string;
	supportLinks: ClaimSupportLink[];
};

export type ProofProvenanceState = 'fresh' | 'stale' | 'warning';

export type ProofSupportLinkForRender = ClaimSupportLink & {
	ageDays: number | null;
	capturedOnLabel: string;
	freshnessLabel: string;
	state: ProofProvenanceState;
};

export type ProofProvenanceForRender = {
	state: ProofProvenanceState;
	stateLabel: string;
	stateDetail: string;
	sources: ProofSupportLinkForRender[];
	fallbackHref: string;
};

export type ApprovedTrustClaimForRender = ApprovedTrustClaim & {
	provenance: ProofProvenanceForRender;
};

export type ProofSnapshotForRender = ProofSnapshot & {
	provenance: ProofProvenanceForRender;
};

export type HomepageNarrativeSectionId =
	| 'hero'
	| 'problem'
	| 'solution'
	| 'workflows'
	| 'differentiation'
	| 'docs-handoff'
	| 'final-cta';

type HomepageNarrativeSectionBase = {
	heading: string;
	purpose: string;
};

export type ProblemSectionCopy = HomepageNarrativeSectionBase & {
	id: 'problem';
	painSignals: NarrativeClaim[];
};

export type SolutionSectionCopy = HomepageNarrativeSectionBase & {
	id: 'solution';
	capabilities: NarrativeClaim[];
};

export type NarrativeJourneyId =
	| 'failing-build-or-test-to-verified-fix'
	| 'simulator-recovery-and-stabilization'
	| 'lldb-assisted-diagnosis'
	| 'evidence-backed-verification';

export type NarrativeJourneyArtifact =
	| {
			status: 'available';
			label: string;
			href: string;
			summary: string;
			external?: boolean;
	  }
	| {
			status: 'unavailable';
			unavailableMessage: string;
	  };

export type NarrativeJourney = {
	id: NarrativeJourneyId;
	title: string;
	detail: string;
	outcome: string;
	artifact: NarrativeJourneyArtifact;
};

export type WorkflowsJourneysSectionCopy = HomepageNarrativeSectionBase & {
	id: 'workflows';
	journeys: NarrativeJourney[];
};

export type DifferentiationPoint = {
	title: string;
	detail: string;
};

export type DifferentiationProofSectionCopy = HomepageNarrativeSectionBase & {
	id: 'differentiation';
	points: DifferentiationPoint[];
	proofClaims: ApprovedTrustClaim[];
	proofOutcomeSummary: string;
	provenanceUnavailableDocsHref: string;
};

export type DocsHandoffLink = {
	label: string;
	href: string;
	summary: string;
	external?: boolean;
	fallbackHref?: string;
	unavailableMessage?: string;
	destinationId?: 'docs' | 'workflow-guide';
};

export type NarrativeClaim = {
	id: string;
	text: string;
	policyClass: ClaimPolicyClass;
	supportLinks: ClaimSupportLink[];
	benchmarkEvidence?: ClaimBenchmarkEvidence;
};

export type DocsHandoffSectionCopy = HomepageNarrativeSectionBase & {
	id: 'docs-handoff';
	handoffLinks: DocsHandoffLink[];
};

export type HomepageNarrativeBodySection =
	| ProblemSectionCopy
	| SolutionSectionCopy
	| WorkflowsJourneysSectionCopy
	| DifferentiationProofSectionCopy
	| DocsHandoffSectionCopy;

export type FinalCtaCopy = {
	heading: string;
	summary: string;
	installLabel: string;
	installCommand: string;
	installHref: string;
	installExternal?: boolean;
	workflowLabel: string;
	workflowHref: string;
	handoffTitle: string;
	handoffReadyMessage: string;
	handoffFailureMessage: string;
	handoffRestoredMessage: string;
	handoffCopyButtonLabel: string;
	handoffGuideLabel: string;
};

export type HomepageContent = {
	navigation: NavItem[];
	hero: HeroCopy;
	narrativeSections: HomepageNarrativeBodySection[];
	finalCta: FinalCtaCopy;
};

export type HomepageNarrativeSectionContract = {
	id: HomepageNarrativeSectionId;
	heading: string;
	purpose: string;
};

export type HomepageNarrativeValidationResult = {
	isValid: boolean;
	messages: string[];
	expectedOrder: readonly HomepageNarrativeSectionId[];
	actualOrder: HomepageNarrativeSectionId[];
};

export type HomepageNarrativeSectionsForRender = {
	problem: ProblemSectionCopy;
	solution: SolutionSectionCopy;
	workflows: WorkflowsJourneysSectionCopy;
	differentiation: DifferentiationProofSectionCopy;
	docsHandoff: DocsHandoffSectionCopy;
};

const requiredNavOrder: NavItemId[] = [
	'product',
	'docs',
	'workflow-guide',
	'changelog',
	'github',
	'install',
];

export const requiredHomepageNarrativeSectionOrder: readonly HomepageNarrativeSectionId[] = [
	'hero',
	'problem',
	'solution',
	'workflows',
	'differentiation',
	'docs-handoff',
	'final-cta',
];

const safeNavigationFallback: NavItem[] = [
	{ id: 'product', label: 'Product', href: '#product' },
	{ id: 'docs', label: 'Docs', href: '/docs' },
	{ id: 'workflow-guide', label: 'Workflow Guide', href: '/docs/getting-started/' },
	{
		id: 'changelog',
		label: 'Changelog',
		href: 'https://github.com/justinthevoid/xcforge/blob/main/CHANGELOG.md',
		external: true,
	},
	{
		id: 'github',
		label: 'GitHub',
		href: 'https://github.com/justinthevoid/xcforge',
		external: true,
	},
	{ id: 'install', label: 'Install', href: '#install-section' },
];

const installCommand = 'brew install xcforge';
const installGuideHref = 'https://github.com/justinthevoid/xcforge#install';
const proofProvenanceDocsHref = '/docs/proof-provenance/';

const approvedTrustClaims: ApprovedTrustClaim[] = [
	{
		id: 'mcp-tools',
		text: approvedTrustClaimCatalog['mcp-tools'],
		policyClass: 'allowed-now',
		supportLinks: [
			{
				label: 'Docs overview',
				href: '/docs',
				summary: 'Lists command coverage and technical surface area used by trust claims.',
				evidenceCapturedAt: '2026-04-07T00:00:00Z',
				maxAgeDays: 30,
			},
		],
	},
	{
		id: 'cli-command-groups',
		text: approvedTrustClaimCatalog['cli-command-groups'],
		policyClass: 'allowed-now',
		supportLinks: [
			{
				label: 'Getting Started workflow guide',
				href: '/docs/getting-started/',
				summary: 'Shows install and verification pathways tied to command-group usage.',
				evidenceCapturedAt: '2026-04-07T00:00:00Z',
				maxAgeDays: 30,
			},
		],
	},
	{
		id: 'native-swift-binary',
		text: approvedTrustClaimCatalog['native-swift-binary'],
		policyClass: 'allowed-now',
		supportLinks: [
			{
				label: 'README feature summary',
				href: 'https://github.com/justinthevoid/xcforge#features',
				summary: 'Documents implementation characteristics and technical capability framing.',
				evidenceCapturedAt: '2026-04-07T00:00:00Z',
				maxAgeDays: 30,
			},
		],
	},
	{
		id: 'no-external-runtime-dependencies',
		text: approvedTrustClaimCatalog['no-external-runtime-dependencies'],
		policyClass: 'allowed-now',
		supportLinks: [
			{
				label: 'Changelog source trail',
				href: 'https://github.com/justinthevoid/xcforge/blob/main/CHANGELOG.md',
				summary: 'Tracks release evidence and source-backed updates over time.',
				evidenceCapturedAt: '2026-04-07T00:00:00Z',
				maxAgeDays: 30,
			},
		],
	},
];

const heroProofSnapshots: ProofSnapshot[] = [
	{
		id: 'manual-baseline',
		label: 'Manual baseline',
		summary:
			'Manual tool stitching can leave diagnostics and verification evidence fragmented across separate steps.',
		announcement:
			'Manual baseline selected. This state describes current workflow friction, not a benchmark claim.',
		supportLinks: [
			{
				label: 'Workflow Guide baseline context',
				href: '/docs/getting-started/',
				summary: 'Provides baseline local workflow context for comparison.',
				evidenceCapturedAt: '2026-04-07T00:00:00Z',
				maxAgeDays: 30,
			},
		],
	},
	{
		id: 'xcforge-proof',
		label: 'xcforge proof',
		summary:
			'xcforge keeps local execution surfaces in one contract so build, simulator, debugger, and evidence paths stay inspectable.',
		announcement:
			'xcforge proof selected. This state summarizes observed capability scope with conservative language.',
		supportLinks: [
			{
				label: 'Workflow Guide verification path',
				href: '/docs/getting-started/',
				summary: 'Maps failing-run diagnosis and verification checkpoints.',
				evidenceCapturedAt: '2026-04-07T00:00:00Z',
				maxAgeDays: 30,
			},
			{
				label: 'Release evidence log',
				href: 'https://github.com/justinthevoid/xcforge/blob/main/CHANGELOG.md',
				summary: 'Tracks source-backed updates tied to workflow verification behavior.',
				evidenceCapturedAt: '2026-04-07T00:00:00Z',
				maxAgeDays: 30,
			},
		],
	},
];

export const homepageContent: HomepageContent = {
	navigation: safeNavigationFallback,
	hero: {
		problemLine:
			'AI code suggestions are fast. Local iOS verification loops are where momentum stalls.',
		productRole:
			'xcforge gives agents hands-on control of build, test, simulators, logs, screenshots, and debug loops so outcomes are verifiable.',
		installCommand,
		installHref: installGuideHref,
		installExternal: true,
		proofHeadline: 'Proof you can inspect in one scan',
		proofClaims: approvedTrustClaims,
		proofSnapshots: heroProofSnapshots,
		defaultProofSnapshotId: 'xcforge-proof',
		provenanceUnavailableDocsHref: proofProvenanceDocsHref,
		fallbackProofText:
			'Proof metadata is temporarily unavailable. Install via Homebrew now, then verify workflows in docs and changelog.',
	},
	narrativeSections: [
		{
			id: 'problem',
			heading: 'The failure point is local verification, not code generation.',
			purpose:
				'AI-generated code often gets close, but iOS teams still lose time stitching together build, simulator, and debugging evidence before they can trust a fix.',
			painSignals: [
				{
					id: 'local-state-mismatch',
					text: 'Build or test suggestions pass in-chat, then fail against real local Xcode and simulator state.',
					policyClass: 'allowed-now',
					supportLinks: [
						{
							label: 'Workflow Guide: install-first local verification path',
							href: '/docs/getting-started/',
							summary:
								'Documents the transition from failing local run to reproducible verification output.',
							evidenceCapturedAt: '2026-04-07T00:00:00Z',
							maxAgeDays: 30,
						},
					],
				},
				{
					id: 'fragmented-evidence',
					text: 'Logs, screenshots, LLDB output, and UI state live in disconnected tools with no single execution thread.',
					policyClass: 'allowed-now',
					supportLinks: [
						{
							label: 'Docs reference: command-group coverage',
							href: '/docs',
							summary:
								'Provides command-group details across diagnostics, evidence capture, and local execution surfaces.',
							evidenceCapturedAt: '2026-04-07T00:00:00Z',
							maxAgeDays: 30,
						},
					],
				},
				{
					id: 'manual-rescue-loop',
					text: 'Each rescue loop becomes manual context switching that is slow to verify and hard to hand off.',
					policyClass: 'allowed-now',
					supportLinks: [
						{
							label: 'Changelog evidence trail',
							href: 'https://github.com/justinthevoid/xcforge/blob/main/CHANGELOG.md',
							summary:
								'Tracks concrete local workflow fixes and verification-oriented release notes.',
							evidenceCapturedAt: '2026-04-07T00:00:00Z',
							maxAgeDays: 30,
						},
					],
				},
			],
		},
		{
			id: 'solution',
			heading: 'xcforge is a unified local execution layer for the iOS loop.',
			purpose:
				'Instead of stitching Apple tools and agent prompts manually, run the full local workflow through one contract that keeps outcomes verifiable.',
			capabilities: [
				{
					id: 'unified-command-surface',
					text: 'Run build, test, simulator control, and diagnostics from one command surface.',
					policyClass: 'allowed-now',
					supportLinks: [
						{
							label: 'xcforge docs reference',
							href: '/docs',
							summary: 'Describes the unified execution layer and command-group coverage model.',
							evidenceCapturedAt: '2026-04-07T00:00:00Z',
							maxAgeDays: 30,
						},
					],
				},
				{
					id: 'evidence-capture',
					text: 'Capture logs, screenshots, UI inspection output, and LLDB diagnostics as reusable evidence.',
					policyClass: 'allowed-now',
					supportLinks: [
						{
							label: 'README capability summary',
							href: 'https://github.com/justinthevoid/xcforge#features',
							summary:
								'Supports build, test, simulator, debugging, and verification capability framing.',
							evidenceCapturedAt: '2026-04-07T00:00:00Z',
							maxAgeDays: 30,
						},
					],
				},
				{
					id: 'verification-closure',
					text: 'Move from failing run to verified fix with deterministic local execution steps and explicit verification checkpoints.',
					policyClass: 'allowed-now',
					supportLinks: [
						{
							label: 'Workflow Guide verification flow',
							href: '/docs/getting-started/',
							summary:
								'Shows install-first and verification-first pathways for local run confirmation.',
							evidenceCapturedAt: '2026-04-07T00:00:00Z',
							maxAgeDays: 30,
						},
					],
				},
			],
		},
		{
			id: 'workflows',
			heading: 'Workflow journeys map directly to real failure-to-proof scenarios.',
			purpose:
				'Each journey is outcome-first so evaluators can quickly judge if xcforge fits their current rescue loops.',
			journeys: [
				{
					id: 'failing-build-or-test-to-verified-fix',
					title: 'Failing build or test to verified fix',
					detail:
						'Start from a broken run, execute diagnosis steps, apply fixes, and verify with reproducible output.',
					outcome:
						'Outcome: move from failing local state to a confirmed fix with reproducible evidence.',
					artifact: {
						status: 'available',
						label: 'Workflow Guide: failing run to verified fix',
						href: '/docs/getting-started/',
						summary:
							'Documents the local diagnosis path and final verification checkpoints for a repaired run.',
					},
				},
				{
					id: 'simulator-recovery-and-stabilization',
					title: 'Simulator recovery and stabilization',
					detail:
						'Recover unstable simulator state quickly so agent workflows stay unblocked and repeatable.',
					outcome:
						'Outcome: recover a stable simulator session so validation loops can proceed without manual reset churn.',
					artifact: {
						status: 'available',
						label: 'Docs: simulator control and recovery references',
						href: '/docs',
						summary:
							'Indexes simulator control surfaces used to recover and stabilize local execution state.',
					},
				},
				{
					id: 'lldb-assisted-diagnosis',
					title: 'LLDB-assisted diagnosis',
					detail:
						'Use structured LLDB flows to inspect runtime behavior and isolate root causes without guesswork.',
					outcome:
						'Outcome: isolate runtime faults with debugger-backed evidence that can be handed off confidently.',
					artifact: {
						status: 'available',
						label: 'README: debugger and diagnosis capability summary',
						href: 'https://github.com/justinthevoid/xcforge#features',
						summary:
							'Links debugger-focused capability coverage used in LLDB-assisted diagnosis journeys.',
						external: true,
					},
				},
				{
					id: 'evidence-backed-verification',
					title: 'Evidence-backed verification',
					detail:
						'Capture screenshots and logs to prove what changed and confirm the fix with concrete artifacts.',
					outcome:
						'Outcome: publish verified before/after evidence so fixes are auditable instead of anecdotal.',
					artifact: {
						status: 'available',
						label: 'Changelog: workflow evidence and release validation',
						href: 'https://github.com/justinthevoid/xcforge/blob/main/CHANGELOG.md',
						summary:
							'Tracks evidence-backed workflow updates and verification-oriented release notes over time.',
						external: true,
					},
				},
			],
		},
		{
			id: 'differentiation',
			heading: 'Differentiation comes from local-first depth and trust discipline.',
			purpose:
				'xcforge is built for technical evaluators who need credible execution evidence, not generic automation claims.',
			proofClaims: approvedTrustClaims,
			proofOutcomeSummary:
				'These proof claims describe currently verifiable capability scope. They are not broad speed or benchmark assertions.',
			provenanceUnavailableDocsHref: proofProvenanceDocsHref,
			points: [
				{
					title: 'Local-first by default',
					detail:
						'Execution happens where iOS outcomes are decided: your local build, simulator, and debugger loop.',
				},
				{
					title: 'Proof-oriented output',
					detail:
						'Trust markers link directly to docs, changelog, and workflow evidence so claims stay inspectable.',
				},
				{
					title: 'End-to-end workflow coverage',
					detail:
						'Build, test, simulator control, diagnosis, and verification stay in one contract without broad productivity hype.',
				},
			],
		},
		{
			id: 'docs-handoff',
			heading: 'Go one click deeper when you need implementation detail.',
			purpose:
				'High-intent evaluators can jump straight to docs and workflow references without losing install momentum.',
			handoffLinks: [
				{
					label: 'Read the Docs',
					href: '/docs?handoff=deep-dive&destination=docs',
					summary: 'Inspect command groups, capabilities, and reference material.',
					fallbackHref: '/docs',
					unavailableMessage:
						'Docs overview is temporarily unavailable. You were redirected to the docs index.',
					destinationId: 'docs',
				},
				{
					label: 'Open Workflow Guide',
					href: '/docs/getting-started/?handoff=deep-dive&destination=workflow-guide',
					summary: 'Follow install-first paths from failing run to verified outcome.',
					fallbackHref: '/docs',
					unavailableMessage:
						'Workflow Guide is temporarily unavailable. You were redirected to the docs index.',
					destinationId: 'workflow-guide',
				},
				{
					label: 'Review Changelog',
					href: 'https://github.com/justinthevoid/xcforge/blob/main/CHANGELOG.md',
					summary: 'Track release evidence and recent workflow improvements.',
					external: true,
				},
			],
		},
	],
	finalCta: {
		heading: 'Ready to run xcforge in your next iOS loop?',
		summary: 'Install now, or carry your install intent forward on mobile and finish on desktop.',
		installLabel: 'Install via Homebrew',
		installCommand,
		installHref: installGuideHref,
		installExternal: true,
		workflowLabel: 'Workflow Guide',
		workflowHref: '/docs/getting-started/',
		handoffTitle: 'Install intent handoff',
		handoffReadyMessage:
			'Install intent captured for later completion. Copy the command or open the install guide.',
		handoffFailureMessage:
			'Install intent could not be saved on this device. Copy the command or open the install guide to continue.',
		handoffRestoredMessage:
			'Saved install intent restored. Continue with the command below when you are ready.',
		handoffCopyButtonLabel: 'Copy command',
		handoffGuideLabel: 'Open install guide',
	},
};

function isValidNavItem(item: NavItem | undefined): item is NavItem {
	if (!item) {
		return false;
	}

	return item.label.trim().length > 0 && item.href.trim().length > 0;
}

export function resolveNavigationMetadata(navigation: NavItem[] | undefined): {
	items: NavItem[];
	isMetadataAvailable: boolean;
} {
	if (!navigation?.length) {
		return { items: safeNavigationFallback, isMetadataAvailable: false };
	}

	const byId = new Map<NavItemId, NavItem>();
	for (const item of navigation) {
		if (!isValidNavItem(item)) {
			continue;
		}
		byId.set(item.id, item);
	}

	const orderedItems: NavItem[] = [];
	for (const navId of requiredNavOrder) {
		const navItem = byId.get(navId);
		if (!navItem) {
			return { items: safeNavigationFallback, isMetadataAvailable: false };
		}
		orderedItems.push(navItem);
	}

	return { items: orderedItems, isMetadataAvailable: true };
}

export function isProofMetadataAvailable(hero: HeroCopy | undefined): boolean {
	if (!hero) {
		return false;
	}

	return (
		hero.problemLine.trim().length > 0 &&
		hero.productRole.trim().length > 0 &&
		hero.installHref.trim().length > 0 &&
		hero.proofHeadline.trim().length > 0 &&
		hero.provenanceUnavailableDocsHref.trim().length > 0 &&
		hasExactApprovedTrustClaims(hero.proofClaims) &&
		hasValidHeroProofSnapshots(hero)
	);
}

export function createHomepageNarrativeSectionContract(
	content: HomepageContent,
): HomepageNarrativeSectionContract[] {
	return [
		{
			id: 'hero',
			heading: content.hero.problemLine,
			purpose: content.hero.productRole,
		},
		...content.narrativeSections.map((section) => ({
			id: section.id,
			heading: section.heading,
			purpose: section.purpose,
		})),
		{
			id: 'final-cta',
			heading: content.finalCta.heading,
			purpose: content.finalCta.summary,
		},
	];
}

function hasNonEmptyText(value: unknown): value is string {
	return typeof value === 'string' && value.trim().length > 0;
}

const evidenceTimestampPattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;
const proofDateFormatter = new Intl.DateTimeFormat('en-US', {
	month: 'short',
	day: 'numeric',
	year: 'numeric',
});

function parseEvidenceTimestamp(value: unknown): Date | null {
	if (!hasNonEmptyText(value) || !evidenceTimestampPattern.test(value)) {
		return null;
	}

	const parsed = new Date(value);
	if (Number.isNaN(parsed.getTime())) {
		return null;
	}

	return parsed;
}

export function resolveProvenanceFallbackHrefForRender(fallbackHref: unknown): string {
	if (hasNonEmptyText(fallbackHref) && isClaimSupportHrefValid(fallbackHref)) {
		return fallbackHref;
	}

	return proofProvenanceDocsHref;
}

function resolveProofProvenanceStateLabel(state: ProofProvenanceState): string {
	switch (state) {
		case 'fresh':
			return 'Fresh evidence';
		case 'stale':
			return 'Stale evidence';
		default:
			return 'Provenance warning';
	}
}

function resolveProofSourceForRender(source: unknown, now: Date): ProofSupportLinkForRender | null {
	if (!source || typeof source !== 'object') {
		return null;
	}

	const rawSource = source as Partial<ClaimSupportLink>;
	if (
		!hasNonEmptyText(rawSource.label) ||
		!hasNonEmptyText(rawSource.href) ||
		!hasNonEmptyText(rawSource.summary)
	) {
		return null;
	}

	if (!isClaimSupportHrefValid(rawSource.href)) {
		return null;
	}

	if (
		typeof rawSource.maxAgeDays !== 'number' ||
		!Number.isInteger(rawSource.maxAgeDays) ||
		rawSource.maxAgeDays < 1 ||
		rawSource.maxAgeDays > 365
	) {
		return null;
	}

	const capturedAt = parseEvidenceTimestamp(rawSource.evidenceCapturedAt);
	if (!capturedAt) {
		return null;
	}

	const ageMs = now.getTime() - capturedAt.getTime();
	if (ageMs < 0) {
		return null;
	}

	const maxAgeMs = rawSource.maxAgeDays * 24 * 60 * 60 * 1000;
	const ageDays = Math.max(0, Math.floor(ageMs / (24 * 60 * 60 * 1000)));
	const state: ProofProvenanceState = ageMs > maxAgeMs ? 'stale' : 'fresh';
	const freshnessLabel =
		state === 'fresh'
			? `Captured ${ageDays} day${ageDays === 1 ? '' : 's'} ago`
			: `Stale: ${ageDays} days old (max ${rawSource.maxAgeDays})`;

	return {
		label: rawSource.label,
		href: rawSource.href,
		summary: rawSource.summary,
		evidenceCapturedAt: capturedAt.toISOString(),
		maxAgeDays: rawSource.maxAgeDays,
		ageDays,
		capturedOnLabel: proofDateFormatter.format(capturedAt),
		freshnessLabel,
		state,
	};
}

export function resolveProofProvenanceForRender(
	rawSources: unknown,
	fallbackHref: string,
	now = new Date(),
): ProofProvenanceForRender {
	const safeFallbackHref = resolveProvenanceFallbackHrefForRender(fallbackHref);

	if (!Array.isArray(rawSources) || rawSources.length === 0) {
		return {
			state: 'warning',
			stateLabel: resolveProofProvenanceStateLabel('warning'),
			stateDetail: 'Source and freshness metadata are temporarily unavailable for this artifact.',
			sources: [],
			fallbackHref: safeFallbackHref,
		};
	}

	let invalidSourceCount = 0;
	const sources: ProofSupportLinkForRender[] = [];

	for (const rawSource of rawSources) {
		const resolvedSource = resolveProofSourceForRender(rawSource, now);
		if (!resolvedSource) {
			invalidSourceCount += 1;
			continue;
		}

		sources.push(resolvedSource);
	}

	if (sources.length === 0) {
		return {
			state: 'warning',
			stateLabel: resolveProofProvenanceStateLabel('warning'),
			stateDetail:
				'Source metadata could not be parsed for this artifact. Use provenance guidance before treating this as current proof.',
			sources: [],
			fallbackHref: safeFallbackHref,
		};
	}

	const hasStaleSource = sources.some((source) => source.state === 'stale');
	const state: ProofProvenanceState =
		invalidSourceCount > 0 ? 'warning' : hasStaleSource ? 'stale' : 'fresh';
	let stateDetail =
		state === 'fresh'
			? 'All listed sources are within their freshness windows.'
			: 'One or more listed sources are stale. Treat this artifact as historical context until refreshed.';

	if (state === 'warning') {
		stateDetail =
			'Some provenance entries are unavailable or invalid. Review listed sources and fallback guidance before trusting this artifact.';
	}

	return {
		state,
		stateLabel: resolveProofProvenanceStateLabel(state),
		stateDetail,
		sources,
		fallbackHref: safeFallbackHref,
	};
}

export function resolveApprovedTrustClaimForRender(
	claim: ApprovedTrustClaim,
	fallbackHref: string,
	now = new Date(),
): ApprovedTrustClaimForRender {
	return {
		...claim,
		provenance: resolveProofProvenanceForRender(claim.supportLinks, fallbackHref, now),
	};
}

export function resolveProofSnapshotForRender(
	snapshot: ProofSnapshot,
	fallbackHref: string,
	now = new Date(),
): ProofSnapshotForRender {
	return {
		...snapshot,
		provenance: resolveProofProvenanceForRender(snapshot.supportLinks, fallbackHref, now),
	};
}

export type ProofProvenanceCoverageCheck = {
	artifactId: string;
	state: ProofProvenanceState;
	hasInspectableSources: boolean;
	hasFallbackLink: boolean;
};

export function runProofProvenanceCoverageChecks(
	hero: HeroCopy,
	now = new Date(),
): ProofProvenanceCoverageCheck[] {
	const fallbackHref = hero.provenanceUnavailableDocsHref;
	const trustClaimChecks = hero.proofClaims.map((claim) => {
		const provenance = resolveProofProvenanceForRender(claim.supportLinks, fallbackHref, now);
		return {
			artifactId: claim.id,
			state: provenance.state,
			hasInspectableSources: provenance.sources.length > 0,
			hasFallbackLink: hasNonEmptyText(provenance.fallbackHref),
		};
	});

	const snapshotChecks = hero.proofSnapshots.map((snapshot) => {
		const provenance = resolveProofProvenanceForRender(snapshot.supportLinks, fallbackHref, now);
		return {
			artifactId: snapshot.id,
			state: provenance.state,
			hasInspectableSources: provenance.sources.length > 0,
			hasFallbackLink: hasNonEmptyText(provenance.fallbackHref),
		};
	});

	return [...trustClaimChecks, ...snapshotChecks];
}

function isApprovedTrustClaimId(value: unknown): value is ApprovedTrustClaimId {
	if (typeof value !== 'string') {
		return false;
	}

	return Object.hasOwn(approvedTrustClaimCatalog, value);
}

function isProofSnapshotId(value: unknown): value is ProofSnapshotId {
	return value === 'manual-baseline' || value === 'xcforge-proof';
}

function hasExactApprovedTrustClaims(claims: ApprovedTrustClaim[] | undefined): boolean {
	if (!claims || claims.length !== Object.keys(approvedTrustClaimCatalog).length) {
		return false;
	}

	const seenClaimIds = new Set<ApprovedTrustClaimId>();

	for (const claim of claims) {
		if (!claim || typeof claim !== 'object' || !isApprovedTrustClaimId(claim.id)) {
			return false;
		}

		if (seenClaimIds.has(claim.id)) {
			return false;
		}

		seenClaimIds.add(claim.id);

		if (claim.policyClass !== 'allowed-now') {
			return false;
		}

		if (claim.text !== approvedTrustClaimCatalog[claim.id]) {
			return false;
		}
	}

	return seenClaimIds.size === Object.keys(approvedTrustClaimCatalog).length;
}

function hasValidHeroProofSnapshots(hero: HeroCopy): boolean {
	if (!hero.proofSnapshots || hero.proofSnapshots.length !== 2) {
		return false;
	}

	const seenSnapshotIds = new Set<ProofSnapshotId>();

	for (const snapshot of hero.proofSnapshots) {
		if (!snapshot || typeof snapshot !== 'object' || !isProofSnapshotId(snapshot.id)) {
			return false;
		}

		if (seenSnapshotIds.has(snapshot.id)) {
			return false;
		}

		seenSnapshotIds.add(snapshot.id);

		if (
			!hasNonEmptyText(snapshot.label) ||
			!hasNonEmptyText(snapshot.summary) ||
			!hasNonEmptyText(snapshot.announcement)
		) {
			return false;
		}
	}

	if (!seenSnapshotIds.has('manual-baseline') || !seenSnapshotIds.has('xcforge-proof')) {
		return false;
	}

	return (
		isProofSnapshotId(hero.defaultProofSnapshotId) &&
		seenSnapshotIds.has(hero.defaultProofSnapshotId)
	);
}

function validateApprovedTrustClaims(
	claims: ApprovedTrustClaim[] | undefined,
	locationLabel: string,
	messages: string[],
): void {
	if (!claims || claims.length === 0) {
		messages.push(
			`${locationLabel} is missing approved trust claims. Mark this proof surface non-publishable. ${claimPolicyRemediation}`,
		);
		return;
	}

	const seenClaimIds = new Set<ApprovedTrustClaimId>();
	const duplicateClaimIds = new Set<ApprovedTrustClaimId>();

	claims.forEach((rawClaim, index) => {
		if (!rawClaim || typeof rawClaim !== 'object') {
			messages.push(
				`${locationLabel} has malformed trust-claim data at index ${index}. Mark this proof surface non-publishable. ${claimPolicyRemediation}`,
			);
			return;
		}

		const claim = rawClaim as Partial<ApprovedTrustClaim>;
		if (!isApprovedTrustClaimId(claim.id)) {
			messages.push(
				`${locationLabel} contains unsupported trust claim id "${String(claim.id)}". Only approved trust claims are publishable. Mark this proof surface non-publishable. ${claimPolicyRemediation}`,
			);
			return;
		}

		if (seenClaimIds.has(claim.id)) {
			duplicateClaimIds.add(claim.id);
		} else {
			seenClaimIds.add(claim.id);
		}

		if (claim.policyClass !== 'allowed-now') {
			messages.push(
				`${locationLabel} claim "${claim.id}" is classed as "${String(claim.policyClass)}". Only "allowed-now" trust claims are publishable in Story 3.2 proof surfaces. Mark this proof surface non-publishable. ${claimPolicyRemediation}`,
			);
		}

		const expectedText = approvedTrustClaimCatalog[claim.id];
		if (!hasNonEmptyText(claim.text) || claim.text !== expectedText) {
			messages.push(
				`${locationLabel} claim "${claim.id}" must render exactly "${expectedText}". Mark this proof surface non-publishable. ${claimPolicyRemediation}`,
			);
		}
	});

	if (duplicateClaimIds.size > 0) {
		messages.push(
			`${locationLabel} has duplicate approved trust claims: ${[...duplicateClaimIds].join(', ')}. Mark this proof surface non-publishable. ${claimPolicyRemediation}`,
		);
	}

	const missingClaimIds = (Object.keys(approvedTrustClaimCatalog) as ApprovedTrustClaimId[]).filter(
		(claimId) => !seenClaimIds.has(claimId),
	);

	if (
		missingClaimIds.length > 0 ||
		claims.length !== Object.keys(approvedTrustClaimCatalog).length
	) {
		messages.push(
			`${locationLabel} must include exactly these approved trust claims: ${Object.values(approvedTrustClaimCatalog).join(', ')}. Missing ids: ${missingClaimIds.length > 0 ? missingClaimIds.join(', ') : 'none'}. Mark this proof surface non-publishable. ${claimPolicyRemediation}`,
		);
	}
}

function validateHeroProofSnapshots(hero: HeroCopy, messages: string[]): void {
	if (!hero.proofSnapshots || hero.proofSnapshots.length === 0) {
		messages.push(
			`Section "hero" is missing proof snapshots. Mark this proof surface non-publishable. ${claimPolicyRemediation}`,
		);
		return;
	}

	const seenSnapshotIds = new Set<ProofSnapshotId>();
	const duplicateSnapshotIds = new Set<ProofSnapshotId>();

	hero.proofSnapshots.forEach((snapshot, index) => {
		if (!snapshot || typeof snapshot !== 'object') {
			messages.push(
				`Section "hero" has malformed proof snapshot data at index ${index}. Mark this proof surface non-publishable. ${claimPolicyRemediation}`,
			);
			return;
		}

		if (!isProofSnapshotId(snapshot.id)) {
			messages.push(
				`Section "hero" has unsupported proof snapshot id "${String(snapshot.id)}". Expected "manual-baseline" or "xcforge-proof". Mark this proof surface non-publishable. ${claimPolicyRemediation}`,
			);
			return;
		}

		if (seenSnapshotIds.has(snapshot.id)) {
			duplicateSnapshotIds.add(snapshot.id);
		} else {
			seenSnapshotIds.add(snapshot.id);
		}

		if (
			!hasNonEmptyText(snapshot.label) ||
			!hasNonEmptyText(snapshot.summary) ||
			!hasNonEmptyText(snapshot.announcement)
		) {
			messages.push(
				`Section "hero" proof snapshot "${snapshot.id}" is missing label, summary, or announcement text. Mark this proof surface non-publishable. ${claimPolicyRemediation}`,
			);
		}
	});

	if (!seenSnapshotIds.has('manual-baseline') || !seenSnapshotIds.has('xcforge-proof')) {
		messages.push(
			`Section "hero" must include both proof snapshots (manual-baseline and xcforge-proof). Mark this proof surface non-publishable. ${claimPolicyRemediation}`,
		);
	}

	if (duplicateSnapshotIds.size > 0) {
		messages.push(
			`Section "hero" has duplicate proof snapshots: ${[...duplicateSnapshotIds].join(', ')}. Mark this proof surface non-publishable. ${claimPolicyRemediation}`,
		);
	}

	if (hero.proofSnapshots.length !== 2) {
		messages.push(
			`Section "hero" must contain exactly two proof snapshots (manual-baseline and xcforge-proof). Mark this proof surface non-publishable. ${claimPolicyRemediation}`,
		);
	}

	if (!isProofSnapshotId(hero.defaultProofSnapshotId)) {
		messages.push(
			`Section "hero" has unsupported default proof snapshot id "${String(hero.defaultProofSnapshotId)}". Mark this proof surface non-publishable. ${claimPolicyRemediation}`,
		);
	} else if (!seenSnapshotIds.has(hero.defaultProofSnapshotId)) {
		messages.push(
			`Section "hero" default proof snapshot "${hero.defaultProofSnapshotId}" is not present in proofSnapshots. Mark this proof surface non-publishable. ${claimPolicyRemediation}`,
		);
	}
}

const claimSupportRemediation =
	'Remediation: refresh or replace supporting links and record the correction in release notes before publishing.';

const claimPolicyRemediation =
	'Remediation: classify each claim with an approved policy class and restore compliant source metadata before publishing.';

const benchmarkClaimRemediation =
	'Remediation: attach benchmark evidence metadata for benchmark-gated claims or reclassify the claim until benchmark evidence is available.';

const requiredSolutionSurfaces: readonly [string, RegExp][] = [
	['build', /\bbuild\b/i],
	['test', /\btest\b/i],
	['simulator control', /simulator/i],
	['logs', /\blogs\b/i],
	['screenshots', /screenshots?/i],
	['UI inspection', /ui inspection/i],
	['LLDB', /\blldb\b/i],
	['verification', /verif/i],
];

const requiredWorkflowScenarioIds: readonly NarrativeJourneyId[] = [
	'failing-build-or-test-to-verified-fix',
	'simulator-recovery-and-stabilization',
	'lldb-assisted-diagnosis',
	'evidence-backed-verification',
];

const journeyOutcomeCuePattern = /verified|recover|isolat|confirm|prove|unblock|reproduc|determin/i;

const requiredDifferentiationSignals: readonly [string, RegExp][] = [
	['local-first execution depth', /local[-\s]?first|local\s+(build|simulator|debugger|execution)/i],
	['trust model', /trust|proof|evidence|inspectable/i],
	['workflow depth', /workflow|end-to-end|build|test|diagnos|verif/i],
];

const disallowedDifferentiationHypePatterns: readonly [string, RegExp][] = [
	['best-in-class', /best[-\s]?in[-\s]?class/i],
	['fastest', /\bfastest\b/i],
	['world-class', /world[-\s]?class/i],
	['unmatched', /\bunmatched\b/i],
	['revolutionary', /\brevolutionary\b/i],
	['guaranteed', /\bguaranteed\b/i],
];

const workflowsRemediation =
	'Remediation: restore required scenario coverage and artifact state metadata before publishing.';

const differentiationRemediation =
	'Remediation: anchor differentiation to local-first trust evidence and remove unsupported hype language before publishing.';

function isNarrativeJourneyId(value: unknown): value is NarrativeJourneyId {
	if (typeof value !== 'string') {
		return false;
	}

	return requiredWorkflowScenarioIds.includes(value as NarrativeJourneyId);
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

function validateNarrativeSectionPayload(
	section: HomepageNarrativeBodySection,
	messages: string[],
	now: Date,
): void {
	switch (section.id) {
		case 'problem': {
			if (section.painSignals.length === 0) {
				messages.push(
					'Section "problem" must include at least one pain signal in website/src/data/homepage.ts.',
				);
			}

			section.painSignals.forEach((signal, index) => {
				if (!signal || typeof signal !== 'object') {
					messages.push(
						`Section "problem" has malformed claim data at index ${index}. Mark this claim non-publishable. ${claimSupportRemediation}`,
					);
					return;
				}

				const claim = signal as Partial<NarrativeClaim>;
				const claimId = hasNonEmptyText(claim.id) ? claim.id : `problem-${index}`;
				if (!hasNonEmptyText(claim.id) || !hasNonEmptyText(claim.text)) {
					messages.push(
						`Section "problem" claim at index ${index} has empty id or text. Mark this claim non-publishable. ${claimSupportRemediation}`,
					);
				}

				validateNarrativeClaimPolicy({
					sectionId: 'problem',
					claimId,
					policyClass: claim.policyClass,
					supportLinks: claim.supportLinks,
					benchmarkEvidence: claim.benchmarkEvidence,
					messages,
					now,
					claimSupportRemediation,
					claimPolicyRemediation,
					benchmarkRemediation: benchmarkClaimRemediation,
				});
			});
			break;
		}
		case 'solution': {
			if (section.capabilities.length === 0) {
				messages.push(
					'Section "solution" must include at least one capability in website/src/data/homepage.ts.',
				);
			}

			section.capabilities.forEach((capability, index) => {
				if (!capability || typeof capability !== 'object') {
					messages.push(
						`Section "solution" has malformed claim data at index ${index}. Mark this claim non-publishable. ${claimSupportRemediation}`,
					);
					return;
				}

				const claim = capability as Partial<NarrativeClaim>;
				const claimId = hasNonEmptyText(claim.id) ? claim.id : `solution-${index}`;
				if (!hasNonEmptyText(claim.id) || !hasNonEmptyText(claim.text)) {
					messages.push(
						`Section "solution" claim at index ${index} has empty id or text. Mark this claim non-publishable. ${claimSupportRemediation}`,
					);
				}

				validateNarrativeClaimPolicy({
					sectionId: 'solution',
					claimId,
					policyClass: claim.policyClass,
					supportLinks: claim.supportLinks,
					benchmarkEvidence: claim.benchmarkEvidence,
					messages,
					now,
					claimSupportRemediation,
					claimPolicyRemediation,
					benchmarkRemediation: benchmarkClaimRemediation,
				});
			});

			const combinedCapabilityText = section.capabilities
				.map((capability) => (hasNonEmptyText(capability.text) ? capability.text : ''))
				.join(' ');
			const missingRequiredSurfaces = requiredSolutionSurfaces
				.filter(([, pattern]) => !pattern.test(combinedCapabilityText))
				.map(([surface]) => surface);

			if (missingRequiredSurfaces.length > 0) {
				messages.push(
					`Section "solution" is missing required capability surfaces: ${missingRequiredSurfaces.join(', ')}. Mark this claim set non-publishable. ${claimSupportRemediation}`,
				);
			}
			break;
		}
		case 'workflows': {
			if (section.journeys.length === 0) {
				messages.push(
					`Section "workflows" must include at least one journey in website/src/data/homepage.ts. Mark this section non-publishable. ${workflowsRemediation}`,
				);
			}

			const seenScenarioIds = new Set<NarrativeJourneyId>();
			const duplicateScenarioIds = new Set<NarrativeJourneyId>();

			section.journeys.forEach((journey, index) => {
				if (!journey || typeof journey !== 'object') {
					messages.push(
						`Section "workflows" has malformed journey data at index ${index}. Mark this section non-publishable. ${workflowsRemediation}`,
					);
					return;
				}

				if (!hasNonEmptyText(journey.id) || !isNarrativeJourneyId(journey.id)) {
					messages.push(
						`Section "workflows" has an invalid scenario id at index ${index}. Expected one of: ${requiredWorkflowScenarioIds.join(', ')}. Mark this section non-publishable. ${workflowsRemediation}`,
					);
				} else if (seenScenarioIds.has(journey.id)) {
					duplicateScenarioIds.add(journey.id);
				} else {
					seenScenarioIds.add(journey.id);
				}

				if (
					!hasNonEmptyText(journey.title) ||
					!hasNonEmptyText(journey.detail) ||
					!hasNonEmptyText(journey.outcome)
				) {
					messages.push(
						`Section "workflows" has an invalid journey at index ${index}. Scenario id, title, detail, and outcome must be non-empty. Mark this section non-publishable. ${workflowsRemediation}`,
					);
				} else if (!journeyOutcomeCuePattern.test(journey.outcome)) {
					messages.push(
						`Section "workflows" scenario "${journey.id}" is not outcome-oriented enough. Include concrete result language (for example verified, recovered, isolated, confirmed). Mark this section non-publishable. ${workflowsRemediation}`,
					);
				}

				const artifact = journey.artifact;

				if (artifact.status === 'available') {
					if (
						!hasNonEmptyText(artifact.label) ||
						!hasNonEmptyText(artifact.href) ||
						!hasNonEmptyText(artifact.summary)
					) {
						messages.push(
							`Section "workflows" scenario "${journey.id}" has incomplete available artifact metadata. Mark this section non-publishable. ${workflowsRemediation}`,
						);
					} else if (!isClaimSupportHrefValid(artifact.href)) {
						messages.push(
							`Section "workflows" scenario "${journey.id}" has invalid artifact href "${artifact.href}". Mark this section non-publishable. ${workflowsRemediation}`,
						);
					}
				} else {
					if (!hasNonEmptyText(artifact.unavailableMessage)) {
						messages.push(
							`Section "workflows" scenario "${journey.id}" is unavailable but missing explicit fallback text. Mark this section non-publishable. ${workflowsRemediation}`,
						);
					}
				}
			});

			if (duplicateScenarioIds.size > 0) {
				messages.push(
					`Section "workflows" has duplicate required scenarios: ${[...duplicateScenarioIds].join(', ')}. Mark this section non-publishable. ${workflowsRemediation}`,
				);
			}

			const missingScenarioIds = requiredWorkflowScenarioIds.filter(
				(scenarioId) => !seenScenarioIds.has(scenarioId),
			);

			if (missingScenarioIds.length > 0) {
				messages.push(
					`Section "workflows" is missing required scenarios: ${missingScenarioIds.join(', ')}. Mark this section non-publishable. ${workflowsRemediation}`,
				);
			}
			break;
		}
		case 'differentiation': {
			if (section.points.length === 0) {
				messages.push(
					'Section "differentiation" must include at least one point in website/src/data/homepage.ts.',
				);
			}

			if (!isClaimSupportHrefValid(section.provenanceUnavailableDocsHref)) {
				messages.push(
					`Section "differentiation" has invalid provenance fallback href "${section.provenanceUnavailableDocsHref}". Provide a valid docs or evidence destination for warning-state trust markers.`,
				);
			}

			validateApprovedTrustClaims(
				section.proofClaims,
				'Section "differentiation" proof claims',
				messages,
			);

			for (const claim of section.proofClaims) {
				const provenance = resolveProofProvenanceForRender(
					claim.supportLinks,
					section.provenanceUnavailableDocsHref,
					now,
				);

				if (provenance.state !== 'warning' && provenance.sources.length === 0) {
					messages.push(
						`Section "differentiation" claim "${claim.id}" has no inspectable provenance sources despite state "${provenance.state}". Ensure source metadata is visible when artifact state is not warning.`,
					);
				}
			}

			if (!hasNonEmptyText(section.proofOutcomeSummary)) {
				messages.push(
					`Section "differentiation" is missing proofOutcomeSummary text. Mark this section non-publishable. ${differentiationRemediation}`,
				);
			}

			section.points.forEach((point, index) => {
				if (!hasNonEmptyText(point.title) || !hasNonEmptyText(point.detail)) {
					messages.push(
						`Section "differentiation" has an invalid point at index ${index}. Both title and detail must be non-empty. Mark this section non-publishable. ${differentiationRemediation}`,
					);
				}
			});

			const differentiationText = [
				section.heading,
				section.purpose,
				...section.points.map((point) => `${point.title} ${point.detail}`),
			].join(' ');

			const missingDifferentiationSignals = requiredDifferentiationSignals
				.filter(([, pattern]) => !pattern.test(differentiationText))
				.map(([signal]) => signal);

			if (missingDifferentiationSignals.length > 0) {
				messages.push(
					`Section "differentiation" is missing required framing: ${missingDifferentiationSignals.join(', ')}. Mark this section non-publishable. ${differentiationRemediation}`,
				);
			}

			const matchedHypeTerms = disallowedDifferentiationHypePatterns
				.filter(([, pattern]) => pattern.test(differentiationText))
				.map(([term]) => term);

			if (matchedHypeTerms.length > 0) {
				messages.push(
					`Section "differentiation" contains disallowed hype language (${matchedHypeTerms.join(', ')}). Mark this section non-publishable. ${differentiationRemediation}`,
				);
			}
			break;
		}
		case 'docs-handoff': {
			if (section.handoffLinks.length === 0) {
				messages.push(
					'Section "docs-handoff" must include at least one handoff link in website/src/data/homepage.ts.',
				);
			}

			section.handoffLinks.forEach((link, index) => {
				const hasCoreFields =
					hasNonEmptyText(link.label) &&
					hasNonEmptyText(link.href) &&
					hasNonEmptyText(link.summary);
				if (!hasCoreFields) {
					messages.push(
						`Section "docs-handoff" has an invalid handoff link at index ${index}. Label, href, and summary must be non-empty.`,
					);
					return;
				}

				if (!isClaimSupportHrefValid(link.href)) {
					messages.push(
						`Section "docs-handoff" link "${link.label}" has invalid href "${link.href}". Use an absolute internal route or valid http(s) URL.`,
					);
					return;
				}

				if (link.external) {
					return;
				}

				if (!link.href.startsWith('/docs')) {
					messages.push(
						`Section "docs-handoff" link "${link.label}" must target docs-owned routes under /docs for one-click depth handoff.`,
					);
				}

				if (!hasNonEmptyText(link.unavailableMessage)) {
					messages.push(
						`Section "docs-handoff" link "${link.label}" is missing unavailableMessage. Provide explicit destination-unavailable copy for fallback redirects.`,
					);
				}

				if (
					!hasNonEmptyText(link.fallbackHref) ||
					!isClaimSupportHrefValid(link.fallbackHref) ||
					!link.fallbackHref.startsWith('/docs')
				) {
					messages.push(
						`Section "docs-handoff" link "${link.label}" must define a valid docs fallbackHref under /docs.`,
					);
				}

				if (link.destinationId !== 'docs' && link.destinationId !== 'workflow-guide') {
					messages.push(
						`Section "docs-handoff" link "${link.label}" must define destinationId as "docs" or "workflow-guide" for orientation context.`,
					);
				}
			});
			break;
		}
	}
}

export function validateHomepageNarrativeSections(
	content: HomepageContent,
): HomepageNarrativeValidationResult {
	const sectionContract = createHomepageNarrativeSectionContract(content);
	const messages: string[] = [];
	const now = new Date();
	validateApprovedTrustClaims(content.hero.proofClaims, 'Section "hero" proof strip', messages);
	validateHeroProofSnapshots(content.hero, messages);

	if (!isClaimSupportHrefValid(content.hero.provenanceUnavailableDocsHref)) {
		messages.push(
			`Section "hero" has invalid provenance fallback href "${content.hero.provenanceUnavailableDocsHref}". Provide a valid docs or evidence destination for warning-state trust markers.`,
		);
	}

	const provenanceCoverageChecks = runProofProvenanceCoverageChecks(content.hero, now);
	for (const check of provenanceCoverageChecks) {
		if (!check.hasFallbackLink) {
			messages.push(
				`Proof artifact "${check.artifactId}" is missing a provenance fallback destination. Add an explicit docs fallback link for warning-state rendering.`,
			);
		}

		if (check.state !== 'warning' && !check.hasInspectableSources) {
			messages.push(
				`Proof artifact "${check.artifactId}" has no inspectable provenance sources despite state "${check.state}". Ensure source metadata is visible when artifact state is not warning.`,
			);
		}
	}

	const seenSectionIds = new Set<HomepageNarrativeSectionId>();
	const duplicateSectionIds = new Set<HomepageNarrativeSectionId>();

	for (const section of sectionContract) {
		if (seenSectionIds.has(section.id)) {
			duplicateSectionIds.add(section.id);
		}

		seenSectionIds.add(section.id);

		if (section.heading.trim().length === 0) {
			messages.push(
				`Section "${section.id}" is missing a heading. Add a non-empty heading in website/src/data/homepage.ts.`,
			);
		}

		if (section.purpose.trim().length === 0) {
			messages.push(
				`Section "${section.id}" is missing a purpose statement. Add a non-empty purpose in website/src/data/homepage.ts.`,
			);
		}
	}

	for (const section of content.narrativeSections) {
		validateNarrativeSectionPayload(section, messages, now);
	}

	if (duplicateSectionIds.size > 0) {
		messages.push(
			`Duplicate section ids found: ${[...duplicateSectionIds].join(', ')}. Keep each required section id unique.`,
		);
	}

	const missingSectionIds = requiredHomepageNarrativeSectionOrder.filter(
		(sectionId) => !seenSectionIds.has(sectionId),
	);

	if (missingSectionIds.length > 0) {
		messages.push(
			`Missing required sections: ${missingSectionIds.join(', ')}. Add each missing section and keep the canonical order.`,
		);
	}

	const firstOccurrenceOrder: HomepageNarrativeSectionId[] = [];
	for (const section of sectionContract) {
		if (!firstOccurrenceOrder.includes(section.id)) {
			firstOccurrenceOrder.push(section.id);
		}
	}

	for (const [index, expectedSectionId] of requiredHomepageNarrativeSectionOrder.entries()) {
		const actualSectionId = firstOccurrenceOrder[index];
		if (!actualSectionId) {
			break;
		}

		if (actualSectionId !== expectedSectionId) {
			messages.push(
				`Section order mismatch at position ${index + 1}: expected "${expectedSectionId}" but found "${actualSectionId}". Reorder sections to ${requiredHomepageNarrativeSectionOrder.join(' -> ')}.`,
			);
			break;
		}
	}

	return {
		isValid: messages.length === 0,
		messages,
		expectedOrder: requiredHomepageNarrativeSectionOrder,
		actualOrder: sectionContract.map((section) => section.id),
	};
}

export function formatHomepageNarrativeValidationReport(
	validation: HomepageNarrativeValidationResult,
): string {
	const expectedOrder = validation.expectedOrder.join(' -> ');
	const actualOrder =
		validation.actualOrder.length > 0 ? validation.actualOrder.join(' -> ') : '(none)';

	if (validation.isValid) {
		return [
			'[homepage narrative] Section contract validation passed.',
			`Expected order: ${expectedOrder}`,
			`Actual order: ${actualOrder}`,
		].join('\n');
	}

	const issueList = validation.messages
		.map((message, index) => `${index + 1}. ${message}`)
		.join('\n');
	const hasNonPublishableClaims = validation.messages.some((message) =>
		message.toLowerCase().includes('non-publishable'),
	);
	const releaseStatus = hasNonPublishableClaims
		? 'Publication status: BLOCKED. Non-publishable narrative claims detected.'
		: 'Publication status: BLOCKED. Validation errors must be resolved before publishing.';
	const releaseNotesGuidance =
		'Release-notes remediation required: document claim-support fixes before the next publish attempt.';

	return [
		'[homepage narrative] Section contract validation failed.',
		releaseStatus,
		issueList,
		`Expected order: ${expectedOrder}`,
		`Actual order: ${actualOrder}`,
		releaseNotesGuidance,
	].join('\n');
}

export function assertValidHomepageNarrativeSections(
	content: HomepageContent,
): HomepageNarrativeSectionContract[] {
	const validation = validateHomepageNarrativeSections(content);
	if (!validation.isValid) {
		throw new Error(formatHomepageNarrativeValidationReport(validation));
	}

	return createHomepageNarrativeSectionContract(content);
}

function requireNarrativeSection<TId extends HomepageNarrativeBodySection['id']>(
	sections: HomepageNarrativeBodySection[],
	sectionId: TId,
): Extract<HomepageNarrativeBodySection, { id: TId }> {
	const section = sections.find((candidate) => candidate.id === sectionId);
	if (!section) {
		throw new Error(
			`[homepage narrative] Missing required narrative data for section "${sectionId}" in website/src/data/homepage.ts.`,
		);
	}

	return section as Extract<HomepageNarrativeBodySection, { id: TId }>;
}

export function resolveHomepageNarrativeSectionsForRender(
	content: HomepageContent,
): HomepageNarrativeSectionsForRender {
	assertValidHomepageNarrativeSections(content);

	return {
		problem: requireNarrativeSection(content.narrativeSections, 'problem'),
		solution: requireNarrativeSection(content.narrativeSections, 'solution'),
		workflows: requireNarrativeSection(content.narrativeSections, 'workflows'),
		differentiation: requireNarrativeSection(content.narrativeSections, 'differentiation'),
		docsHandoff: requireNarrativeSection(content.narrativeSections, 'docs-handoff'),
	};
}
