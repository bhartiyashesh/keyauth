import { describe, it, expect } from 'vitest';
import { domainMatchesIssuer, sortAccountsByDomain } from '../domain-match';

describe('domainMatchesIssuer', () => {
  it('matches when domain contains issuer (github.com contains github)', () => {
    expect(domainMatchesIssuer('github.com', 'GitHub')).toBe(true);
  });

  it('matches when issuer contains domain base (Google contains google)', () => {
    expect(domainMatchesIssuer('accounts.google.com', 'Google')).toBe(true);
  });

  it('returns false for non-matching', () => {
    expect(domainMatchesIssuer('github.com', 'Google')).toBe(false);
  });

  it('returns false for empty domain', () => {
    expect(domainMatchesIssuer('', 'GitHub')).toBe(false);
  });

  it('returns false for empty issuer', () => {
    expect(domainMatchesIssuer('github.com', '')).toBe(false);
  });

  it('handles subdomains (login.microsoft.com matches Microsoft)', () => {
    expect(domainMatchesIssuer('login.microsoft.com', 'Microsoft')).toBe(true);
  });

  it('handles .app TLD (linear.app matches Linear)', () => {
    expect(domainMatchesIssuer('linear.app', 'Linear')).toBe(true);
  });

  it('handles www prefix stripping', () => {
    expect(domainMatchesIssuer('www.github.com', 'GitHub')).toBe(true);
  });
});

describe('sortAccountsByDomain', () => {
  const accounts = [
    { id: '1', issuer: 'Google', label: 'me@gmail.com' },
    { id: '2', issuer: 'GitHub', label: 'dev@github.com' },
    { id: '3', issuer: 'AWS', label: 'admin@aws.com' },
  ];

  it('puts matching accounts first', () => {
    const sorted = sortAccountsByDomain(accounts, 'github.com');
    expect(sorted[0].issuer).toBe('GitHub');
  });

  it('preserves order for unmatched accounts', () => {
    const sorted = sortAccountsByDomain(accounts, 'github.com');
    expect(sorted[1].issuer).toBe('Google');
    expect(sorted[2].issuer).toBe('AWS');
  });

  it('returns original order when domain is empty', () => {
    const sorted = sortAccountsByDomain(accounts, '');
    expect(sorted).toEqual(accounts);
  });
});
