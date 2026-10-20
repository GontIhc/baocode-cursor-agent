# Contributing (Cursor Agent fork)

This repository is a fork of [BaoCode](https://github.com/baocode-dev/baocode) aimed at a **personal desktop shell for the [Cursor Agent CLI](https://cursor.com/docs/cli/overview)**. Claude Code remains available as a second kernel; Cursor Agent is the practical default when the `agent` binary is installed.

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

3. **Optional: pin the `agent` binary** — Settings → General → **Cursor Agent** → **Path** (`cursorAgent.path` in `settings.json`). Leave empty to search `PATH` and `~/.local/bin/agent`.

4. **Pick the kernel** — Settings → General → **Agent kernel** (Cursor Agent vs Claude Code), or use the kernel menu in the composer before the first message.

## Transport

Cursor Agent sessions use **ACP** (`agent acp` over stdio JSON-RPC). This fork does not drive Cursor through Claude Code’s `stream-json` control channel.

## Multi-repo workspaces (Cursor CLI)

The [Cursor CLI](https://cursor.com/docs/cli/changelog) supports named multi-directory workspaces:

- **Launch flags** — BaoCode starts `agent` with global flags before `acp`: `agent --workspace <name> acp`, or `agent --add-dir <path> … acp` when no name is set (primary cwd is still the project folder you picked).
- **Settings** — Settings → General → **Cursor Agent** → **CLI workspace** and **Extra roots** (`cursorAgent.workspace` / `cursorAgent.extraDirectories` in the app preference store). The same controls appear over a new Cursor Agent chat before the first message.
- **Sidebar** — With Cursor Agent selected, the sidebar shows the active named workspace and root folders.
- **Slash commands** — Messages such as `/save-workspace my-platform` or `/load-workspace my-platform` are sent through ACP `session/prompt` unchanged; the CLI handles them when supported.

To create a saved name from the terminal: `agent --workspace ./repo-a --add-dir ./repo-b`, then `/save-workspace my-platform`, then in BaoCode set **CLI workspace** to `my-platform` or pass it when starting new agents.

## Tests

The full suite is slow; run tests for what you changed, for example:

```sh
flutter test test/kernel/cursor_agent_kernel_test.dart
```

## License

Same as upstream: GPL-3.0-only for the app; see [LICENSE](LICENSE).
