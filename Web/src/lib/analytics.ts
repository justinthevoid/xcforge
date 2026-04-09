import type { DeviceClass, InstallIntentPayload } from './install-intent';

export type AnalyticsActionTier = 'primary' | 'secondary';
export type AnalyticsIntentSignal = 'install' | 'depth-navigation';
export type AnalyticsDestination = 'install' | 'docs' | 'workflow-guide' | 'github';
export type AnalyticsSourceSurface =
	| 'hero'
	| 'final-cta'
	| 'global-nav'
	| 'install-handoff';

export type HomepageActionEventName =
	| 'homepage.install.cta.clicked'
	| 'homepage.docs.clicked'
	| 'homepage.workflow-guide.clicked'
	| 'homepage.github.outbound.clicked';

export type AnalyticsEventName = HomepageActionEventName | 'homepage.install-intent.captured';

export const canonicalHomepageAnalyticsEventNames: readonly AnalyticsEventName[] = [
	'homepage.install.cta.clicked',
	'homepage.docs.clicked',
	'homepage.workflow-guide.clicked',
	'homepage.github.outbound.clicked',
	'homepage.install-intent.captured',
] as const;

export type HomepageActionPayload = {
	route: string;
	deviceClass: DeviceClass;
	sourceSurface: AnalyticsSourceSurface;
	targetHref: string;
	actionTier: AnalyticsActionTier;
	intentSignal: AnalyticsIntentSignal;
	destination: AnalyticsDestination;
	external: boolean;
};

export type HomepageActionEvent = {
	schemaVersion: 1;
	eventName: HomepageActionEventName;
	capturedAt: string;
	payload: HomepageActionPayload;
};

export type InstallIntentCapturedPayload = {
	route: string;
	deviceClass: DeviceClass;
	sourceSurface: 'hero' | 'final-cta';
	targetHref: string;
	actionTier: 'primary';
	intentSignal: 'install';
	destination: 'install';
	installTarget: 'homebrew';
	installCommand: string;
	installIntentSource: 'hero' | 'final-cta';
};

export type InstallIntentCapturedEvent = {
	schemaVersion: 1;
	eventName: 'homepage.install-intent.captured';
	capturedAt: string;
	payload: InstallIntentCapturedPayload;
};

export type HomepageAnalyticsEvent = HomepageActionEvent | InstallIntentCapturedEvent;

export type AnalyticsRelayEnvelope = {
	schemaVersion: 1;
	emittedAt: string;
	events: HomepageAnalyticsEvent[];
};

type AnalyticsQueueEntry = {
	schemaVersion: 1;
	queuedAt: string;
	retryCount: number;
	lastAttemptAt: string | null;
	event: HomepageAnalyticsEvent;
};

const ANALYTICS_SCHEMA_VERSION = 1;
const ANALYTICS_QUEUE_STORAGE_KEY = 'xcforge.analyticsQueue.v1';
const ANALYTICS_QUEUE_MAX_ITEMS = 64;
const ANALYTICS_MAX_RETRY_COUNT = 3;
const ANALYTICS_MAX_EVENT_AGE_MS = 1000 * 60 * 60 * 24 * 7;
const ANALYTICS_MAX_FLUSH_BATCH_SIZE = 20;
const ANALYTICS_RELAY_PATH = '/api/analytics';
const ANALYTICS_ANCHOR_SELECTOR = 'a[data-analytics-event-name]';

const MOBILE_MAX_WIDTH = 767;
const TABLET_MAX_WIDTH = 1023;

let flushTimer: ReturnType<typeof setTimeout> | null = null;
let lifecycleBound = false;
let flushInFlight = false;

function isBrowserRuntime(): boolean {
	return typeof window !== 'undefined' && typeof document !== 'undefined';
}

function isIsoTimestamp(value: unknown): value is string {
	return typeof value === 'string' && value.length > 0 && !Number.isNaN(Date.parse(value));
}

function isString(value: unknown): value is string {
	return typeof value === 'string' && value.trim().length > 0;
}

function isBoolean(value: unknown): value is boolean {
	return typeof value === 'boolean';
}

function isDeviceClass(value: unknown): value is DeviceClass {
	return value === 'mobile' || value === 'tablet' || value === 'desktop';
}

function isAnalyticsActionTier(value: unknown): value is AnalyticsActionTier {
	return value === 'primary' || value === 'secondary';
}

function isAnalyticsIntentSignal(value: unknown): value is AnalyticsIntentSignal {
	return value === 'install' || value === 'depth-navigation';
}

function isAnalyticsDestination(value: unknown): value is AnalyticsDestination {
	return (
		value === 'install' || value === 'docs' || value === 'workflow-guide' || value === 'github'
	);
}

function isAnalyticsSourceSurface(value: unknown): value is AnalyticsSourceSurface {
	return (
		value === 'hero' ||
		value === 'final-cta' ||
		value === 'global-nav' ||
		value === 'install-handoff'
	);
}

function isHomepageActionEventName(value: unknown): value is HomepageActionEventName {
	return (
		value === 'homepage.install.cta.clicked' ||
		value === 'homepage.docs.clicked' ||
		value === 'homepage.workflow-guide.clicked' ||
		value === 'homepage.github.outbound.clicked'
	);
}

function isInstallIntentCapturedPayload(value: unknown): value is InstallIntentCapturedPayload {
	if (!value || typeof value !== 'object') {
		return false;
	}

	const candidate = value as Partial<InstallIntentCapturedPayload>;
	return (
		isString(candidate.route) &&
		isDeviceClass(candidate.deviceClass) &&
		(candidate.sourceSurface === 'hero' || candidate.sourceSurface === 'final-cta') &&
		isString(candidate.targetHref) &&
		candidate.actionTier === 'primary' &&
		candidate.intentSignal === 'install' &&
		candidate.destination === 'install' &&
		candidate.installTarget === 'homebrew' &&
		isString(candidate.installCommand) &&
		(candidate.installIntentSource === 'hero' || candidate.installIntentSource === 'final-cta')
	);
}

function isHomepageActionPayload(value: unknown): value is HomepageActionPayload {
	if (!value || typeof value !== 'object') {
		return false;
	}

	const candidate = value as Partial<HomepageActionPayload>;
	return (
		isString(candidate.route) &&
		isDeviceClass(candidate.deviceClass) &&
		isAnalyticsSourceSurface(candidate.sourceSurface) &&
		isString(candidate.targetHref) &&
		isAnalyticsActionTier(candidate.actionTier) &&
		isAnalyticsIntentSignal(candidate.intentSignal) &&
		isAnalyticsDestination(candidate.destination) &&
		isBoolean(candidate.external)
	);
}

function isHomepageActionEvent(value: unknown): value is HomepageActionEvent {
	if (!value || typeof value !== 'object') {
		return false;
	}

	const candidate = value as Partial<HomepageActionEvent>;
	return (
		candidate.schemaVersion === ANALYTICS_SCHEMA_VERSION &&
		isHomepageActionEventName(candidate.eventName) &&
		isIsoTimestamp(candidate.capturedAt) &&
		isHomepageActionPayload(candidate.payload)
	);
}

function isInstallIntentCapturedEvent(value: unknown): value is InstallIntentCapturedEvent {
	if (!value || typeof value !== 'object') {
		return false;
	}

	const candidate = value as Partial<InstallIntentCapturedEvent>;
	return (
		candidate.schemaVersion === ANALYTICS_SCHEMA_VERSION &&
		candidate.eventName === 'homepage.install-intent.captured' &&
		isIsoTimestamp(candidate.capturedAt) &&
		isInstallIntentCapturedPayload(candidate.payload)
	);
}

export function isHomepageAnalyticsEvent(value: unknown): value is HomepageAnalyticsEvent {
	return isHomepageActionEvent(value) || isInstallIntentCapturedEvent(value);
}

export function isAnalyticsRelayEnvelope(value: unknown): value is AnalyticsRelayEnvelope {
	if (!value || typeof value !== 'object') {
		return false;
	}

	const candidate = value as Partial<AnalyticsRelayEnvelope>;
	return (
		candidate.schemaVersion === ANALYTICS_SCHEMA_VERSION &&
		isIsoTimestamp(candidate.emittedAt) &&
		Array.isArray(candidate.events) &&
		candidate.events.every((event) => isHomepageAnalyticsEvent(event))
	);
}

function isAnalyticsQueueEntry(value: unknown): value is AnalyticsQueueEntry {
	if (!value || typeof value !== 'object') {
		return false;
	}

	const candidate = value as Partial<AnalyticsQueueEntry>;
	return (
		candidate.schemaVersion === ANALYTICS_SCHEMA_VERSION &&
		isIsoTimestamp(candidate.queuedAt) &&
		typeof candidate.retryCount === 'number' &&
		candidate.retryCount >= 0 &&
		Number.isInteger(candidate.retryCount) &&
		(candidate.lastAttemptAt === null || isIsoTimestamp(candidate.lastAttemptAt)) &&
		isHomepageAnalyticsEvent(candidate.event)
	);
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

function resolveDeviceClass(): DeviceClass {
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

function pruneQueue(entries: AnalyticsQueueEntry[], nowMs = Date.now()): AnalyticsQueueEntry[] {
	const oldestAllowedMs = nowMs - ANALYTICS_MAX_EVENT_AGE_MS;

	const filtered = entries.filter((entry) => {
		const queuedAtMs = Date.parse(entry.queuedAt);
		if (Number.isNaN(queuedAtMs) || queuedAtMs < oldestAllowedMs) {
			return false;
		}

		return entry.retryCount <= ANALYTICS_MAX_RETRY_COUNT;
	});

	return filtered.slice(-ANALYTICS_QUEUE_MAX_ITEMS);
}

function readQueue(): AnalyticsQueueEntry[] {
	if (!isBrowserRuntime()) {
		return [];
	}

	const rawQueue = safeReadStorage(ANALYTICS_QUEUE_STORAGE_KEY);
	if (!Array.isArray(rawQueue)) {
		return [];
	}

	const safeQueue = rawQueue.filter((entry) => isAnalyticsQueueEntry(entry));
	const prunedQueue = pruneQueue(safeQueue);

	if (prunedQueue.length !== safeQueue.length) {
		safeWriteStorage(ANALYTICS_QUEUE_STORAGE_KEY, prunedQueue);
	}

	return prunedQueue;
}

function writeQueue(entries: AnalyticsQueueEntry[]): boolean {
	if (!isBrowserRuntime()) {
		return false;
	}

	return safeWriteStorage(ANALYTICS_QUEUE_STORAGE_KEY, pruneQueue(entries));
}

function isPrimaryUnmodifiedClick(event: MouseEvent): boolean {
	return event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey;
}

function parseTrackedAnchorEvent(anchor: HTMLAnchorElement): HomepageActionEvent | null {
	const eventName = anchor.dataset.analyticsEventName;
	const destination = anchor.dataset.analyticsDestination;
	const sourceSurface = anchor.dataset.analyticsSourceSurface;
	const intentSignal = anchor.dataset.analyticsIntentSignal;

	if (
		!isHomepageActionEventName(eventName) ||
		!isAnalyticsDestination(destination) ||
		!isAnalyticsSourceSurface(sourceSurface) ||
		!isAnalyticsIntentSignal(intentSignal)
	) {
		return null;
	}

	let absoluteHref = anchor.href;
	let external = false;

	try {
		const targetUrl = new URL(anchor.href, window.location.origin);
		absoluteHref = targetUrl.toString();
		external = targetUrl.origin !== window.location.origin;
	} catch {
		external = anchor.target === '_blank';
	}

	return {
		schemaVersion: ANALYTICS_SCHEMA_VERSION,
		eventName,
		capturedAt: new Date().toISOString(),
		payload: {
			route: window.location.pathname,
			deviceClass: resolveDeviceClass(),
			sourceSurface,
			targetHref: absoluteHref,
			actionTier: isAnalyticsActionTier(anchor.dataset.actionTier)
				? anchor.dataset.actionTier
				: 'secondary',
			intentSignal,
			destination,
			external,
		},
	};
}

export function enqueueHomepageAnalyticsEvent(event: HomepageAnalyticsEvent): boolean {
	if (!isBrowserRuntime()) {
		return false;
	}

	const queue = readQueue();
	queue.push({
		schemaVersion: ANALYTICS_SCHEMA_VERSION,
		queuedAt: new Date().toISOString(),
		retryCount: 0,
		lastAttemptAt: null,
		event,
	});

	const written = writeQueue(queue);
	if (written) {
		scheduleAnalyticsFlush();
	}

	return written;
}

export function enqueueTaggedAnchorClickEvent(anchor: HTMLAnchorElement): boolean {
	if (!isBrowserRuntime()) {
		return false;
	}

	const event = parseTrackedAnchorEvent(anchor);
	if (!event) {
		return false;
	}

	return enqueueHomepageAnalyticsEvent(event);
}

export function enqueueInstallIntentCapturedEvent(payload: InstallIntentPayload): boolean {
	const event: InstallIntentCapturedEvent = {
		schemaVersion: ANALYTICS_SCHEMA_VERSION,
		eventName: 'homepage.install-intent.captured',
		capturedAt: new Date().toISOString(),
		payload: {
			route: payload.route,
			deviceClass: payload.deviceClass,
			sourceSurface: payload.source,
			targetHref: payload.installHref,
			actionTier: 'primary',
			intentSignal: 'install',
			destination: 'install',
			installTarget: payload.target,
			installCommand: payload.command,
			installIntentSource: payload.source,
		},
	};

	return enqueueHomepageAnalyticsEvent(event);
}

function markBatchFailed(queue: AnalyticsQueueEntry[], batchSize: number): AnalyticsQueueEntry[] {
	const attemptedAt = new Date().toISOString();
	const nextQueue = queue.map((entry, index) => {
		if (index >= batchSize) {
			return entry;
		}

		return {
			...entry,
			retryCount: entry.retryCount + 1,
			lastAttemptAt: attemptedAt,
		};
	});

	return pruneQueue(nextQueue);
}

function dropBatch(queue: AnalyticsQueueEntry[], batchSize: number): AnalyticsQueueEntry[] {
	return pruneQueue(queue.slice(batchSize));
}

function isRetryableRelayStatus(status: number): boolean {
	return status === 408 || status === 429 || status >= 500;
}

async function flushAnalyticsQueue(): Promise<void> {
	if (!isBrowserRuntime() || flushInFlight) {
		return;
	}

	if (typeof navigator !== 'undefined' && !navigator.onLine) {
		return;
	}

	const queue = readQueue();
	if (queue.length === 0) {
		return;
	}

	flushInFlight = true;
	const batch = queue.slice(0, ANALYTICS_MAX_FLUSH_BATCH_SIZE);
	const relayEnvelope: AnalyticsRelayEnvelope = {
		schemaVersion: ANALYTICS_SCHEMA_VERSION,
		emittedAt: new Date().toISOString(),
		events: batch.map((entry) => entry.event),
	};

	try {
		const response = await fetch(ANALYTICS_RELAY_PATH, {
			method: 'POST',
			headers: {
				'content-type': 'application/json',
			},
			credentials: 'same-origin',
			keepalive: true,
			body: JSON.stringify(relayEnvelope),
		});

		if (response.ok) {
			const remainingQueue = queue.slice(batch.length);
			writeQueue(remainingQueue);
		} else if (isRetryableRelayStatus(response.status)) {
			writeQueue(markBatchFailed(queue, batch.length));
		} else {
			writeQueue(dropBatch(queue, batch.length));
		}
	} catch {
		writeQueue(markBatchFailed(queue, batch.length));
	} finally {
		flushInFlight = false;
		const remainingQueue = readQueue();
		if (remainingQueue.length > 0) {
			scheduleAnalyticsFlush(2000);
		}
	}
}

function scheduleAnalyticsFlush(delayMs = 0): void {
	if (!isBrowserRuntime()) {
		return;
	}

	if (flushTimer !== null) {
		return;
	}

	flushTimer = setTimeout(() => {
		flushTimer = null;
		void flushAnalyticsQueue();
	}, delayMs);
}

function bindAnchorTracking(anchor: HTMLAnchorElement): void {
	if (anchor.dataset.analyticsBound === 'true') {
		return;
	}

	anchor.dataset.analyticsBound = 'true';
	anchor.addEventListener('click', (event) => {
		if (!isPrimaryUnmodifiedClick(event)) {
			return;
		}

		enqueueTaggedAnchorClickEvent(anchor);
	});
}

function bindLifecycleHooks(): void {
	if (lifecycleBound) {
		return;
	}

	lifecycleBound = true;
	window.addEventListener('online', () => {
		scheduleAnalyticsFlush();
	});

	window.addEventListener('pagehide', () => {
		void flushAnalyticsQueue();
	});

	document.addEventListener('visibilitychange', () => {
		if (document.visibilityState === 'hidden') {
			void flushAnalyticsQueue();
		}
	});
}

export function initializeHomepageAnalytics(): void {
	if (!isBrowserRuntime()) {
		return;
	}

	const trackedAnchors = document.querySelectorAll<HTMLAnchorElement>(ANALYTICS_ANCHOR_SELECTOR);
	for (const anchor of trackedAnchors) {
		bindAnchorTracking(anchor);
	}

	bindLifecycleHooks();
	scheduleAnalyticsFlush();
}
