import type { PairingData } from './types';

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
