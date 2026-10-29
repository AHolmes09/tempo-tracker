# Tempo

A Flutter time tracker with two pages:

- **Time tracker:** clock in/out, an optional work label, live elapsed time, today's sessions, and daily/weekly/monthly totals.
- **Calendar:** monthly grid with a total for every day, monthly totals, and a scrollable 24-hour day view with work blocks positioned at their recorded times. Double-click empty timeline space (or press and hold on a phone) to create a labeled work session. Drag completed blocks to snap their start to five-minute marks while preserving duration, drag either edge to resize to an exact five-minute mark, or tap for exact date/time editing and deletion. Running sessions must be clocked out before editing. Sessions can also be deleted from Today’s sessions. Edits cannot overlap other sessions or extend into the future.

Web sessions are stored in IndexedDB. Existing SharedPreferences web data is migrated on first load at the same origin; the old key is removed only after a successful database commit. Native Flutter builds continue to use SharedPreferences. There is no account, cloud sync, or external backup.

The web app requests persistent storage on first interaction. Browsers decide whether to grant it; it does not prevent deliberate website-data deletion. Clearing cookies alone does not remove IndexedDB, but Safari's website-data clearing can. Data is specific to a device/browser and origin: moving from localhost to hosting, or changing domains, does not transfer sessions.

An active clock-in survives reopening. Durations measure actual elapsed time, including overnight sessions.

## Run

```sh
flutter pub get
flutter run
```

For a browser: `flutter run -d chrome`.

## Verify

```sh
flutter analyze
flutter test
python3 tool/build_web.py
```

## Offline release and hosting

Run `python3 tool/build_web.py` for every release, then deploy the entire `build/web` directory to an HTTPS static host (for example Cloudflare Pages). The script builds local rendering assets and a content-versioned service worker that precaches the app. A plain `flutter build web` does **not** prepare the custom offline release.

Visit once online and let the offline installation finish before disconnecting. An updated release activates after old app windows close; reload/reopen to use it. Updating the app cache never deletes the IndexedDB session database. The supplied `_headers` file configures revalidation on Cloudflare Pages.

On iPhone, open the hosted address in Safari and use Share → Add to Home Screen. Offline behavior and persistence grants should also be checked on the actual iPhone; automated browser validation currently covers desktop Chrome only.

Browser regression check (requires Playwright and Chrome, with the release served on port 8080): `node tool/test_web.cjs`. It uses an isolated browser profile and verifies migration, cookie clearing, offline reload, and offline writes.

## GitHub Pages

The included GitHub Actions workflow builds and deploys the app to Pages. Set the repository's Pages source to **GitHub Actions**. It uses the repository path for a project site and `/` for a `<owner>.github.io` repository. For a local build at a project path, run `python3 tool/build_web.py --base-href /REPOSITORY/` (including both slashes).

GitHub Pages does not use the Cloudflare `_headers` file. The app's offline cache and session database remain separate, but browser storage can still be removed. Sessions stay on the device and do not automatically move between hosting addresses or browsers.
