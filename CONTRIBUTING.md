# Contributing to BaoCursor

**BaoCursor** is a fork of [BaoCode](https://github.com/baocode-dev/baocode) (GPL): a **personal desktop shell for the [Cursor Agent CLI](https://cursor.com/docs/cli/overview)** only. **Claude Code is not offered** as an agent kernel in this build; sessions use Cursor Agent (`agent acp`) over stdio.

Feature parity vs the upstream Claude adapter is documented in [docs/CURSOR_CLI_PARITY.md](docs/CURSOR_CLI_PARITY.md).

## Quick start

1. **Install the Cursor CLI** (provides the `agent` command):

   ```sh
   curl https://cursor.com/install -fsS | bash
   ```

   On Windows (PowerShell): `irm 'https://cursor.com/install?win32=true' | iex`

   See [Cursor CLI installation](https://cursor.com/docs/cli/installation).

2. **Run the Flutter app** (Dart SDK `^3.13.4`):

   ```sh
   flutter pub get
   flutter run -d macos    # or windows / linux
   ```

3. **Optional: pin the `agent` binary** — Settings → General → **Cursor Agent** → **Path** (`cursorAgent.path` in `settings.json`). Leave empty to search `PATH` and `~/.local/bin/agent`. **Model** (`cursorAgent.model`) is passed as `agent --model … acp` when set.

If the CLI is missing, the app shows an install hint at launch and when you start a conversation.

## Transport

Cursor Agent sessions use **ACP** (`agent acp` over stdio JSON-RPC). This fork does not drive agents through Claude Code’s `stream-json` control channel.

## Multi-repo workspaces (Cursor CLI)

The [Cursor CLI](https://cursor.com/docs/cli/changelog) supports named multi-directory workspaces:

- **Launch flags** — BaoCursor starts `agent` with global flags before `acp`: `agent --workspace <name> acp`, or `agent --add-dir <path> … acp` when no name is set (primary cwd is still the project folder you picked).
- **Settings** — Settings → General → **Cursor Agent** → **CLI workspace** and **Extra roots** (`cursorAgent.workspace` / `cursorAgent.extraDirectories` in the app preference store). The same controls appear over a new Cursor Agent chat before the first message.
- **Sidebar** — The sidebar shows the active named workspace and root folders for Cursor Agent chats.
- **Slash commands** — Messages such as `/save-workspace my-platform` or `/load-workspace my-platform` are sent through ACP `session/prompt` unchanged; the CLI handles them when supported.

To create a saved name from the terminal: `agent --workspace ./repo-a --add-dir ./repo-b`, then `/save-workspace my-platform`, then in BaoCursor set **CLI workspace** to `my-platform` or pass it when starting new agents.

## macOS package (GitHub Actions)

To build installable macOS DMGs without running the full **Release** workflow (Windows, Linux, and publish to `dl.baocode.dev`):

1. Open **Actions** → **Package macOS** → **Run workflow** (branch `main`).
2. When the run finishes, download the **`macos`** artifact.
3. Install from `BaoCursor-<version>-arm64.dmg` (Apple silicon) or `BaoCursor-<version>-x64.dmg` (Intel).

These builds are **ad-hoc signed** when this fork has no Apple Developer ID secrets. On your Mac, if Gatekeeper blocks the app, use **Open Anyway** in **System Settings → Privacy & Security**.

## Tests

The full suite is slow; run tests for what you changed, for example:

```sh
flutter test test/kernel/cursor_agent_kernel_test.dart
```

## License

Same as upstream: GPL-3.0-only for the app; see [LICENSE](LICENSE).
