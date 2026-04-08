<script lang="ts">
import { onMount } from 'svelte';

import type { ProofSnapshotForRender, ProofSnapshotId } from '../../data/homepage';

export let snapshots: ProofSnapshotForRender[] = [];
export let defaultSnapshotId: ProofSnapshotId = 'xcforge-proof';

let activeSnapshotId: ProofSnapshotId = defaultSnapshotId;
let _prefersReducedMotion = true;

function resolveDefaultSnapshotId(): ProofSnapshotId {
	if (snapshots.some((snapshot) => snapshot.id === defaultSnapshotId)) {
		return defaultSnapshotId;
	}

	if (snapshots.some((snapshot) => snapshot.id === 'xcforge-proof')) {
		return 'xcforge-proof';
	}

	if (snapshots.some((snapshot) => snapshot.id === 'manual-baseline')) {
		return 'manual-baseline';
	}

	return snapshots[0]?.id ?? 'xcforge-proof';
}

function selectSnapshot(nextSnapshotId: ProofSnapshotId): void {
	if (!snapshots.some((snapshot) => snapshot.id === nextSnapshotId)) {
		return;
	}

	if (activeSnapshotId === nextSnapshotId) {
		return;
	}

	activeSnapshotId = nextSnapshotId;
}

function getOrderedSnapshotIds(): ProofSnapshotId[] {
	const preferredOrder: ProofSnapshotId[] = ['manual-baseline', 'xcforge-proof'];
	const snapshotIds = snapshots
		.map((snapshot) => snapshot.id)
		.filter((snapshotId, index, allIds) => allIds.indexOf(snapshotId) === index);

	const preferredSnapshotIds = preferredOrder.filter((snapshotId) =>
		snapshotIds.includes(snapshotId),
	);
	const remainingSnapshotIds = snapshotIds.filter(
		(snapshotId) => !preferredSnapshotIds.includes(snapshotId),
	);

	return [...preferredSnapshotIds, ...remainingSnapshotIds];
}

function _handleToggleKeydown(event: KeyboardEvent): void {
	if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') {
		return;
	}

	event.preventDefault();
	const orderedSnapshotIds = getOrderedSnapshotIds();
	const currentIndex = orderedSnapshotIds.indexOf(activeSnapshotId);
	if (currentIndex < 0) {
		return;
	}

	const delta = event.key === 'ArrowRight' ? 1 : -1;
	const nextIndex = (currentIndex + delta + orderedSnapshotIds.length) % orderedSnapshotIds.length;
	const nextSnapshotId = orderedSnapshotIds[nextIndex];
	selectSnapshot(nextSnapshotId);
}

function _getButtonLabel(snapshot: ProofSnapshotForRender): string {
	if (snapshot.id === activeSnapshotId) {
		return `${snapshot.label} (selected)`;
	}

	return `Show ${snapshot.label}`;
}

function _isExternalHref(href: string): boolean {
	return /^https?:\/\//i.test(href);
}

function _getLiveAnnouncement(): string {
	const activeSnapshot = snapshots.find((snapshot) => snapshot.id === activeSnapshotId);
	return (
		activeSnapshot?.announcement ??
		'Proof snapshot unavailable. Static approved trust claims remain visible.'
	);
}

$: activeSnapshotId = snapshots.some((snapshot) => snapshot.id === activeSnapshotId)
	? activeSnapshotId
	: resolveDefaultSnapshotId();

onMount(() => {
	activeSnapshotId = resolveDefaultSnapshotId();

	try {
		const reduceMotionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
		_prefersReducedMotion = reduceMotionQuery.matches;

		const handleReduceMotionChange = (event: MediaQueryListEvent): void => {
			_prefersReducedMotion = event.matches;
		};

		if (typeof reduceMotionQuery.addEventListener === 'function') {
			reduceMotionQuery.addEventListener('change', handleReduceMotionChange);
			return () => reduceMotionQuery.removeEventListener('change', handleReduceMotionChange);
		}

		reduceMotionQuery.addListener(handleReduceMotionChange);
		return () => reduceMotionQuery.removeListener(handleReduceMotionChange);
	} catch {
		_prefersReducedMotion = true;
	}

	return undefined;
});
</script>

<section class="proof-toggle" data-reduced-motion={_prefersReducedMotion ? 'true' : 'false'}>
	<p class="proof-toggle-heading" id="proof-toggle-heading">Proof comparison</p>
	{#if snapshots.length === 0}
		<p class="proof-toggle-empty" role="status" aria-live="polite">
			Proof snapshot unavailable. Static approved trust claims remain visible.
		</p>
	{:else}
		<div
			class="proof-toggle-controls"
			role="group"
			aria-labelledby="proof-toggle-heading"
			on:keydown={_handleToggleKeydown}
		>
			{#each snapshots as snapshot}
				<button
					type="button"
					class="proof-toggle-button"
					data-selected={snapshot.id === activeSnapshotId ? 'true' : 'false'}
					aria-pressed={snapshot.id === activeSnapshotId}
					aria-controls={`proof-snapshot-${snapshot.id}`}
					on:click={() => selectSnapshot(snapshot.id)}
				>
					<span class="proof-toggle-button-label">{_getButtonLabel(snapshot)}</span>
				</button>
			{/each}
		</div>
		<p class="proof-toggle-status" role="status" aria-live="polite">{_getLiveAnnouncement()}</p>
		<div class="proof-snapshot-grid" aria-label="Proof snapshots">
			{#each snapshots as snapshot}
				<article
					id={`proof-snapshot-${snapshot.id}`}
					class="proof-snapshot-card"
					data-selected={snapshot.id === activeSnapshotId ? 'true' : 'false'}
					data-state={snapshot.provenance.state}
				>
					<p class="proof-snapshot-state">
						{snapshot.id === activeSnapshotId ? 'Current view' : 'Available view'}
					</p>
					<h3>{snapshot.label}</h3>
					<p>{snapshot.summary}</p>
					<p class="proof-snapshot-trust">
						<span class="proof-marker-state" data-state={snapshot.provenance.state}>
							{snapshot.provenance.stateLabel}
						</span>
						<span>{snapshot.provenance.stateDetail}</span>
					</p>
					{#if snapshot.provenance.sources.length > 0}
						<ul class="proof-snapshot-sources">
							{#each snapshot.provenance.sources as source}
								<li>
									<a
										href={source.href}
										target={_isExternalHref(source.href) ? '_blank' : undefined}
										rel={_isExternalHref(source.href) ? 'noreferrer noopener' : undefined}
									>
										{source.label}
									</a>
									<span class="proof-snapshot-source-meta">
										{source.capturedOnLabel}
										· {source.freshnessLabel}
									</span>
								</li>
							{/each}
						</ul>
					{/if}
					{#if snapshot.provenance.state === 'warning'}
						<p class="proof-snapshot-warning">
							{snapshot.provenance.sources.length > 0
								? 'Some provenance entries are unavailable.'
								: 'Provenance details are unavailable.'}
							<a href={snapshot.provenance.fallbackHref}> Review provenance guidance.</a>
						</p>
					{/if}
				</article>
			{/each}
		</div>
	{/if}
</section>
