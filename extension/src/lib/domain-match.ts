import type { AccountMetadata } from './types';

/**
 * Check if a domain matches an issuer using string-contains logic.
 * Mirrors iOS CodeApprovalView.swift domainMatchedAccounts logic exactly:
 * - domain.lowercased().contains(issuer.lowercased())
 * - OR issuer.lowercased().contains(domain stripped of TLD)
 *
 * Per D-03: simple string-contains, consistent across platforms.
 */
export function domainMatchesIssuer(domain: string, issuer: string): boolean {
  if (!domain || !issuer) return false;
  const domainLower = domain.toLowerCase();
  const issuerLower = issuer.toLowerCase();
  // Strip www prefix and common TLDs for the reverse check
  // (mirrors Swift .replacingOccurrences(of: ".com", with: ""))
  const domainBase = domainLower
    .replace(/^www\./, '')
    .replace(/\.(com|org|io|net|dev|app|co)$/, '');
  return domainLower.includes(issuerLower) || issuerLower.includes(domainBase);
}

/**
 * Sort accounts with domain-matched accounts first, preserving relative order within each group.
 */
export function sortAccountsByDomain(accounts: AccountMetadata[], domain: string): AccountMetadata[] {
  if (!domain) return accounts;
  const matched: AccountMetadata[] = [];
  const unmatched: AccountMetadata[] = [];
  for (const account of accounts) {
    if (domainMatchesIssuer(domain, account.issuer)) {
      matched.push(account);
    } else {
      unmatched.push(account);
    }
  }
  return [...matched, ...unmatched];
}
