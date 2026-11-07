// Tiny IndexedDB wrapper. Stores: rolls (keyPath id), blobs (ArrayBuffers), meta (vault key).
let dbPromise;

function openDB() {
  if (!dbPromise) {
    dbPromise = new Promise((resolve, reject) => {
      const req = indexedDB.open('rollcam', 1);
      req.onupgradeneeded = () => {
        const db = req.result;
        db.createObjectStore('rolls', { keyPath: 'id' });
        db.createObjectStore('blobs');
        db.createObjectStore('meta');
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  }
  return dbPromise;
}

function run(storeName, mode, fn) {
  return openDB().then((db) => new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, mode);
    const request = fn(tx.objectStore(storeName));
    tx.oncomplete = () => resolve(request ? request.result : undefined);
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error);
  }));
}

export const getAll = (store) => run(store, 'readonly', (s) => s.getAll());
export const get = (store, key) => run(store, 'readonly', (s) => s.get(key));
export const put = (store, value) => run(store, 'readwrite', (s) => s.put(value));
export const set = (store, key, value) => run(store, 'readwrite', (s) => s.put(value, key));
export const del = (store, key) => run(store, 'readwrite', (s) => s.delete(key));
export const delPrefix = (store, prefix) =>
  run(store, 'readwrite', (s) => s.delete(IDBKeyRange.bound(prefix, prefix + '￿')));
