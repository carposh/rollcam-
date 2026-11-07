// Undeveloped frames are AES-GCM encrypted with a non-extractable key kept in IndexedDB.
import * as db from './db.js';

let keyPromise;

function key() {
  if (!keyPromise) {
    keyPromise = (async () => {
      let k = await db.get('meta', 'vaultKey');
      if (!k) {
        k = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
        await db.set('meta', 'vaultKey', k);
      }
      return k;
    })();
  }
  return keyPromise;
}

export async function seal(buffer) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const data = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await key(), buffer);
  return { iv, data };
}

export async function open(sealed) {
  return crypto.subtle.decrypt({ name: 'AES-GCM', iv: sealed.iv }, await key(), sealed.data);
}
