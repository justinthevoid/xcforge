// @ts-check
import cloudflare from '@astrojs/cloudflare';
import starlight from '@astrojs/starlight';
import svelte from '@astrojs/svelte';
import { defineConfig } from 'astro/config';

// https://astro.build/config
export default defineConfig({
	output: 'server',
	adapter: cloudflare(),
	integrations: [
		starlight({
			title: 'xcforge Docs',
			description: 'Technical documentation and workflow guidance for xcforge.',
			social: [
				{
					icon: 'github',
					label: 'GitHub',
					href: 'https://github.com/justinthevoid/xcforge',
				},
			],
			sidebar: [
				{
					label: 'Overview',
					items: [
						{ label: 'Overview', slug: 'docs' },
						{ label: 'Getting Started', slug: 'docs/getting-started' },
						{ label: 'Proof Provenance', slug: 'docs/proof-provenance' },
					],
				},
				{
					label: 'CLI Guides',
					items: [
						{ label: 'CLI Command Groups', slug: 'docs/guides/cli-command-groups' },
						{ label: 'Workflow Patterns', slug: 'docs/guides/workflow-patterns' },
					],
				},
				{
					label: 'MCP Reference',
					items: [
						{ label: 'MCP Server Overview', slug: 'docs/reference/mcp-server-overview' },
						{
							label: 'MCP Client Configuration',
							slug: 'docs/reference/mcp-client-configuration',
						},
						{ label: 'CLI and MCP Parity', slug: 'docs/reference/cli-mcp-parity' },
					],
				},
			],
		}),
		svelte(),
	],
});
