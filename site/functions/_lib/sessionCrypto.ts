// functions/_lib/sessionCrypto.ts
//
// AES-256-GCM sealing for the Patreon session_id while it sits in KV.
// The session cookie is account-takeover material, so it must never be
// stored in plaintext: anyone with dashboard/API access to the KV namespace
// could otherwise read live sessions during the pairing window.
//
// Key: `PAIRING_SESSION_KEY` env var — 32 random bytes, base64-encoded.
// Generate one with:  openssl rand -base64 32
//
// Sealed format: "v1." + base64(iv) + "." + base64(ciphertext)

const SEALED_PREFIX = "v1.";

function base64Encode(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}

function base64Decode(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export async function importSessionKey(rawBase64: string): Promise<CryptoKey> {
  const raw = base64Decode(rawBase64.trim());
  if (raw.length !== 32) {
    throw new Error("PAIRING_SESSION_KEY must be 32 bytes, base64-encoded (openssl rand -base64 32)");
  }
  return crypto.subtle.importKey("raw", raw.buffer as ArrayBuffer, "AES-GCM", false, [
    "encrypt",
    "decrypt",
  ]);
}

export async function sealSession(sessionID: string, key: CryptoKey): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    key,
    new TextEncoder().encode(sessionID),
  );
  return `${SEALED_PREFIX}${base64Encode(iv)}.${base64Encode(new Uint8Array(ciphertext))}`;
}

export function isSealed(value: string): boolean {
  return value.startsWith(SEALED_PREFIX);
}

export async function openSession(sealed: string, key: CryptoKey): Promise<string | null> {
  if (!isSealed(sealed)) return null;
  const parts = sealed.slice(SEALED_PREFIX.length).split(".");
  if (parts.length !== 2) return null;
  try {
    const iv = base64Decode(parts[0]);
    const ciphertext = base64Decode(parts[1]);
    const plaintext = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: iv.buffer as ArrayBuffer },
      key,
      ciphertext.buffer as ArrayBuffer,
    );
    return new TextDecoder().decode(plaintext);
  } catch {
    // Wrong key or corrupted record — treat as unrecoverable.
    return null;
  }
}
