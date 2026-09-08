# Bagad Billa 🐾

A fluffy, slightly grumpy macOS desktop cat that looks at your cursor, types alongside you, wears headphones, plays, naps, and reminds you to walk.

**Author: GOPAL GOYAL**  
**Co-author: SAKSHAM BATTA**

![Headphones, typing, box, and petting](docs/features-preview.png)

## Requirements

- macOS 13 or later. Developed and tested on Apple Silicon; the build script targets the current Mac's architecture. Intel builds have not been tested.
- Apple Xcode Command Line Tools (`xcode-select --install`).
- No third-party packages, API keys, accounts, or network services are needed at runtime.

## Build and run

```bash
git clone https://github.com/gopalgoyal2002/bagad-billa.git
cd bagad-billa
./scripts/build.sh
./scripts/run.sh
```

You can also double-click `build/Bagad Billi.app` in Finder. The app appears as a floating cat with a paw icon in the menu bar, without a Dock icon. Keep the full app bundle together. Quit an existing copy before rebuilding or running a copy from another location.

The script compiles Swift against AppKit, ApplicationServices, and CoreAudio, packages all sprite frames, and applies a local ad-hoc signature. This is not a notarized distribution. Building on your own Mac is the supported setup; downloaded binaries may require macOS approval.

To rebuild after changes, quit the cat, run `./scripts/build.sh`, then `./scripts/run.sh`. macOS may require renewing Accessibility permission after a rebuild or moving the app.

## Enable typing detection

1. Right-click the cat and leave **Typing reactions** checked.
2. Choose **Open keyboard permission settings…**.
3. In System Settings → Privacy & Security → Accessibility, add the exact `build/Bagad Billi.app` you launched and enable it.
4. Type in a normal text editor. The menu's typing status indicates whether permission is missing, it is waiting for keys, or it has received keys.

Permission is checked every second. Relaunch if macOS requests it. If the switch is on but the menu still says permission is needed, remove the old Accessibility entry with **−**, add the current app with **+**, and enable it. A prior build's authorization may no longer match.

**Preview typing** tests the animation without keyboard permission. Secure-input/password fields may suppress keyboard events. “Receiving keys” means this session has received keyboard activity, not necessarily that keys are being pressed at that instant.

## Features and controls

Right-click the cat or click the menu-bar paw to access all controls.

- **Cursor tracking:** sixteen gaze directions, with a neutral blink when the cursor is close to its face. Pause/resume tracking from the menu.
- **Typing:** alternating paws and a little keyboard; faster typing produces faster taps and “Turbo paws”. Returns to normal after 0.7 seconds without detected keys. Typing interrupts temporary petting/stretch animations and appears during focus; a short active chase/pounce finishes first.
- **Click and drag:** click to wave, double-click to jump, drag to reposition. Position is saved. Small/Large changes size; Reset position brings the cat to the visible screen.
- **Petting:** rub the pointer across its head for closed eyes and a heart. Pet Bagad Billa triggers it manually.
- **Treats:** Give a fish treat, then click the fish for a short pounce and return. Unused fish disappear after 20 seconds.
- **Sleep:** automatic nap after 3 minutes without mouse movement or detected typing; movement/typing wakes it. Nap now is available. Music mode prevents automatic idle naps.
- **Cursor play:** occasional short chases when the moving cursor is nearby, with at least 75 seconds between automatic attempts. Disable Occasional cursor play or trigger Play with cursor manually.
- **Walking reminders:** enabled by default, every 20 minutes while running. “Stand up & take a short walk” displays for 30 seconds, including during focus and pet naps. Preview walk reminder triggers it immediately. Toggle reminders in the menu.
- **Stretch reminders:** every 30 minutes while awake, with a brief paw-up animation. Focus and sleep defer these reminders. Stretch now is available.
- **Focus:** start 25-minute or 5-minute sessions, or try a 10-second preview. The cat naps, shows a countdown, and jumps when done. Cancel from the menu.
- **Homes:** choose a cushion, cardboard box, or no home. The cat settles lower in its box during sleep/petting.
- **Headphones:** automatic mode checks whether the default audio output device is active. It cannot distinguish music from notifications, silent streams, or apps keeping audio open. Manual music mode works with any player. Head bobbing is decorative, not synchronized to beats; headphones also work during typing.
- **Sounds:** optional synthesized purr and completion/reminder chime. Sounds and purring is off by default.

## Timing, preferences, and limitations

The companion must be running for reminders. There are no scheduled background jobs or automatic login startup items. Restarting begins fresh countdowns; missed walk reminders do not queue up. Re-enabling walk reminders starts a fresh 20 minutes. Focus timing uses system uptime and is not intended as an alarm while the Mac is asleep.

Position, typing toggle, automatic nap/play/reminder toggles, sound preference, home, and automatic audio mode use macOS UserDefaults. Size, manual headphones, cursor pause, and active focus timers are session-only.

If the cat is hidden, use **paw menu → Reset position**. If you see two cats, quit the other standalone copy or hide the separate Codex pet. This app currently has no single-instance enforcement across different bundle copies.

## Privacy

The keyboard handlers observe event timing only: they do not read characters/key codes, record typed text, or send it anywhere. Turning typing reactions off removes the keyboard monitors. Cursor tracking reads pointer coordinates. Audio detection reads device-running state; it does not use the microphone or record audio. Preferences stay on the Mac. Runtime code does not make network requests.

## Tests and visual preview

```bash
./scripts/test.sh
"build/Bagad Billi.app/Contents/MacOS/BagadBilli" --render-gallery "$PWD/build/features-preview.png"
```

Tests cover sixteen directions, compass/deadzone cases, typing expiry and cadence/storage, sleep/wake, focus completion, reminder timing and disabled behavior, excursion return, and sprite availability. Gallery rendering requires a logged-in macOS GUI session. Real cross-app typing requires user-granted Accessibility permission; deterministic tests do not prove that system permission is granted.

Optional startup diagnostics (no typed text):

```bash
# Quit the running cat first.
open "build/Bagad Billi.app" --args --diagnostics "$PWD/build/typing-diagnostics.txt"
```

This records permission, enabled state, and monitor installation at startup; it is not a live-updating report.

## Source layout

- `Sources/main.swift`: native AppKit window, rendering, input monitoring, behavior state, audio-state detection, and self-tests.
- `Resources/frames/`: all animation and directional PNG frames.
- `Resources/Info.plist`: application metadata.
- `scripts/`: reproducible build, run, and test commands.
- `docs/features-preview.png`: rendered feature examples.
- `codex-pet/`: original v2 Codex pet manifest and sprite atlas, separate from the standalone application.

The Codex sprite package does not implement this app's global cursor/keyboard interactions or timers. The standalone Swift app supplies those behaviors. Build products, local diagnostics, temporary generation files, and caches are excluded from version control.

See [AUTHORS.md](AUTHORS.md) for credits.

## Contribution and approval policy

All changes to `main` require a pull request, code-owner approval, passing macOS checks, and resolved review conversations. Direct pushes, force pushes, and branch deletion are blocked by repository protection, including for administrators. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

This repository is publicly readable; public visibility permits viewing and forking, not editing this repository. Its owner can manage access and change protection settings. No open-source license has been selected for this project.

Headphone fit uses per-direction ear anchors and the same drawing transform as the cat, including breathing and box settling. Profile views hide the far ear cup. Headphones temporarily hide during action sprites without fitted anchors and return for idle, gaze, and typing poses.
