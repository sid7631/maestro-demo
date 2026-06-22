# Maestro mobile test base

A config-driven [Maestro](https://maestro.mobile.dev) setup for UI-testing
multiple apps on **Android** (primary focus) and **iOS**, on macOS.

Flows are app-agnostic; each app supplies its own id and (optional) build via a
small config file. The same four commands — **run**, **debug**, **report**,
**inspect** — work for every app.

## Layout

```
config/
  global.env              Shared defaults (default platform, etc.)
  apps/<app>.env          Per-app config: APP_ID, platform, binary paths
flows/
  common/subflows/        Subflows shared by ALL apps (e.g. launch-app)
  <app>/config.yaml       Maestro workspace config for that app
  <app>/subflows/*.yaml   Reusable subflows shared within ONE app (e.g. login)
  <app>/<suite>/*.yaml    Test flows, grouped by suite (smoke, login, ...)
scripts/
  setup.sh                Install/verify tooling (Maestro, Allure, JDK, adb)
  run.sh                  Run a flow/suite -> JUnit results
  debug.sh                Iterate on one flow in continuous (auto-rerun) mode
  report.sh               Build & open an Allure HTML report
  inspect.sh              Maestro Studio / view-hierarchy dump
  keyboard.sh             Activate/restore ADBKeyboard for Android text input
  lib/common.sh           Shared helpers
binaries/                 Drop APK/.app builds here (gitignored)
reports/<app>/            Generated results & reports (gitignored)
```

## One-time setup

```bash
scripts/setup.sh
```

This checks for and installs (where possible via Homebrew): a JDK, the Maestro
CLI, and Allure. **Android** also needs the SDK — install Android Studio, then
an SDK + emulator (AVD), and put `platform-tools` (for `adb`) on your `PATH`.
**iOS** needs Xcode command line tools.

Start an Android emulator (or connect a device) before running.

## Daily use

```bash
# Run the whole suite for an app
scripts/run.sh app-one

# Run a suite or a single flow
scripts/run.sh app-one smoke
scripts/run.sh app-one smoke/app-launch.yaml

# Filter by tags / pick a device / target iOS
scripts/run.sh app-one --tags smoke
scripts/run.sh app-two --platform ios --device "iPhone 15"

# Iterate on a flow (auto-reruns on save)
scripts/debug.sh app-one smoke/app-launch.yaml

# Find selectors (ids/text) interactively
scripts/inspect.sh            # Maestro Studio
scripts/inspect.sh hierarchy  # dump current screen

# Build + open the Allure report for an app
scripts/report.sh app-one
```

## Flow structure (modularity)

Flows are layered so steps are written once and reused:

- **Common subflows** (`flows/common/subflows/`) — app-agnostic steps every app
  needs, e.g. `launch-app.yaml`. They use `appId: ${APP_ID}`, so they work for
  any app without change.
- **Per-app subflows** (`flows/<app>/subflows/`) — reusable steps specific to one
  app, e.g. `login.yaml`. Other tests for that app use them as preconditions.
- **Test flows** (`flows/<app>/<suite>/`) — thin orchestrators that `runFlow` the
  subflows and add the assertions for that scenario.

Example — `flows/naukri/login/login-with-password.yaml` composes:

```
runFlow common/subflows/launch-app.yaml   # launch (shared by all apps)
runFlow naukri/subflows/login.yaml        # login  (shared by naukri tests)
assertVisible "Jobs"                       # the scenario's own check
```

Pass data into a subflow with the `env:` form of `runFlow` (see the login test),
so subflows stay self-contained and parameterized.

## Adding a new app

1. `cp config/apps/app-one.env config/apps/<your-app>.env` and set `APP_ID`,
   `PLATFORM`, and binary paths.
2. `mkdir -p flows/<your-app>/smoke` and add flows. Use `appId: ${APP_ID}` (not
   a hardcoded id) so flows stay portable across apps.
3. Drop the build in `binaries/` if you want the runner to install it; otherwise
   leave the binary path blank and the app is assumed already installed.
4. Run it: `scripts/run.sh <your-app>`.

## How app binaries work

Per app, per platform you set a binary path in `config/apps/<app>.env`:

- **Path set & file present** → the runner installs it (`adb install -r` /
  `simctl install`) before the flows.
- **Path blank or file missing** → install is skipped and flows just
  `launchApp` by id (the app must already be on the device).

Use `--no-install` on `run.sh`/`debug.sh` to skip installation for a run.

## Android text input — troubleshooting

If `inputText` seems to "do nothing" (the field focuses, keyboard appears, but
no text lands), check these **first** — they're the usual causes:

1. **Empty variable.** `inputText: ${USERNAME}` types nothing if the variable is
   empty. Confirm the value is set (e.g. in `config/apps/<app>.local.env`) and
   that an `env:` block in the flow isn't overriding it with a blank default —
   empty `env` defaults shadow values forwarded from the runner.
2. **Field not focused.** The `tapOn` before `inputText` must focus the actual
   input — target it by `id` (from `inspect.sh`), not by hint text. Quick check:
   type a literal string and see if it lands.

Only if those are fine and Maestro still can't type **special/non-ASCII
characters** is it the ADB limitation (`adb shell input text` handles plain ASCII
only). The optional fallback is **ADBKeyboard**, an IME that receives text over
broadcast intents. It is **not** activated automatically — enable it when needed:

```bash
scripts/keyboard.sh use-adb   # install + enable + activate ADBKeyboard
scripts/keyboard.sh restore   # switch back to your normal keyboard afterwards
scripts/keyboard.sh status    # show the currently active input method
```

`use-adb` saves your current keyboard (under `reports/state/`) so `restore` puts
it back. While active you'll see ADBKeyboard's minimal UI on the device.

## Reporting

`run.sh` writes JUnit XML into `reports/<app>/allure-results/`. `report.sh`
runs `allure generate` over that folder, preserving previous history so Allure
shows **trends** across runs, then opens the HTML report. Per-step screenshots
and logs for a run are kept under `reports/<app>/debug/<timestamp>/`.

## Notes

- CI is intentionally out of scope for now; everything runs locally on macOS.
  The scripts take no Mac-specific shortcuts beyond setup, so wiring them into
  CI later is mostly "boot an emulator, then call `run.sh` + `report.sh`".
