// Optionally pass the app URL to test a release hosted under a path prefix.
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
(async () => {
  const browser = await chromium.launch({channel: 'chrome', headless: true});
  try {
    const context = await browser.newContext();
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    const legacy = JSON.stringify([{start: '2026-01-05T08:07:00.000', end: null, label: 'Migrated active session'}]);
    await context.addInitScript(data => {
      if (!localStorage.getItem('migration-test-seeded')) {
        localStorage.setItem('flutter.tempo.sessions.v1', data);
        localStorage.setItem('migration-test-seeded', 'yes');
      }
    }, legacy);
    await page.goto(process.argv[2] || 'http://127.0.0.1:8080/');
    await page.waitForFunction(() => window.tempoStorage);
    assert.equal(await page.evaluate(() => tempoStorage.read()), legacy);
    assert.equal(await page.evaluate(() => localStorage.getItem('flutter.tempo.sessions.v1')), null);
    // Wait for the complete app shell to be installed before disconnecting.
    await page.evaluate(() => navigator.serviceWorker.ready);
    await page.waitForFunction(() => navigator.serviceWorker.controller);
    await page.waitForSelector('flutter-view');
    await context.clearCookies();
    await page.reload();
    assert.equal(await page.evaluate(() => tempoStorage.read()), legacy);
    await context.setOffline(true);
    await page.reload();
    await page.waitForSelector('flutter-view');
    assert.equal(await page.evaluate(() => tempoStorage.read()), legacy);
    await page.evaluate(() => tempoStorage.write('[]'));
    await page.reload();
    assert.equal(await page.evaluate(() => tempoStorage.read()), '[]');
    assert.deepEqual(errors, []);
    console.log('PASS: migration, cookie clearing, offline app reload, offline writes and reload, no browser errors');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
