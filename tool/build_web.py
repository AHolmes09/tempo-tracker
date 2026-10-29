"""Build a self-contained Flutter web release and version its offline cache."""
import hashlib
import argparse
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--base-href', default='/', help='Public URL path, starting and ending with /')
args = parser.parse_args()
if not args.base_href.startswith('/') or not args.base_href.endswith('/') or args.base_href.startswith('//'):
    parser.error('--base-href must be an absolute path starting and ending with /')
subprocess.run(['flutter', 'build', 'web', '--no-web-resources-cdn', '--pwa-strategy=none',
                f'--base-href={args.base_href}'], check=True)
root = Path('build/web')
(root / '_headers').write_text(Path('web/_headers').read_text())
files = sorted(p for p in root.rglob('*') if p.is_file()
               and not any(part.startswith('.') for part in p.relative_to(root).parts)
               and p.name not in {'tempo-sw.js', 'flutter_service_worker.js', '_headers'})
version = hashlib.sha256(b''.join(p.relative_to(root).as_posix().encode() + p.read_bytes() for p in files)).hexdigest()[:16]
assets = [p.relative_to(root).as_posix() for p in files]
worker = '''
const CACHE = 'tempo-shell-VERSION';
const ASSETS = ASSET_LIST;
self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    await cache.addAll(ASSETS.map(path => new Request(new URL(path, self.registration.scope), {cache: 'reload'})));
  })());
});
// Updated releases wait until old app windows close, avoiding mixed versions.
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if ((key.startsWith('tempo-shell-') && key !== CACHE) || key.startsWith('flutter-')) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET' || new URL(event.request.url).origin !== self.location.origin) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const key = event.request.mode === 'navigate' ? new URL('index.html', self.registration.scope).href : event.request;
    return (await cache.match(key)) || fetch(event.request);
  })());
});
'''.replace('VERSION', version).replace('ASSET_LIST', json.dumps(assets))
(root / 'tempo-sw.js').write_text(worker)
print(f'Offline release ready: {len(assets)} assets, version {version}')
