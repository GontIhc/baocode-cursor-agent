# BaoCursor (Cursor Agent fork)

**BaoCursor** is a desktop shell around the **[Cursor Agent CLI](https://cursor.com/docs/cli/overview)** (`agent acp`) only — like upstream BaoCode was built for Claude Code only. It ships a fast UI and built-in IDE; **Claude Code is not offered** as an agent kernel in this build.

Repository: `baocode-cursor-agent` (name unchanged for compatibility). See [CONTRIBUTING.md](CONTRIBUTING.md) for install and settings. Kernel parity notes: [docs/CURSOR_CLI_PARITY.md](docs/CURSOR_CLI_PARITY.md).

**English** · [简体中文](README_CN.md) · [日本語](README_JA.md) · [Français](README_FR.md) · [Español](README_ES.md)

[Website](https://baocode.dev) · [Download](https://baocode.dev/download) · [Changelog](https://baocode.dev/changelog)

An awesome, easy-to-use desktop UI for **Cursor Agent**, with a millisecond-fast IDE built in.

![BaoCursor main window](site/shots/main.png)

## Why

The terminal is a fine place to run a coding agent, but a poor place to read one: long diffs scroll out of view, earlier steps are hard to find again, and reviewing what changed means switching to another app. BaoCursor is the window we wanted around **Cursor Agent CLI**.

BaoCursor has no agent of its own, by design. The agent is **Cursor Agent** over ACP. The UI is built for reading turns, reviewing edits, and working in the IDE beside the chat.

## Features

- **Cursor Agent over ACP** — modes (agent / plan / ask), permissions, questions, plans, todos, cancel, session load when supported.
- **An interface made for reading.** Reads, searches and commands fold into single lines. Review edits file by file in the IDE.
- **Fast IDE.** An editor, a terminal and Source Control with a commit graph, built in. VS Code, IntelliJ, Sublime and Atom keymaps, and language servers.
- **Named workspaces** — multi-repo Cursor CLI workspaces (see [CONTRIBUTING.md](CONTRIBUTING.md#multi-repo-workspaces-cursor-cli)).
- **Notifications.** A system notification, a sound and a badge when an agent needs you or finishes.

For the full upstream BaoCode feature list (browser extension, remote SSH, themes, etc.), see the original [BaoCode README](https://github.com/baocode-dev/baocode/blob/main/README.md). Some of those paths still assume Claude Code; this fork’s agent surface is Cursor-only.

## Speed

VS Code and Cursor are built on Electron: each window is a web page, and every copy carries its own Chromium and Node.js. BaoCursor is a native app that draws its own interface straight to the GPU.

| | BaoCursor | VS Code | Cursor |
| --- | --- | --- | --- |
| Launch | ≈ 0.18 s | ≈ 2–3 s | ≈ 2–3 s |
| Memory, one window idle | ≈ 120 MB | ≈ 970 MB | ≈ 1.9 GB |
| Processes, one window | 2 | 8 | 13 |
| Download size, Windows | ≈ 16 MB | ≈ 244 MB | ≈ 214 MB |

## Requirements

- macOS 12 or later (Apple silicon or Intel, one download each), Windows 10 or later (x64), or Linux: Ubuntu 22.04 or later and other Debian-based distributions (x64 or arm64, a .deb each).
- **[Cursor Agent CLI](https://cursor.com/docs/cli/installation)** (`agent` on your `PATH`, or set `cursorAgent.path` in settings). The composer model pill uses ACP’s model list when `agent acp` advertises one; otherwise it sets `cursorAgent.model` (Settings → General → Cursor Agent) and passes `agent --model … acp`. CLI chats for the open folder show in the sidebar. Install with:

  ```sh
  curl https://cursor.com/install -fsS | bash
  ```

### Multi-repo workspaces (Cursor CLI)

You can run across several repositories: set a saved CLI workspace name or add extra root folders in Settings → General → Cursor Agent (or in the bar above a new chat). The sidebar shows the active workspace and roots. See [CONTRIBUTING.md](CONTRIBUTING.md#multi-repo-workspaces-cursor-cli).

## Building from source

BaoCursor is a Flutter app (Dart SDK `^3.13.4`).

```sh
flutter pub get
flutter run -d macos        # or: flutter run -d windows
```

To build what is released, into `build/installers/`:

```sh
dart run tool/build_macos.dart            # BaoCursor-<version>-{arm64,x64}.dmg and BaoCursor-<version>-mac-{arm64,x64}.zip
dart run tool/build_windows.dart          # BaoCode-<version>-setup.exe (needs Inno Setup; name may still say BaoCode)
flutter build linux --release && sh tool/package_linux_deb.sh   # BaoCursor-<version>-linux-{amd64,arm64}.deb (executable stays baocode)
dart run tool/build_remote_server.dart    # the SSH remote server, for Linux x64 and arm64
```

**Package Linux** (Actions → Package Linux, or a push to `ci/package-linux`) builds the standard x64 edition and uploads a `linux` artifact (`BaoCursor-<version>-linux-amd64.deb` and `.tar.gz`). It does not publish to `dl.baocode.dev`. See [CONTRIBUTING.md](CONTRIBUTING.md#linux-package-github-actions).

The full test suite is slow; run the tests for what you changed, for example `flutter test test/update`.

Releases are built and published by CI when a `v*` tag is pushed; versions, signing and where releases go are in [docs/release.md](docs/release.md). More in [docs/](docs): [auto-update](docs/auto-update.md), [SSH remote](docs/ssh-remote.md), [Windows](docs/windows.md) (some are in Chinese).

## Repository

| Path | What it is |
| --- | --- |
| [lib/](lib) | The app |
| [packages/bao_editor](packages/bao_editor) | Monaco, ported to Flutter: the editor, its highlighting, VS Code's themes and keybindings |
| [packages/bao_xterm](packages/bao_xterm) | A Dart port of xterm.js |
| [packages/bao_pty](packages/bao_pty) | Pseudo terminals for Dart: forkpty on macOS and Linux, ConPTY on Windows |
| [packages/bao_remote](packages/bao_remote) | The remote host served over SSH |
| [macos/](macos), [windows/](windows), [linux/](linux) | The native runners |
| [tool/](tool) | Build, packaging and release scripts |
| [site/](site) | The website, [baocode.dev](https://baocode.dev) |
| [docs/](docs) | Design notes |

## Feedback

Issues are welcome. Pull requests are not accepted.

## License

GPL-3.0-or-later, same as BaoCode. See [LICENSE](LICENSE) and upstream attribution in source files.
