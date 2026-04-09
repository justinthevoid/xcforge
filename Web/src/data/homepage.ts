export type NavItemId = 'features' | 'docs' | 'workflow-guide' | 'changelog' | 'github' | 'install';

export type NavItem = {
	id: NavItemId;
	label: string;
	href: string;
	external?: boolean;
};

export type HeroCopy = {
	headline: string;
	subtitle: string;
	tapCommand: string;
	installCommand: string;
	fullInstallCommand: string;
	installHref: string;
	installExternal?: boolean;
};

export type Feature = {
	id: string;
	marker: string;
	title: string;
	description: string;
};

export type TerminalDemoStep = {
	prompt?: boolean;
	command?: string;
	output?: string;
	style?: 'error' | 'success' | 'muted' | 'info';
};

export type TerminalDemoCopy = {
	heading: string;
	subtitle: string;
	steps: TerminalDemoStep[];
};

export type FinalCtaCopy = {
	heading: string;
	summary: string;
	installLabel: string;
	installCommand: string;
	installHref: string;
	installExternal?: boolean;
	docsLabel: string;
	docsHref: string;
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
	terminalDemo: TerminalDemoCopy;
	features: Feature[];
	finalCta: FinalCtaCopy;
};

const requiredNavOrder: NavItemId[] = [
	'features',
	'docs',
	'workflow-guide',
	'changelog',
	'github',
	'install',
];

const tapCommand = 'brew tap justinthevoid/tap';
const installCommand = 'brew install xcforge';
const fullInstallCommand = `${tapCommand} && ${installCommand}`;
const installGuideHref = 'https://github.com/justinthevoid/xcforge#install';

export const homepageContent: HomepageContent = {
	navigation: [
		{ id: 'features', label: 'Features', href: '#features' },
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
	],
	hero: {
		headline: 'Your AI agent can write the fix.\nNow let it prove the fix works.',
		subtitle:
			'xcforge gives AI agents direct control of Xcode builds, tests, simulators, and debuggers — so they can verify their own work without waiting on you.',
		tapCommand,
		installCommand,
		fullInstallCommand,
		installHref: installGuideHref,
		installExternal: true,
	},
	terminalDemo: {
		heading: 'See it work',
		subtitle: 'From failing build to verified fix — without leaving the agent loop.',
		steps: [
			{ prompt: true, command: 'xcforge build --project MyApp.xcodeproj --scheme MyApp' },
			{ output: 'Build failed — 2 errors in ContentView.swift', style: 'error' },
			{ prompt: true, command: 'xcforge diagnose --last-build' },
			{
				output:
					'ContentView.swift:42 — Cannot convert \'String\' to \'Int\'\nContentView.swift:87 — Missing return in closure',
				style: 'muted',
			},
			{ output: '→ Agent applies fix...', style: 'info' },
			{ prompt: true, command: 'xcforge build --project MyApp.xcodeproj --scheme MyApp' },
			{ output: 'Build succeeded', style: 'success' },
			{ prompt: true, command: 'xcforge test --scheme MyApp' },
			{ output: 'Test suite passed — 47 tests, 0 failures', style: 'success' },
		],
	},
	features: [
		{
			id: 'mcp-tools',
			marker: '103',
			title: 'MCP Tools',
			description: 'Full Model Context Protocol surface — agents call xcforge directly.',
		},
		{
			id: 'cli-commands',
			marker: '17',
			title: 'CLI Command Groups',
			description: 'Build, test, run, sim, debug, log, screenshot, accessibility, and more.',
		},
		{
			id: 'build-test',
			marker: 'xc',
			title: 'Build & Test',
			description: 'Compile, run tests, and capture structured diagnostics in one pass.',
		},
		{
			id: 'simulator',
			marker: 'sim',
			title: 'Simulator Control',
			description: 'Boot, manage, screenshot, and recover simulators programmatically.',
		},
		{
			id: 'debugger',
			marker: 'lldb',
			title: 'LLDB Debugging',
			description: 'Attach, set breakpoints, evaluate expressions — from the command line.',
		},
		{
			id: 'evidence',
			marker: 'log',
			title: 'Evidence Capture',
			description: 'Screenshots, logs, and UI inspection output as verifiable artifacts.',
		},
	],
	finalCta: {
		heading: 'Ready to close the loop?',
		summary: 'Install xcforge and let your agent verify its own work.',
		installLabel: 'Install via Homebrew',
		installCommand: fullInstallCommand,
		installHref: installGuideHref,
		installExternal: true,
		docsLabel: 'Read the Docs',
		docsHref: '/docs',
		handoffTitle: 'Install intent saved',
		handoffReadyMessage:
			'Install intent captured for later. Copy the command or open the install guide.',
		handoffFailureMessage:
			'Could not save install intent on this device. Copy the command to continue.',
		handoffRestoredMessage:
			'Saved install intent restored. Run the command below when ready.',
		handoffCopyButtonLabel: 'Copy command',
		handoffGuideLabel: 'Open install guide',
	},
};

export type NavigationMetadata = {
	isMetadataAvailable: boolean;
	items: NavItem[];
};

export function resolveNavigationMetadata(items: NavItem[]): NavigationMetadata {
	if (!Array.isArray(items) || items.length === 0) {
		return {
			isMetadataAvailable: false,
			items: homepageContent.navigation,
		};
	}

	const actualOrder = items.map((item) => item.id);
	const orderMatches =
		actualOrder.length === requiredNavOrder.length &&
		actualOrder.every((id, index) => id === requiredNavOrder[index]);

	if (!orderMatches) {
		return {
			isMetadataAvailable: false,
			items: homepageContent.navigation,
		};
	}

	return { isMetadataAvailable: true, items };
}
