# MyRemote

> Ad-free remote control for Samsung Tizen smart TVs.
> Clean UI, no tracking, no upsells — just a remote that works.

<p align="left">
  <img alt="Version" src="https://img.shields.io/badge/version-0.0.1-blue">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter">
  <img alt="Dart" src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android-green">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-lightgrey">
</p>

---

## Table of Contents

- [About](#about)
- [Features](#features)
- [Screenshots](#screenshots)
- [Getting Started](#getting-started)
- [Configuration](#configuration)
- [Project Structure](#project-structure)
- [How It Works](#how-it-works)
- [Known Limitations](#known-limitations)
- [Versioning & Releases](#versioning--releases)
- [Roadmap](#roadmap)
- [License](#license)

---

## About

**MyRemote** is a Flutter app that controls Samsung Tizen smart TVs over the local
network. It talks directly to the TV via the Samsung WebSocket remote-control
API — no cloud, no accounts, no telemetry. It's built as an ad-free alternative
to the many cluttered remote apps on the Play Store.

The project is currently in early development (`v0.0.x`). Expect breaking
changes between minor versions until `v1.0.0`.

---

## Features

- 🔌 **Direct WebSocket connection** to the TV on port `8002`
- 🎛 **Full D-pad navigation** with a clean circular layout
- 🔊 **Volume / Channel rockers** with mute toggle
- ⌨️ **Text input** for search fields on the TV
- 💤 **Wake-on-LAN** support for turning the TV on from standby
- 🌙 **Dark-first UI** designed for one-handed use
- 🚫 **No ads, no analytics, no telemetry**

---

## Getting Started

### Prerequisites

- Flutter `3.13.2` or newer
- Dart `3.13.2` or newer
- Android device or emulator (iOS support is planned)
- A Samsung Tizen TV on the same Wi-Fi network as your phone

### Installation

```bash
# 1. Clone the repository
git clone git@github.com:<your-user>/myremote.git
cd myremote

# 2. Install dependencies
flutter pub get

# 3. Set up your local environment file (see Configuration below)
cp .env.example .env
# then edit .env with your TV's values

# 4. Run
flutter run
```

---

## Configuration

Sensitive, device-specific values are stored in a **`.env`** file at the project
root. This file is **gitignored** and must never be committed.

### Setup

```bash
cp .env.example .env
```

Then edit `.env`:

```env
TV_DEFAULT_IP=192.168.1.100
TV_DEFAULT_MAC=AA:BB:CC:DD:EE:FF
TV_DEFAULT_NAME=My Samsung TV
```

### Reference

| Variable | Required | Description |
|---|---|---|
| `TV_DEFAULT_IP` | ✅ | LAN IP of the TV (find it under TV → Settings → Network → Network Status) |
| `TV_DEFAULT_MAC` | ⚠️ Optional | MAC address of the TV's network interface. Required only for Wake-on-LAN. |
| `TV_DEFAULT_NAME` | ✅ | Display name shown in the app's title bar |

> **Note:** These are only *fallback* values used the very first time the app
> runs. Once the TV is paired, the IP, MAC, and token are persisted to
> `SharedPreferences` on the device and read from there.

### Never commit these files

- `.env`
- `android/key.properties`
- `*.jks` / `*.keystore`

All are already listed in `.gitignore`.

---

## Project Structure

```
lib/
├── core/
│   ├── tv_connection_service.dart   # WebSocket + pairing + key/text sending
│   ├── tv_key_codes.dart            # Samsung Tizen key constants
│   └── wake_on_lan_service.dart     # WoL magic packet sender
├── models/
│   └── tv_device.dart               # TvDevice model (ip, mac, name, token)
├── screens/
│   ├── pairing_screen.dart          # (planned) manual IP/MAC entry
│   └── remote_screen.dart           # Main remote UI
├── widgets/
│   ├── dpad.dart                    # Circular D-pad widget
│   └── volume_channel_rocker.dart   # Volume + channel rocker widget
└── main.dart                        # App entry point, dotenv loader
```

---

## How It Works

1. **Connection**
   The app opens a WebSocket to `wss://<tv-ip>:8002/api/v2/channels/samsung.remote.control`.
   Because the TV uses a self-signed certificate on this port, TLS verification
   is bypassed specifically for this connection.

2. **Pairing**
   On the first connection, the TV shows an "Allow" prompt on screen. Once you
   accept it, the TV sends back a **token** in the `ms.channel.connect` event.
   That token is saved to `SharedPreferences` and reused on every subsequent
   connection, so the user only has to pair once.

3. **Sending keys**
   Keys are sent as JSON payloads with `TypeOfRemote: "SendRemoteKey"`. Example
   key codes: `KEY_UP`, `KEY_ENTER`, `KEY_VOLUP`, `KEY_POWER`.

4. **Sending text**
   Text is sent with `TypeOfRemote: "SendInputString"`. **Important:** the TV
   must already have a text field focused on screen (e.g. a search box). The
   API does not open the keyboard for you.

5. **Wake-on-LAN**
   When the TV is fully off, only a WoL magic packet can turn it on. The app
   broadcasts the packet to `255.255.255.255` on ports 7 and 9, then retries
   the WebSocket connection for up to 30 seconds.

---

## Known Limitations

- **Wake-on-LAN is unreliable.** It depends heavily on the TV model, firmware,
  and router. It requires "Power On with Mobile" to be enabled in the TV's
  network settings. Many TVs simply don't respond to WoL from full off.
- **Text input requires an active field on the TV.** The app cannot open the
  TV's on-screen keyboard remotely.
- **Android only for now.** iOS support is planned but not implemented.
- **One TV per install.** Multi-device support is not yet available.

---

## Versioning & Releases

This project follows [Semantic Versioning](https://semver.org/) with a
`v` prefix on git tags.

### Format

```
vMAJOR.MINOR.PATCH
```

| Part | When to bump | Example |
|---|---|---|
| **MAJOR** | Breaking change to the user-facing experience or an incompatible API change | `v1.0.0 → v2.0.0` |
| **MINOR** | New feature, backward compatible | `v0.1.0 → v0.2.0` |
| **PATCH** | Bug fix, backward compatible | `v0.0.1 → v0.0.2` |

### Pre-1.0 rules (current phase)

While the project is at `v0.x.y`:

- **MINOR** bumps may include breaking changes. That's expected.
- **PATCH** bumps are always safe.
- Nothing is considered stable until `v1.0.0`.

### Branch strategy

| Branch | Purpose |
|---|---|
| `main` | Always stable. Only merged PRs from `dev`. |
| `dev` | Active development. May be broken. |
| `feature/*` | One branch per feature or fix, branched from `dev`. |

### Commit message convention

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short description>

[optional body]

[optional footer]
```

Common types:

- `feat:` — new feature
- `fix:` — bug fix
- `refactor:` — code change that neither fixes a bug nor adds a feature
- `docs:` — documentation only
- `chore:` — tooling, dependencies, build config
- `style:` — formatting, missing semicolons, etc.

Examples:

```
feat(remote): add long-press for volume up
fix(connection): retry WebSocket connect on TV wake-up
docs(readme): clarify Wake-on-LAN setup
chore(deps): bump flutter_dotenv to 5.1.0
```

### Release process

1. Merge everything intended for the release into `main`.
2. Update `version:` in `pubspec.yaml` **and** the badge at the top of this README.
3. Commit with message: `chore(release): vX.Y.Z`
4. Tag the commit:
   ```bash
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   git push origin main --tags
   ```
5. (When the Play Store build is ready) create a GitHub Release from the tag
   with a short changelog.

### Changelog

Starting from `v0.1.0`, every release will include a `CHANGELOG.md` entry
following the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

### Version history

| Version | Date | Notes |
|---|---|---|
| `v0.0.1` | _TBD_ | Initial scaffold: WebSocket connection, D-pad, volume/channel, text input, WoL skeleton |

---

## Roadmap

- [x] WebSocket connection + pairing token persistence
- [x] D-pad, volume, channel, mute
- [x] Text input into active TV fields
- [x] Dark UI matching the design mockup
- [x] `.env`-based config for personal TV details
- [ ] Robust Wake-on-LAN with retry and status feedback
- [ ] Manual pairing screen (enter IP/MAC without `.env`)
- [ ] Multi-TV support
- [ ] App launcher shortcuts (e.g. one-tap YouTube)
- [ ] iOS support
- [ ] Play Store release (`v1.0.0`)

---

## License

MIT — see [`LICENSE`](LICENSE) for details.

---

<p align="center">
  Built with ☕ and too many TV reboots.
</p>

