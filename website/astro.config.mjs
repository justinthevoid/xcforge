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
					label: 'Docs',
					items: [
						{ label: 'Overview', slug: 'docs' },
						{ label: 'Getting Started', slug: 'docs/getting-started' },
					],
				},
			],
		}),
		svelte(),
	],
});
