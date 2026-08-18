import { describe, it, expect, vi, beforeEach } from 'vitest';
import { encryptCredentials } from '../crypto';

// jsdom lacks a usable crypto.subtle for WebCrypto round-trips in some
// configurations; stub a minimal AES-GCM implementation backed by node's webcrypto.
const webcrypto = (globalThis as { crypto?: Crypto }).crypto ?? (await import('node:crypto')).webcrypto;

beforeEach(() => {
  window.sessionStorage.clear();
  Object.defineProperty(window, 'crypto', {
    value: webcrypto,
    writable: true,
    configurable: true,
  });
});

describe('encryptCredentials', () => {
  it('returns settings unchanged when encryption is disabled', async () => {
    const settings = { connection: { proxyPass: 'secret' }, extra: { encryptAccessTokens: false } };
    await expect(encryptCredentials(settings)).resolves.toBe(settings);
  });

  it('returns settings unchanged when encryption flag is missing', async () => {
    const settings = { connection: { proxyPass: 'secret' }, extra: {} };
    await expect(encryptCredentials(settings)).resolves.toBe(settings);
  });

  it('encrypts configured credential fields when enabled', async () => {
    const settings = {
      connection: { proxyPass: 'pw', proxyUser: 'user' },
      extra: { encryptAccessTokens: true, tgBotToken: 'token' },
    };
    const result = await encryptCredentials(settings);
    expect(result).not.toBe(settings);
    expect(result.connection.proxyPass).toMatch(/^enc:/);
    // Base64 ciphertext is arbitrary text and can coincidentally contain a
    // plaintext substring. Instead assert the AES-GCM envelope structure:
    // 12-byte IV + 16-byte authentication tag + plaintext bytes.
    const proxyPassPayload = atob(result.connection.proxyPass.slice('enc:'.length));
    expect(proxyPassPayload).toHaveLength(12 + 16 + new TextEncoder().encode('pw').byteLength);
    expect(result.connection.proxyPass).not.toBe('enc:pw');
    expect(result.connection.proxyUser).toMatch(/^enc:/);
    expect(result.extra.tgBotToken).toMatch(/^enc:/);
  });

  it('does not re-encrypt already encrypted values', async () => {
    const settings = {
      connection: { proxyPass: 'enc:already' },
      extra: { encryptAccessTokens: true },
    };
    const result = await encryptCredentials(settings);
    expect(result.connection.proxyPass).toBe('enc:already');
  });

  it('leaves unset fields alone', async () => {
    const settings = { connection: { proxyPass: undefined }, extra: { encryptAccessTokens: true } };
    const result = await encryptCredentials(settings);
    expect(result.connection.proxyPass).toBeUndefined();
  });

  it('returns plaintext when WebCrypto is unavailable', async () => {
    Object.defineProperty(window, 'crypto', {
      value: { subtle: undefined },
      writable: true,
      configurable: true,
    });
    const settings = { connection: { proxyPass: 'pw' }, extra: { encryptAccessTokens: true } };
    const result = await encryptCredentials(settings);
    expect(result.connection.proxyPass).toBe('pw');
    expect(vi.isMockFunction(window.crypto.subtle as unknown as () => void)).toBe(false);
  });

  it('reuses the key from sessionStorage across calls', async () => {
    const settings = { connection: { proxyPass: 'pw' }, extra: { encryptAccessTokens: true } };
    await encryptCredentials(settings);
    const stored = window.sessionStorage.getItem('nova_encryption_key_v1');
    expect(stored).toBeTruthy();
    const second = await encryptCredentials({ connection: { proxyUser: 'u' }, extra: { encryptAccessTokens: true } });
    expect(second.connection.proxyUser).toMatch(/^enc:/);
  });
});
