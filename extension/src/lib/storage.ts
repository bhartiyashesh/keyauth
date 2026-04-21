import type { PairingData, AccountMetadata } from './types';

// chrome.storage.local -- persists across sessions

export async function savePairingData(data: PairingData): Promise<void> {
  await chrome.storage.local.set({ pairing: data });
}

export async function loadPairingData(): Promise<PairingData | null> {
  const result = await chrome.storage.local.get('pairing');
  return result.pairing ?? null;
}

export async function clearPairingData(): Promise<void> {
  await chrome.storage.local.remove('pairing');
}

// chrome.storage.session -- survives service worker restarts within session

export async function setSessionState(state: Record<string, unknown>): Promise<void> {
  await chrome.storage.session.set(state);
}

export async function getSessionState<T>(key: string): Promise<T | null> {
  const result = await chrome.storage.session.get(key);
  return (result[key] as T) ?? null;
}

// Account list -- session storage only (D-01: no persistent cache)

export async function saveAccounts(accounts: AccountMetadata[]): Promise<void> {
  await chrome.storage.session.set({ accounts });
}

export async function loadAccounts(): Promise<AccountMetadata[]> {
  const result = await chrome.storage.session.get('accounts');
  return (result.accounts as AccountMetadata[]) ?? [];
}

export async function clearAccounts(): Promise<void> {
  await chrome.storage.session.remove('accounts');
}
