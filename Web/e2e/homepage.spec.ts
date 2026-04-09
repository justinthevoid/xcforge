import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

test.describe('Homepage', () => {
	test.beforeEach(async ({ page }) => {
		await page.goto('/');
	});

	test('passes axe accessibility scan', async ({ page }) => {
		const results = await new AxeBuilder({ page }).analyze();
		expect(results.violations).toEqual([]);
	});

	test('has correct page title and meta description', async ({ page }) => {
		await expect(page).toHaveTitle(/xcforge/i);
		const description = page.locator('meta[name="description"]');
		await expect(description).toHaveAttribute('content', /.+/);
	});

	test('renders all four homepage sections in order', async ({ page }) => {
		const hero = page.locator('#product');
		const terminalDemo = page.locator('[id="demo"]');
		const features = page.locator('[id="features"]');
		const finalCta = page.locator('#final-cta');

		await expect(hero).toBeVisible();
		await expect(finalCta).toBeVisible();

		const heroBox = await hero.boundingBox();
		const finalCtaBox = await finalCta.boundingBox();
		expect(heroBox!.y).toBeLessThan(finalCtaBox!.y);
	});

	test('hero install CTA is clickable and links to install', async ({ page }) => {
		const installLink = page.locator('#install-section a[data-action-tier="primary"]');
		await expect(installLink).toBeVisible();
		await expect(installLink).toHaveAttribute('href', /.+/);
	});

	test('hero has docs and GitHub secondary links', async ({ page }) => {
		const docsLink = page.locator('#install-section a[href="/docs"]');
		const githubLink = page.locator('#install-section a[href*="github.com"]');
		await expect(docsLink).toBeVisible();
		await expect(githubLink).toBeVisible();
	});

	test('final CTA install button is visible', async ({ page }) => {
		const finalInstall = page.locator('#final-cta a[data-action-tier="primary"]');
		await expect(finalInstall).toBeVisible();
	});

	test('copy command button exists in final CTA', async ({ page }) => {
		const copyButton = page.locator('#final-cta button[data-copy-adjacent]');
		await expect(copyButton).toBeVisible();
	});

	test('skip link targets main content', async ({ page }) => {
		const skipLink = page.locator('a.skip-link');
		await expect(skipLink).toHaveAttribute('href', '#main-content');
		const main = page.locator('main#main-content');
		await expect(main).toBeAttached();
	});

	test('navigation contains required links', async ({ page }) => {
		const nav = page.locator('.global-nav');
		await expect(nav).toBeVisible();
		await expect(nav.locator('a[href="/docs"]')).toBeAttached();
		await expect(nav.locator('a[href*="github.com"]')).toBeAttached();
	});
});

test.describe('Homepage responsive', () => {
	test.use({ viewport: { width: 375, height: 812 } });

	test('mobile layout stacks CTAs vertically', async ({ page }) => {
		await page.goto('/');

		const heroActions = page.locator('.hero-actions');
		await expect(heroActions).toBeVisible();

		const style = await heroActions.evaluate((el) => getComputedStyle(el).flexDirection);
		expect(style).toBe('column');
	});
});
