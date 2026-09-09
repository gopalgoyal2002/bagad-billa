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
- **Cursor play:** occasional short chases when the moving cursor is nearby, with 45 to 150 seconds between automatic attempts depending on mood. Disable Occasional cursor play or trigger Play with cursor manually.
- **Walking reminders:** enabled by default, every 20 minutes while running. “Stand up & take a short walk” displays for 30 seconds, including during focus and pet naps. Preview walk reminder triggers it immediately. Toggle reminders in the menu.
- **Stretch reminders:** every 30 minutes while awake, with a brief paw-up animation. Focus and sleep defer these reminders. Stretch now is available.
- **Focus:** start 25-minute or 5-minute sessions, or try a 10-second preview. The cat naps, shows a countdown, and jumps when done. Cancel from the menu.
- **Homes:** choose a cushion, cardboard box, or no home. The cat settles lower in its box during sleep/petting.
- **Headphones:** automatic mode checks whether the default audio output device is active. It cannot distinguish music from notifications, silent streams, or apps keeping audio open. Manual music mode works with any player. Head bobbing is decorative, not synchronized to beats; headphones also work during typing.
- **Wardrobe:** the **Wardrobe** submenu dresses the cat in sunglasses (light frames, translucent teal tint), a monocle, a bow tie, a knit scarf, and one hat at a time: party hat, crown, Santa hat, witch hat, or nightcap. Everything follows all sixteen gaze directions and idle poses, stays on while typing, napping, and being petted, and can be worn with headphones. Accessories hide briefly during wave, jump, chase, and other action sprites. Choices are remembered. **Seasonal hats** (on by default) add a Santa hat from 1 to 26 December and a witch hat from 24 to 31 October using the Mac's clock, unless you picked a hat yourself.
- **Bedtime:** pick 10 PM, 11 PM, midnight, or 1 AM under **Bedtime nightcap and nudge**. From then until 5 AM the cat wears a nightcap and, while awake, yawns and says "It's late. Go to bed." every 20 minutes. Off by default.
- **Mood:** a 0 to 100 mood shown in the menu drifts down one point every ten minutes and rises with petting, treats, water, yarn, laser play, and finished focus sessions. Delighted cats chase the cursor more often, neglected ones less; a neglected cat grumbles "Hmph." now and then and says "Took you long enough." when you finally pet it. Mood is saved and keeps decaying while the app is closed, capped at 40 points lost.
- **Laser pointer:** **Laser pointer for 30 seconds** makes the cat run after the cursor wherever it goes, then stop and save its new spot.
- **Yarn ball:** **Toss a yarn ball** throws a ball that rolls, slows, and bounces off screen edges. The cat walks over and bats it four times, then loses interest. Click the ball to kick it yourself.
- **Strolls:** **Occasional strolls along the screen** lets the cat wander to a new spot along its row every 25 to 35 minutes when nothing else is happening. Off by default because it moves the saved position.
- **Water and eye rest:** **Water reminders every 45 minutes** put a bowl beside the cat; click it and the cat walks over to drink. **Eye rest every 20 minutes** makes the cat stare into the distance for 20 seconds with a countdown so you can follow the 20-20-20 rule. Both are off by default, defer during focus and naps, and have preview items.
- **Focus stats:** the menu shows how many focus sessions of five minutes or longer finished today. The count resets at midnight.
- **Work reactions:** with the zsh integration below, failed commands get the thinking pose, long successes get a jump, five successes in a row earn a dance, and git pushes, commits, and merges are celebrated. In the pet's own terminal tabs, a terminal bell makes the cat wave at you.
- **Sounds:** optional synthesized purr and completion/reminder chime. Sounds and purring is off by default.

## Timing, preferences, and limitations

The companion must be running for reminders. There are no scheduled background jobs or automatic login startup items. Restarting begins fresh countdowns; missed walk reminders do not queue up. Re-enabling walk reminders starts a fresh 20 minutes. Focus timing uses system uptime and is not intended as an alarm while the Mac is asleep.

Position, typing toggle, automatic nap/play/reminder toggles, water and eye-rest toggles, strolls, sound preference, home, wardrobe, seasonal hats, bedtime, mood, the daily focus count, and automatic audio mode use macOS UserDefaults. Size, manual headphones, cursor pause, and active focus timers are session-only.

If the cat is hidden, use **paw menu → Reset position**. If you see two cats, quit the other standalone copy or hide the separate Codex pet. This app currently has no single-instance enforcement across different bundle copies.

## Privacy

The keyboard handlers observe event timing only: they do not read characters/key codes, record typed text, or send it anywhere. Turning typing reactions off removes the keyboard monitors. Cursor tracking reads pointer coordinates. Audio detection reads device-running state; it does not use the microphone or record audio. Preferences stay on the Mac. Runtime code does not make network requests.

## Tests and visual preview

```bash
./scripts/test.sh
"build/Bagad Billi.app/Contents/MacOS/BagadBilli" --render-gallery "$PWD/build/features-preview.png"
"build/Bagad Billi.app/Contents/MacOS/BagadBilli" --render-wardrobe "$PWD/build/wardrobe-preview.png" sunglasses,bowtie,partyHat
```

Tests cover sixteen directions, compass/deadzone cases, typing expiry and cadence/storage, sleep/wake, focus completion, reminder timing and disabled behavior, excursion return and pursuit, sprite availability, wardrobe anchors for every idle and gaze pose, terminal reaction messages and streaks, mood decay and labels, bedtime and seasonal date logic, and yarn physics. The wardrobe render takes a comma-separated list of outfit names (sunglasses, monocle, bowtie, scarf, partyHat, crown, santaHat, witchHat, nightcap) and shows the sixteen gaze poses plus the six idle frames wearing them, with headphones on the idle frames. Gallery rendering requires a logged-in macOS GUI session. Real cross-app typing requires user-granted Accessibility permission; deterministic tests do not prove that system permission is granted.

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

Wardrobe items reuse those anchors. Sunglasses and the monocle use per-pose lens anchors for the sixteen gaze poses and six idle frames; three-quarter poses narrow the far lens and profile poses show a single lens with a temple arm toward the ear. The bow tie and scarf sit a fixed distance below the eyes and drift toward the body's center line as the head turns. Hats sit midway between the ear anchors, and the pet view keeps extra room above the sprite so tall hats are not clipped. Everything shares the cat's breathing and box-settling transform and hides during the same action sprites as headphones.

## Terminal notifications (zsh)

Source the integration from your `~/.zshrc`, using the absolute path to this checkout:

```zsh
source /absolute/path/to/bagad-billa/integrations/bagad-billa.zsh
```

Open a new terminal tab, or run that source command in an existing zsh tab. This works in IDE terminals that start interactive zsh and load that configuration, as well as standalone terminals. Bash, fish, remote hosts, containers, and IDE task runners that do not load this shell configuration are not automatically covered.

Failures are reported when the shell returns to its prompt. Successful commands are reported if they ran for at least three seconds. The cat reacts as well: a failure gets the thinking pose and "That's on you."; a success that ran ten seconds or longer gets a jump and "Finally."; every fifth success in a row earns a short dance and "5 in a row. Show-off."; and a successful `git push`, `git commit`, or `git merge` is reported as a milestone with a dance. Reactions also nudge the cat's mood. For explicit input/approval requests, run `bagad-help` before the waiting operation. Arbitrary prompts are not inferred from terminal output. A foreground command still running cannot automatically report its own need for input unless it explicitly integrates this signal.

The cat displays an alert for 12 seconds and retains the latest 12 alerts under Recent terminal activity. Terminal notifications can be disabled in its menu. Alerts identify the terminal device (for example ttys001); exact IDE-tab activation is not implemented.

Only event kind, numeric exit code, elapsed seconds, timestamp, terminal device label, and coarse terminal application category are written locally. No command text, arguments, working directory, terminal output, or credentials are captured. To recognize git milestones, the hook checks inside your shell whether the command line began with `git push`, `git commit`, or `git merge`; the command line itself is never written anywhere. Events use private files under `~/Library/Application Support/BagadBilli/events`, overwritten per shell process. The companion reads bounded files once per second and ignores stale events. Very rapid events from the same shell can be coalesced. This is a local convenience notification channel, not a security audit log; another process running as your user can write to it.

Try `sleep 3`, then `false`, then `bagad-help`, then a real `git commit` for the dance. To uninstall, remove the source line from `.zshrc` and start fresh terminal tabs. Existing tabs retain their hooks until closed. The integration does not execute commands on your behalf.

## Terminals above the pet

The Agent Desk, process scan, connected-agent cards, and personal-assistant/AI chat have been removed. Terminal Desk opens above the pet on startup. Click the cat, or use **Open terminals** in its menu, to reopen it. The title shows the number of open tabs. Each tab is an independent terminal; switch tabs to view its output.

- Type `claude` normally, just as in another terminal. No special launcher is needed for using Claude here.
- **+ Terminal** starts another independent zsh session in your home folder.
- **+ In folder…** lets you choose the working directory for a new tab.
- Drag a window edge to resize, or click **Expand** to zoom. Shell rows/columns update with the view.
- Use the tabs to switch between sessions. **Copy** copies selected terminal text; **Paste** uses the terminal's paste handling.
- Closing the terminal window hides it and keeps sessions running. Click the cat to reopen it.
- **End tab** asks before closing its shell. Quitting the pet closes all of its terminal sessions. Commands may be interrupted; save your work first.
- When a program in a pet tab rings the terminal bell, for example Claude Code waiting at a permission prompt, the cat waves and shows "Terminal 2 needs you" for ten seconds, unless that tab is already selected in the frontmost Terminal Desk window. Bells are limited to one reaction every eight seconds and follow the **Terminal notifications** toggle. The bell byte is the only terminal output the pet inspects.

This is an interactive zsh terminal, not an AI command interpreter. Commands you type have your normal account access and run immediately, just like a normal terminal. The app neither auto-approves Claude prompts nor supplies commands on your behalf. Your ordinary shell startup files and history settings apply. Embedded terminal scrollback stays in memory (3,000 lines); it is not added to a separate pet transcript. Existing optional bagad-claude launcher sessions still work separately.

Rendering uses locally bundled xterm.js 5.5.0 and addon-fit 0.10.0, with their MIT licenses in Resources/terminal. No CDN or local network server is used. A Python helper owns each pseudo-terminal over private process pipes. The web view is limited to its bundled page, blocks network content, and receives output as bytes rather than HTML. Python and WebKit are needed at runtime, in addition to the macOS requirements above.

Tests: `PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 tests/test_terminal_host.py` verifies shell execution, resize, Ctrl-C, tab isolation, and shutdown using harmless commands. A logged-in GUI session can run `"build/Bagad Billi.app/Contents/MacOS/BagadBilli" --terminal-smoke "$PWD/build/terminal-preview.png"` to verify real shell output reaches the embedded renderer. These tests require PTY access.

## Gemini Live voice for pet terminals

Click **Voice** in Terminal Desk. Enter a Gemini API key in the secure field (never in source code or chat), keep the suggested Live model or enter one available to your account, and click **Start voice**. Grant macOS microphone permission when asked. The key is saved in macOS Keychain, not preferences, source, or logs. Use **Forget saved key** in voice settings to remove it. macOS may request Keychain access after an app update. Google API billing/quota applies; a consumer Gemini subscription is not automatically an API credential.

To allow actions, enable **Allow voice to control this pet’s terminals**. Try:

- “List my terminals.”
- “Create a new terminal.”
- “In terminal 2, type claude and press Enter.”
- “Send hello to terminal 2 without pressing Enter.”
- “Send Control-C to terminal 2.”
- “Press Escape in terminal 2.”

IDs are the stable numbers shown in the tab labels for this app run. New tabs start in your home directory. Only ready, running tabs created by the pet can receive input. Input is a single line, up to 16 KB; control characters are rejected except the separately implemented Enter and interrupt keys. A queued input result does not mean its command succeeded. Claude-specific interactive prompts remain Claude’s responsibility; the voice feature does not auto-approve them. Commands spoken and submitted have your normal terminal permissions. Watch the selected terminal to see actions and their output. Disable terminal control when only chatting.

**Mute** stops sending microphone chunks while leaving the connection/audio engine open; **Stop** disconnects and releases audio capture/playback. Closing settings leaves voice running in the pet bar. **End**, the **Stop** button, saying “hang up”, or quitting the pet stops voice. No background listening starts at launch. Talking over Gemini clears its queued reply audio when the server reports interruption. Use headphones if your audio device's echo cancellation is unavailable. Reconnect after session expiry or device/network failures; session resumption is not implemented.

Scope is intentionally limited to listing/creating pet terminals, sending requested text, and Ctrl-C/Escape. It has no access to external terminal windows, files, or pet configuration. With **Share recent pet terminal output with Gemini** enabled, changed snapshots are sent every four seconds: up to eight tabs, the last 60 rendered lines and at most 4,000 characters per tab. This can include private terminal text; disable sharing to stop future snapshots (already sent context remains in the current session). Snapshots may be truncated or stale. Terminal context is untrusted data and cannot authorize commands. The voice stream, transcription, tool definitions, terminal IDs/folder labels, and tool results are exchanged with Google while connected. Audio/transcripts are not saved to disk; there is no conversation UI. Google's service data policies still apply. The app keeps a per-session tool-call cache so duplicate IDs do not repeat actions and ignores cancelled or post-disconnect calls.

Implementation: native AVAudioEngine microphone/playback and an ephemeral URLSession WebSocket to Google's Live API. Sends 16-bit PCM at the input device's reported rate (Gemini supports resampling) and plays 24 kHz PCM replies. Uses `gemini-3.1-flash-live-preview` by default; preview availability can change. No extra package or server is required.

Validation: native build/self-tests include tool argument validation. `"build/Bagad Billi.app/Contents/MacOS/BagadBilli" --voice-tool-smoke` uses synthetic model calls and real owned shell tabs to test disabled control, stable target routing, duplicate suppression, actual shell delivery, cancellation, and the stop gate. It makes no Gemini request and does not open the microphone. Live authentication, speech recognition, microphone hardware, and reply playback require testing with your key and devices.

Protocol references: [Google Live WebSocket reference](https://ai.google.dev/api/live) and [Live API capabilities](https://ai.google.dev/gemini-api/docs/live-api/capabilities).

The **Voice** button beneath the cat opens setup the first time; after saving a key it starts voice directly. The compact bar shows connection, incoming/outgoing audio packet activity, and mute state. **Mute** toggles the microphone stream; **End** hangs up; **⚙** opens settings. Terminal controls and context sharing are enabled by default for the requested assistant workflow and can be disabled in settings. The Terminal Desk toolbar opens settings. Clear spoken commands execute without repeated confirmation; Gemini asks when the target or destructive action is ambiguous.

Audio startup uses the output device’s native format and retries without echo cancellation if voice processing fails. Use headphones when the fallback notice appears. If both attempts fail, the voice window shows the native error domain/code; select working input and output devices in macOS Sound settings and retry.
