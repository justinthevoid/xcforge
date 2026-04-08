const pageTitle = 'xcforge | Install-first iOS agent execution';
const pageDescription =
	'xcforge helps AI-assisted iOS developers move from generated code to verified local outcomes with one clear install path.';

export const homepageSeo = {
	title: pageTitle,
	description: pageDescription,
	canonicalPath: '/',
	socialImagePath: '/og-image.png',
	organizationLogoPath: '/favicon.svg',
};

export function createHomepageStructuredData(siteUrl: string) {
	const organizationLogoUrl = new URL(homepageSeo.organizationLogoPath, siteUrl).toString();

	return {
		'@context': 'https://schema.org',
		'@graph': [
			{
				'@type': 'Organization',
				name: 'xcforge',
				url: siteUrl,
				logo: organizationLogoUrl,
				sameAs: ['https://github.com/justinthevoid/xcforge'],
			},
			{
				'@type': 'WebSite',
				name: 'xcforge',
				url: siteUrl,
				description: pageDescription,
				inLanguage: 'en-US',
			},
		],
	};
}
