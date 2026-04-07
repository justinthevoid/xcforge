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

export type HomepageContent = {
  navigation: NavItem[];
  hero: HeroCopy;
};

const requiredNavOrder: NavItemId[] = [
  'product',
  'docs',
  'workflow-guide',
  'changelog',
  'github',
  'install',
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

export const homepageContent: HomepageContent = {
  navigation: safeNavigationFallback,
  hero: {
    problemLine:
      'AI code suggestions are fast. Local iOS verification loops are where momentum stalls.',
    productRole:
      'xcforge gives agents hands-on control of build, test, simulators, logs, screenshots, and debug loops so outcomes are verifiable.',
    installCommand: 'brew install xcforge',
    installHref: 'https://github.com/justinthevoid/xcforge#install',
    installExternal: true,
    proofHeadline: 'Proof you can inspect in one scan',
    proofSummary:
      '103 MCP tools, 17 CLI command groups, native Swift binary, and no external runtime dependencies.',
    fallbackProofText:
      'Proof metadata is temporarily unavailable. Install via Homebrew now, then verify workflows in docs and changelog.',
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
