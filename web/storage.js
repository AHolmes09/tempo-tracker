// Session data is separate from the app-shell cache. Cache updates never erase it.
(() => {
  const database = new Promise((resolve, reject) => {
    const request = indexedDB.open('tempo', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('settings');
    request.onsuccess = () => {
      request.result.onversionchange = () => request.result.close();
      resolve(request.result);
    };
    request.onerror = () => reject(request.error);
    request.onblocked = () => reject(new Error('Close other Tempo tabs and retry.'));
  });
  // Keep failures observable by callers without an unhandled startup rejection.
  database.catch(() => {});
  const transaction = async (mode, action) => {
    const db = await database;
    return new Promise((resolve, reject) => {
      const tx = db.transaction('settings', mode);
      const request = action(tx.objectStore('settings'));
      tx.oncomplete = () => resolve(request.result ?? null);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error ?? new Error('Storage transaction aborted'));
    });
  };
  const validate = data => {
    const sessions = JSON.parse(data);
    if (!Array.isArray(sessions) || sessions.some(s =>
      typeof s.label !== 'string' || !Number.isFinite(Date.parse(s.start)) ||
      (s.end !== null && !Number.isFinite(Date.parse(s.end))))) {
      throw new Error('Invalid saved sessions');
    }
  };
  window.tempoStorage = {
    async read() {
      const current = await transaction('readonly', store => store.get('sessions'));
      if (current !== null) return current;
      // SharedPreferences used this localStorage key in the original web app.
      const legacy = localStorage.getItem('flutter.tempo.sessions.v1');
      if (legacy === null) return null;
      validate(legacy);
      await this.write(legacy); // Only migrate after the database commit succeeds.
      localStorage.removeItem('flutter.tempo.sessions.v1');
      return legacy;
    },
    async write(data) {
      validate(data);
      await transaction('readwrite', store => store.put(data, 'sessions'));
    },
    async requestPersistence() {
      try {
        if (!navigator.storage?.persist) return false;
        return await navigator.storage.persisted() || await navigator.storage.persist();
      } catch (_) { return false; }
    }
  };
  // A user gesture gives browsers the opportunity to grant persistent storage.
  document.addEventListener('pointerdown', () => window.tempoStorage.requestPersistence(), {once: true});
})();
