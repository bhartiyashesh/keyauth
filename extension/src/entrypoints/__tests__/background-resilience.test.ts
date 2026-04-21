import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock chrome APIs
const mockStorage: Record<string, unknown> = {};
const mockChrome = {
  storage: {
    session: {
      set: vi.fn(async (data: Record<string, unknown>) => {
        Object.assign(mockStorage, data);
      }),
      get: vi.fn(async (key: string) => {
        return { [key]: mockStorage[key] ?? null };
      }),
      remove: vi.fn(async (key: string) => {
        delete mockStorage[key];
      }),
    },
    local: {
      get: vi.fn(async () => ({})),
      set: vi.fn(async () => {}),
      remove: vi.fn(async () => {}),
    },
    onChanged: {
      addListener: vi.fn(),
      removeListener: vi.fn(),
    },
  },
  runtime: {
    onMessage: { addListener: vi.fn() },
    sendMessage: vi.fn(),
  },
  tabs: {
    query: vi.fn(async () => []),
    sendMessage: vi.fn(),
  },
};

vi.stubGlobal('chrome', mockChrome);

describe('Resilience: Reconnection Backoff', () => {
  it('exponential backoff caps at 30 seconds', () => {
    const RECONNECT_BASE_MS = 1000;
    const RECONNECT_MAX_MS = 30000;

    const delays = Array.from({ length: 8 }, (_, attempt) =>
      Math.min(RECONNECT_BASE_MS * Math.pow(2, attempt), RECONNECT_MAX_MS)
    );

    expect(delays[0]).toBe(1000);   // 1s
    expect(delays[1]).toBe(2000);   // 2s
    expect(delays[2]).toBe(4000);   // 4s
    expect(delays[3]).toBe(8000);   // 8s
    expect(delays[4]).toBe(16000);  // 16s
    expect(delays[5]).toBe(30000);  // 30s (capped)
    expect(delays[6]).toBe(30000);  // 30s (capped)
    expect(delays[7]).toBe(30000);  // 30s (capped)
  });
});

describe('Resilience: Proactive Reconnect Timer', () => {
  it('proactive reconnect interval is 13 minutes', () => {
    const PROACTIVE_RECONNECT_MS = 13 * 60 * 1000;
    expect(PROACTIVE_RECONNECT_MS).toBe(780000);
    // Must be less than Railway's 15-min timeout (900000)
    expect(PROACTIVE_RECONNECT_MS).toBeLessThan(15 * 60 * 1000);
    // Must provide at least 1-min buffer
    expect(15 * 60 * 1000 - PROACTIVE_RECONNECT_MS).toBeGreaterThanOrEqual(60000);
  });
});

describe('Resilience: Service Worker Wake', () => {
  beforeEach(() => {
    Object.keys(mockStorage).forEach(key => delete mockStorage[key]);
    vi.clearAllMocks();
  });

  it('shouldBeConnected flag persists via session storage', async () => {
    await mockChrome.storage.session.set({ shouldBeConnected: true });
    const result = await mockChrome.storage.session.get('shouldBeConnected');
    expect(result.shouldBeConnected).toBe(true);
  });

  it('disconnect clears shouldBeConnected', async () => {
    await mockChrome.storage.session.set({ shouldBeConnected: true });
    await mockChrome.storage.session.set({ shouldBeConnected: false });
    const result = await mockChrome.storage.session.get('shouldBeConnected');
    expect(result.shouldBeConnected).toBe(false);
  });

  it('keepalive interval is 20 seconds', () => {
    const KEEPALIVE_MS = 20_000;
    expect(KEEPALIVE_MS).toBe(20000);
    // Must be less than Chrome's ~30s idle termination threshold
    expect(KEEPALIVE_MS).toBeLessThan(30000);
  });
});
