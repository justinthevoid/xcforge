export type InstallIntentSource = 'hero' | 'final-cta';
export type InstallTarget = 'homebrew';
export type DeviceClass = 'mobile' | 'tablet' | 'desktop';

export type InstallIntentPayload = {
	schemaVersion: 1;
	target: InstallTarget;
	source: InstallIntentSource;
	command: string;
	installHref: string;
	route: string;
	deviceClass: DeviceClass;
	capturedAt: string;
};

export type InstallIntentRelayEvent = {
	schemaVersion: 1;
	eventName: 'install.intent.captured';
	queuedAt: string;
	payload: InstallIntentPayload;
};

const INSTALL_INTENT_STORAGE_KEY = 'xcforge.installIntent.v1';
const INSTALL_INTENT_RELAY_QUEUE_KEY = 'xcforge.installIntentRelayQueue.v1';
const DEFAULT_INSTALL_COMMAND = 'brew install xcforge';
const MOBILE_MAX_WIDTH = 767;
const TABLET_MAX_WIDTH = 1023;
const INSTALL_INTENT_TTL_MS = 1000 * 60 * 60 * 24 * 7;

function isBrowserRuntime(): boolean {
	return typeof window !== 'undefined' && typeof document !== 'undefined';
}

function safeReadStorage(rawKey: string): unknown | null {
	try {
		const rawValue = window.localStorage.getItem(rawKey);
		if (!rawValue) {
			return null;
		}
		return JSON.parse(rawValue);
	} catch {
		return null;
	}
}

function safeWriteStorage(rawKey: string, value: unknown): boolean {
	try {
		window.localStorage.setItem(rawKey, JSON.stringify(value));
		return true;
	} catch {
		return false;
	}
}

function isInstallIntentSource(value: string | undefined): value is InstallIntentSource {
	return value === 'hero' || value === 'final-cta';
}

function isInstallTarget(value: string | undefined): value is InstallTarget {
	return value === 'homebrew';
}

function getDeviceClass(): DeviceClass {
	if (!isBrowserRuntime()) {
		return 'desktop';
	}

	const viewportWidth = window.innerWidth;
	if (viewportWidth <= MOBILE_MAX_WIDTH) {
		return 'mobile';
	}

	if (viewportWidth <= TABLET_MAX_WIDTH) {
		return 'tablet';
	}

	return 'desktop';
}

function isTouchPrimaryDevice(): boolean {
	if (!isBrowserRuntime()) {
		return false;
	}

	return (
		window.matchMedia('(pointer: coarse)').matches && window.matchMedia('(hover: none)').matches
	);
}

function clearInstallIntent(): void {
	if (!isBrowserRuntime()) {
		return;
	}

	try {
		window.localStorage.removeItem(INSTALL_INTENT_STORAGE_KEY);
	} catch {
		// Ignore storage cleanup failures to preserve non-blocking behavior.
	}
}

function isInstallIntentPayload(value: unknown): value is InstallIntentPayload {
	if (!value || typeof value !== 'object') {
		return false;
	}

	const candidate = value as Partial<InstallIntentPayload>;
	return (
		candidate.schemaVersion === 1 &&
		candidate.target === 'homebrew' &&
		(candidate.source === 'hero' || candidate.source === 'final-cta') &&
		typeof candidate.command === 'string' &&
		candidate.command.length > 0 &&
		typeof candidate.installHref === 'string' &&
		candidate.installHref.length > 0 &&
		typeof candidate.route === 'string' &&
		candidate.route.length > 0 &&
		(candidate.deviceClass === 'mobile' ||
			candidate.deviceClass === 'tablet' ||
			candidate.deviceClass === 'desktop') &&
		typeof candidate.capturedAt === 'string' &&
		candidate.capturedAt.length > 0
	);
}

function isInstallIntentRelayEvent(value: unknown): value is InstallIntentRelayEvent {
	if (!value || typeof value !== 'object') {
		return false;
	}

	const candidate = value as Partial<InstallIntentRelayEvent>;
	return (
		candidate.schemaVersion === 1 &&
		candidate.eventName === 'install.intent.captured' &&
		typeof candidate.queuedAt === 'string' &&
		candidate.queuedAt.length > 0 &&
		isInstallIntentPayload(candidate.payload)
	);
}

export function restoreInstallIntent(): InstallIntentPayload | null {
	if (!isBrowserRuntime()) {
		return null;
	}

	const stored = safeReadStorage(INSTALL_INTENT_STORAGE_KEY);
	if (!isInstallIntentPayload(stored)) {
		clearInstallIntent();
		return null;
	}

	const capturedAtMs = Date.parse(stored.capturedAt);
	if (Number.isNaN(capturedAtMs) || Date.now() - capturedAtMs > INSTALL_INTENT_TTL_MS) {
		clearInstallIntent();
		return null;
	}

	return stored;
}

export function persistInstallIntent(payload: InstallIntentPayload): boolean {
	if (!isBrowserRuntime()) {
		return false;
	}

	return safeWriteStorage(INSTALL_INTENT_STORAGE_KEY, payload);
}

export function enqueueInstallIntentRelay(payload: InstallIntentPayload): boolean {
	if (!isBrowserRuntime()) {
		return false;
	}

	const relayEvent: InstallIntentRelayEvent = {
		schemaVersion: 1,
		eventName: 'install.intent.captured',
		queuedAt: new Date().toISOString(),
		payload,
	};

	const current = safeReadStorage(INSTALL_INTENT_RELAY_QUEUE_KEY);
	const safeQueue = Array.isArray(current)
		? current.filter((event) => isInstallIntentRelayEvent(event))
		: [];
	safeQueue.push(relayEvent);
	const recentQueue = safeQueue.slice(-20);
	return safeWriteStorage(INSTALL_INTENT_RELAY_QUEUE_KEY, recentQueue);
}

function buildInstallIntentPayload(trigger: HTMLAnchorElement): InstallIntentPayload {
	const source = isInstallIntentSource(trigger.dataset.installIntentSource)
		? trigger.dataset.installIntentSource
		: 'hero';
	const target = isInstallTarget(trigger.dataset.installTarget)
		? trigger.dataset.installTarget
		: 'homebrew';
	const command = trigger.dataset.installCommand?.trim() || DEFAULT_INSTALL_COMMAND;

	return {
		schemaVersion: 1,
		target,
		source,
		command,
		installHref: trigger.href,
		route: window.location.pathname,
		deviceClass: getDeviceClass(),
		capturedAt: new Date().toISOString(),
	};
}

function isMobileDeferredInstall(): boolean {
	const deviceClass = getDeviceClass();
	if (deviceClass === 'mobile') {
		return true;
	}

	return deviceClass === 'tablet' && isTouchPrimaryDevice();
}

function resolveMessage(handoffRoot: HTMLElement, state: 'ready' | 'failure' | 'restored'): string {
	const readyMessage =
		handoffRoot.dataset.readyMessage ||
		'Install intent captured for later completion. Copy the command to continue.';
	const failureMessage =
		handoffRoot.dataset.failureMessage ||
		'Install intent could not be saved on this device. Copy the command to continue.';
	const restoredMessage =
		handoffRoot.dataset.restoredMessage ||
		'Saved install intent restored. Continue with the command below when ready.';

	if (state === 'failure') {
		return failureMessage;
	}

	if (state === 'restored') {
		return restoredMessage;
	}

	return readyMessage;
}

function revealHandoff(
	handoffRoot: HTMLElement,
	payload: InstallIntentPayload,
	state: 'ready' | 'failure' | 'restored',
): void {
	const messageNode = handoffRoot.querySelector<HTMLElement>('[data-install-handoff-message]');
	const commandNode = handoffRoot.querySelector<HTMLElement>('[data-install-handoff-command]');
	const guideLinkNode = handoffRoot.querySelector<HTMLAnchorElement>(
		'[data-install-handoff-guide-link]',
	);

	handoffRoot.hidden = false;
	handoffRoot.dataset.state = state;

	if (commandNode) {
		commandNode.textContent = payload.command;
	}

	if (guideLinkNode) {
		guideLinkNode.href = payload.installHref;
	}

	if (messageNode) {
		const message = resolveMessage(handoffRoot, state);
		messageNode.textContent = '';
		window.requestAnimationFrame(() => {
			messageNode.textContent = message;
		});
	}
}

async function copyText(text: string): Promise<boolean> {
	if (!text.trim()) {
		return false;
	}

	try {
		await navigator.clipboard.writeText(text);
		return true;
	} catch {
		try {
			const tempNode = document.createElement('textarea');
			tempNode.value = text;
			tempNode.setAttribute('readonly', 'true');
			tempNode.style.position = 'absolute';
			tempNode.style.left = '-9999px';
			document.body.append(tempNode);
			tempNode.select();
			const copyResult = document.execCommand('copy');
			tempNode.remove();
			return copyResult;
		} catch {
			return false;
		}
	}
}

function wireCopyButton(handoffRoot: HTMLElement): void {
	const copyButton = handoffRoot.querySelector<HTMLButtonElement>('[data-copy-install-command]');
	const commandNode = handoffRoot.querySelector<HTMLElement>('[data-install-handoff-command]');
	const messageNode = handoffRoot.querySelector<HTMLElement>('[data-install-handoff-message]');

	if (!copyButton || !commandNode || !messageNode) {
		return;
	}

	copyButton.addEventListener('click', async () => {
		const command = commandNode.textContent?.trim() || '';
		const copied = await copyText(command);
		messageNode.textContent = copied
			? 'Command copied. Run it in your terminal when ready.'
			: 'Copy failed. Select and copy the command manually.';

		if (copied) {
			clearInstallIntent();
		}
	});
}

function wireGuideLinkClear(handoffRoot: HTMLElement): void {
	const guideLink = handoffRoot.querySelector<HTMLAnchorElement>(
		'[data-install-handoff-guide-link]',
	);
	if (!guideLink) {
		return;
	}

	guideLink.addEventListener('click', () => {
		clearInstallIntent();
	});
}

function wirePrimaryCtaStateObserver(): void {
	const finalCtaSection = document.querySelector<HTMLElement>('#final-cta');
	if (!finalCtaSection) {
		return;
	}

	document.body.dataset.primaryCtaRegion = 'hero';

	const observer = new IntersectionObserver(
		(entries) => {
			for (const entry of entries) {
				if (entry.target !== finalCtaSection) {
					continue;
				}

				document.body.dataset.primaryCtaRegion =
					entry.isIntersecting && entry.intersectionRatio >= 0.35 ? 'final' : 'hero';
			}
		},
		{ threshold: [0, 0.35, 0.7] },
	);

	observer.observe(finalCtaSection);
}

function wireInstallTriggers(handoffRoot: HTMLElement): void {
	const triggers = document.querySelectorAll<HTMLAnchorElement>(
		'[data-install-intent-trigger="true"]',
	);
	if (!triggers.length) {
		return;
	}

	for (const trigger of triggers) {
		trigger.addEventListener('click', (event) => {
			if (!isMobileDeferredInstall()) {
				return;
			}

			event.preventDefault();
			const payload = buildInstallIntentPayload(trigger);
			const persisted = persistInstallIntent(payload);
			const queued = enqueueInstallIntentRelay(payload);
			const state = persisted && queued ? 'ready' : 'failure';
			revealHandoff(handoffRoot, payload, state);
			handoffRoot.scrollIntoView({
				behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth',
				block: 'nearest',
			});
		});
	}
}

export function initializeInstallIntentHandoff(): void {
	if (!isBrowserRuntime()) {
		return;
	}

	const handoffRoot = document.querySelector<HTMLElement>('[data-install-handoff]');
	if (!handoffRoot) {
		return;
	}

	wireCopyButton(handoffRoot);
	wireGuideLinkClear(handoffRoot);
	wireInstallTriggers(handoffRoot);
	wirePrimaryCtaStateObserver();

	const restoredIntent = restoreInstallIntent();
	if (restoredIntent && isMobileDeferredInstall()) {
		revealHandoff(handoffRoot, restoredIntent, 'restored');
	}
}
