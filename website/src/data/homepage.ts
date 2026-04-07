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
	proofSummary: string;
	fallbackProofText: string;
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
	painSignals: string[];
};

export type SolutionSectionCopy = HomepageNarrativeSectionBase & {
	id: 'solution';
	capabilities: string[];
};

export type NarrativeJourney = {
	title: string;
	detail: string;
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
};

export type DocsHandoffLink = {
	label: string;
	href: string;
	summary: string;
	external?: boolean;
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
		proofSummary:
			'103 MCP tools, 17 CLI command groups, native Swift binary, and no external runtime dependencies.',
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
				'Build or test suggestions pass in-chat, then fail against real local Xcode and simulator state.',
				'Logs, screenshots, LLDB output, and UI state live in disconnected tools with no single execution thread.',
				'Each rescue loop becomes manual context switching that is slow to verify and hard to hand off.',
			],
		},
		{
			id: 'solution',
			heading: 'xcforge is a unified local execution layer for the iOS loop.',
			purpose:
				'Instead of stitching Apple tools and agent prompts manually, run the full local workflow through one contract that keeps outcomes verifiable.',
			capabilities: [
				'Run build, test, simulator control, and diagnostics from one command surface.',
				'Capture logs, screenshots, and UI inspection artifacts as reusable evidence.',
				'Move from failing run to verified fix with deterministic local execution steps.',
			],
		},
		{
			id: 'workflows',
			heading: 'Workflow journeys map directly to real failure-to-proof scenarios.',
			purpose:
				'Each journey is outcome-first so evaluators can quickly judge if xcforge fits their current rescue loops.',
			journeys: [
				{
					title: 'Failing build or test to verified fix',
					detail:
						'Start from a broken run, execute diagnosis steps, apply fixes, and verify with reproducible output.',
				},
				{
					title: 'Simulator recovery and stabilization',
					detail:
						'Recover unstable simulator state quickly so agent workflows stay unblocked and repeatable.',
				},
				{
					title: 'LLDB-assisted diagnosis',
					detail:
						'Use structured LLDB flows to inspect runtime behavior and isolate root causes without guesswork.',
				},
				{
					title: 'Evidence-backed verification',
					detail:
						'Capture screenshots and logs to prove what changed and confirm the fix with concrete artifacts.',
				},
			],
		},
		{
			id: 'differentiation',
			heading: 'Differentiation comes from local-first depth and trust discipline.',
			purpose:
				'xcforge is built for technical evaluators who need credible execution evidence, not generic automation claims.',
			points: [
				{
					title: 'Local-first by default',
					detail:
						'Execution happens where iOS outcomes are decided: your local build, simulator, and debugger loop.',
				},
				{
					title: 'Proof-oriented output',
					detail:
						'Trust markers and workflow evidence stay close to conversion surfaces so credibility is inspectable.',
				},
				{
					title: 'End-to-end workflow coverage',
					detail:
						'Build, test, simulator control, diagnostics, and verification stay in one coherent execution contract.',
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
					href: '/docs',
					summary: 'Inspect command groups, capabilities, and reference material.',
				},
				{
					label: 'Open Workflow Guide',
					href: '/docs/getting-started/',
					summary: 'Follow install-first paths from failing run to verified outcome.',
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
		hero.proofSummary.trim().length > 0
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

function hasNonEmptyText(value: string): boolean {
	return value.trim().length > 0;
}

function validateNarrativeSectionPayload(
	section: HomepageNarrativeBodySection,
	messages: string[],
): void {
	switch (section.id) {
		case 'problem': {
			if (section.painSignals.length === 0) {
				messages.push(
					'Section "problem" must include at least one pain signal in website/src/data/homepage.ts.',
				);
			}

			section.painSignals.forEach((signal, index) => {
				if (!hasNonEmptyText(signal)) {
					messages.push(
						`Section "problem" has an empty pain signal at index ${index}. Provide non-empty text.`,
					);
				}
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
				if (!hasNonEmptyText(capability)) {
					messages.push(
						`Section "solution" has an empty capability at index ${index}. Provide non-empty text.`,
					);
				}
			});
			break;
		}
		case 'workflows': {
			if (section.journeys.length === 0) {
				messages.push(
					'Section "workflows" must include at least one journey in website/src/data/homepage.ts.',
				);
			}

			section.journeys.forEach((journey, index) => {
				if (!hasNonEmptyText(journey.title) || !hasNonEmptyText(journey.detail)) {
					messages.push(
						`Section "workflows" has an invalid journey at index ${index}. Both title and detail must be non-empty.`,
					);
				}
			});
			break;
		}
		case 'differentiation': {
			if (section.points.length === 0) {
				messages.push(
					'Section "differentiation" must include at least one point in website/src/data/homepage.ts.',
				);
			}

			section.points.forEach((point, index) => {
				if (!hasNonEmptyText(point.title) || !hasNonEmptyText(point.detail)) {
					messages.push(
						`Section "differentiation" has an invalid point at index ${index}. Both title and detail must be non-empty.`,
					);
				}
			});
			break;
		}
		case 'docs-handoff': {
			if (section.handoffLinks.length === 0) {
				messages.push(
					'Section "docs-handoff" must include at least one handoff link in website/src/data/homepage.ts.',
				);
			}

			section.handoffLinks.forEach((link, index) => {
				if (
					!hasNonEmptyText(link.label) ||
					!hasNonEmptyText(link.href) ||
					!hasNonEmptyText(link.summary)
				) {
					messages.push(
						`Section "docs-handoff" has an invalid handoff link at index ${index}. Label, href, and summary must be non-empty.`,
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
		validateNarrativeSectionPayload(section, messages);
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

	return [
		'[homepage narrative] Section contract validation failed.',
		issueList,
		`Expected order: ${expectedOrder}`,
		`Actual order: ${actualOrder}`,
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
