# Agent handoff: running this app in the cloud

This repository is a test copy of
[Ahmed7773333/Hojaty-v2](https://github.com/Ahmed7773333/Hojaty-v2), a Flutter
app (iOS and Android). All credit for the app goes to its author; the copy has
no license, so keep it for testing and do not publish changes from it.

**Nothing is installed on this Mac for Flutter, Xcode simulators, or the Android
SDK, and it should stay that way.** Do not install them. Every build and every
run happens on GitHub Actions, and the person uses the app through Appetize in
the browser.

- Local copy: `~/Documents/ui-test-projects/Hojaty-v2`
- GitHub: `Mohanad-Ramadan/Hojaty-v2` (public, so Actions minutes are free)
- Branch: **`dev`** is the live app and the default branch. `main` is an old
  first commit; ignore it.

## What runs

`.github/workflows/cloud-run.yml`, on every push to `dev`, or by hand:

| Job | Runner | What it does |
|---|---|---|
| `ios` | `macos-latest` (Xcode and simulators preinstalled) | `flutter build ios --simulator --debug`, boots an iPhone simulator, installs, grants location, launches, screenshots, records |
| `android` | `ubuntu-latest` with KVM | `flutter build apk --debug`, boots a Pixel 7 emulator (API 35), installs, grants location and notifications, launches, screenshots, records |

Each job then builds Release, and, when asked, checks that given strings are
absent from it. The device location is set to Mecca so prayer times have data.
A run takes about 12 to 15 minutes.

## The loop

```sh
cd ~/Documents/ui-test-projects/Hojaty-v2
git push origin dev                     # runs both jobs with default inputs

# or by hand, with inputs:
gh workflow run cloud-run.yml --ref dev \
  -f platforms=both \
  -f dart_defines="SOME_FLAG=true OTHER=1" \
  -f wait_seconds=25 \
  -f log_filter="SOME_TAG" \
  -f release_forbidden="DebugOnlyClass some-debug-string"

gh run list --workflow cloud-run.yml --limit 1      # the run id
gh run watch <run-id> --exit-status
gh run download <run-id> --dir results/<run-id> -p '*-results'
```

Run `gh run watch` in the background: a run outlasts a two-minute command
timeout. A push that only changes docs still starts a run; cancel it with
`gh run cancel <run-id>` if it is not needed.

| Input | Default | Meaning |
|---|---|---|
| `platforms` | `both` | `both`, `ios`, or `android` |
| `dart_defines` | empty | space-separated `KEY=VALUE`, each passed as `--dart-define` to every build |
| `wait_seconds` | `25` | delay before the second screenshot |
| `log_filter` | empty | text to pull out of the logs into `filtered-log.txt` |
| `release_forbidden` | empty | strings that must not appear in the release binaries; empty skips the check |

Artifacts `ios-results` and `android-results` each contain:

| File | Use |
|---|---|
| `01-launch.png`, `02-after-<n>s.png` | look at these to see the screen |
| `run.mp4` | about a minute of the screen from launch |
| `app-log.txt` (and `logcat.txt` on Android) | the app's log, for crashes and `debugPrint` |
| `filtered-log.txt` | lines containing `log_filter`, when given |
| `release-check.txt` | PASS, FOUND (with the binary), or SKIPPED |
| `Runner-simulator.zip` / `app-debug.apk` | the debug builds Appetize runs |

`results/` is git-ignored. Downloads are large (the APK is about 190 MB); delete
old `results/<run-id>` folders when done with them.

## Things to know about this app

- Every run is a fresh install, so the app opens on onboarding (the language
  picker). CI cannot tap. To show a deeper screen in CI, add debug-only startup
  code (under `kDebugMode`, driven by a `--dart-define`) that skips onboarding
  or routes there. Otherwise the person taps through it in Appetize.
- On Android, the Quran and hadith books are Play Asset Delivery packs
  (on-demand), which a plain debug APK does not contain, so those reader screens
  are empty on the emulator and in Appetize's Android build. Use iOS for them.
- The app uses Hive, Awesome Notifications, and Firebase Messaging, but needs no
  Firebase config or secrets to build or launch.
- `telegram_deploy.yml` (the author's Play Store and Telegram deploy) is
  disabled in this copy. Leave it disabled.
- A cold emulator can raise "isn't responding" dialogs; `ci/android-run.sh`
  already hides them. If one still shows in a screenshot, rerun.

## Appetize: letting the person use the app

CI only produces screenshots and recordings. To **touch** the app (tap, type,
scroll) on a real iOS simulator and Android emulator in the browser, the
workflow uploads each debug build to [Appetize](https://appetize.io). This needs
a one-time setup by the person; walk them through it when they want to
interact.

### One-time setup (the person does this)

1. Sign up at <https://appetize.io> (free plan; no card needed). The free plan
   has a small monthly allowance of session minutes and a short session length,
   so close the tab when done.
2. In the Appetize dashboard: **Organization → API Token**, create a token, and
   copy it. Only an organization admin can create one; the account owner is.
3. Store it as a repository secret. The person runs this and pastes the token
   when prompted, so it never appears in chat or in shell history:

   ```sh
   gh secret set APPETIZE_API_TOKEN --repo Mohanad-Ramadan/Hojaty-v2
   ```

   Never ask the person to paste the token into chat, and never write it into
   a file.

### After setup (the agent does this)

1. Start a run (push or `gh workflow run`). With the secret present, each job
   ends with an "Upload to Appetize" step, and the run's summary page shows a
   link per platform: `Appetize (ios): https://appetize.io/app/<key>`.
   Read them with `gh run view <run-id> --log | grep "Appetize ("`.
2. The first upload creates a new Appetize app and prints its public key.
   Save each key as a repository variable, so later runs update the same app
   and the person's links stay the same:

   ```sh
   gh variable set APPETIZE_IOS_KEY --body <ios-key> --repo Mohanad-Ramadan/Hojaty-v2
   gh variable set APPETIZE_ANDROID_KEY --body <android-key> --repo Mohanad-Ramadan/Hojaty-v2
   ```

3. Give the person both links. They open one while signed in to Appetize, press
   **Tap to play**, and use the app with the mouse and keyboard. Device, OS
   version, and orientation are in the page's settings.

### Reading what happened in an Appetize session

The agent cannot see an Appetize session or its log. When the person needs to
report something from the app (an error, a value the app logged), ask them to
open the session's **debug log** on the Appetize page (the logs toggle beside
the device), copy the relevant lines, and paste them in chat.

### If uploads fail

- `401` or `403`: the token is wrong or was revoked; the person sets it again.
- A `404` on update: a saved `APPETIZE_*_KEY` points to a deleted app; remove the
  variable (`gh variable delete APPETIZE_IOS_KEY --repo ...`) and rerun to
  create a new one.
- The upload step is skipped: the secret is not set.
- Out of minutes: the free allowance resets monthly; screenshots and recordings
  from CI still work without Appetize.
