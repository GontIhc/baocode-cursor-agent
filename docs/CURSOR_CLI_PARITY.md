# Cursor Agent CLI parity (BaoCursor shell)

This document compares what the **Claude Code** kernel adapter still implements in-tree (`lib/kernel/claude_code/`, used in tests and parity reference) with the **Cursor Agent** adapter (`lib/kernel/cursor_agent/`) that **BaoCursor ships** over **ACP** (`agent acp` stdio JSON-RPC). The UI registry exposes **Cursor Agent only** (`KernelRegistry.all` → `[cursorAgent]`). It reflects the code on this fork, not wishful protocol support.

References:

- [Cursor CLI ACP](https://cursor.com/docs/cli/acp)
- [Agent Client Protocol](https://agentclientprotocol.com/protocol/v1/overview)

## Supported now

| Area | Cursor path | Notes |
| --- | --- | --- |
| Process + transport | `cursor_agent_process_io.dart`, `cursor_agent_transport.dart` | Spawns `agent acp` in project `cwd`; newline-delimited JSON-RPC. |
| Boot / auth | `cursor_agent_kernel.dart` (`initialize`, `authenticate`) | `cursor_login`; surfaces login / `CURSOR_API_KEY` errors. |
| Session lifecycle | `cursor_agent_kernel.dart` | `session/new`, `session/prompt`, `session/cancel`, `session/set_mode`. |
| Session resume (replay) | `cursor_agent_kernel.dart` | `session/load` when `agentCapabilities.loadSession` is true; replays via translator `replaying`. |
| Modes | `cursor_agent_kernel.dart`, composer | `SelectsMode`: agent / plan / ask; `session/set_mode` + `current_mode_update`. |
| Model picker | `cursor_agent_kernel.dart`, `session_model_picker.dart` | `SelectsModel`. `initialize` sets `clientCapabilities._meta.parameterizedModelPicker`. ACP `configOptions` category `model` is the menu (bare ids). Effort, context, fast, and thinking, when advertised, are the same settings submenu and `session/set_config_option` (`effort` / `reasoning` / `reasoning_effort`, `context`, `fast`, `thinking`). `--model` is only a bare CLI id. An exploded `id[context=…,effort=…,fast=…]` value is never passed as `--model`. If the CLI never advertises models, the menu is CLI default, the current id, recent ids, and a typed id, and that path restarts as `agent --model <id> acp`. A resumed CLI chat omits `--model` and does not rewrite stored parameters until the user picks. |
| CLI history | `cursor_agent_sessions_io.dart` | Sidebar catalog reads Cursor CLI `chats/` and `acp-sessions/` (not Claude `projects/*.jsonl`, not IDE `agent-transcripts`). Opening a row resumes with `session/load` (`sessionId`, `cwd`, empty `mcpServers` only) when advertised. Invalid params or a process exit on load starts a new session and leaves the honest empty state (history stays in the CLI store). |
| User turn | `cursor_agent_kernel.dart` | Text + optional notes in `session/prompt`. |
| Streaming text / thinking | `cursor_agent_translator.dart` | `agent_message_chunk`, `agent_thought_chunk`. |
| Tool calls | `cursor_agent_translator.dart` | `tool_call` / `tool_call_update` → chat items. |
| Permissions | `cursor_agent_kernel.dart` | `session/request_permission` → approval UI → `optionId`. |
| Questions | `cursor_agent_kernel.dart` | `cursor/ask_question` → question UI. |
| Plans (approval) | `cursor_agent_kernel.dart`, translator | `cursor/create_plan` + inline `plan` updates; accept/reject outcomes. |
| Todos | `cursor_agent_translator.dart` | `cursor/update_todos` + plan todos. |
| Subagent tasks | `cursor_agent_translator.dart` | `cursor/task` notifications. |
| Generate image | `cursor_agent_translator.dart` | `cursor/generate_image` (path shown; bytes not read). |
| Usage chunks | `cursor_agent_translator.dart` | `usage_update` when present. |
| Multi-root hints | `cursor_agent_kernel.dart` | `additionalDirectories` when advertised. |
| MCP | `cursor_agent_kernel.dart` | Empty `mcpServers` in `session/new`; Cursor reads `.cursor/mcp.json` in project. |
| Kernel registration / default | `kernel_registry.dart`, `main.dart` | **Cursor Agent only** in the registry; default kernel on startup. Claude descriptor kept for tests, not offered in UI. |
| Settings | `general_page.dart`, `cursor_agent_path_setting.dart`, `cursor_agent_model_setting.dart` | CLI path (`cursorAgent.path`) and model (`cursorAgent.model`). The composer writes the model key. Locator and `--yolo` are unchanged. |
| Health / errors | `cursor_agent_kernel.dart` | Failed start, folder missing, RPC errors → `KernelHealth` + notices. |

## Partial / stub

| Area | What the UI or code does | Gap |
| --- | --- | --- |
| Plan → build | Plan approval works; no `StartsPlans` | No “Start building” handoff like Claude; accepted plan does not set `planUri` (see kernel TODO). |
| Session resume | `session/load` only when capability set | No `session/resume` without replay. The sidebar still lists the CLI chat; opening it explains that history stays in the store and a new session starts. |
| Permission modes | Per-request approvals only | No `SelectsPermission` (no global yolo / ask-once mode in shell). |
| Slash commands | Hidden (no `ProvidesCommands`) | Not wired from ACP `available_commands_update`. |
| Account usage / cost | No `ReportsUsage` | `usage_update` may appear in-thread only; no account limits bar like Claude. |
| History paging | No `LoadsHistory` | No Claude-style transcript paging; rely on `session/load` replay when available. |
| FS / terminal ACP | Declined at `initialize` | `clientCapabilities` fs + terminal false; notifications ignored. |
| Images in prompts | `KernelTurn.images` not sent in ACP prompt parts | Text-only prompt array today. |
| Client identity | `clientInfo.name: baocursor` in `initialize` | ACP client id; display branding is BaoCursor in the app shell. |

## Missing vs Claude path (matters for daily use)

| Claude (`claude_code_kernel.dart`) | Cursor today | Impact |
| --- | --- | --- |
| `SelectsModel` + providers / proxy | Cursor model id only | No Claude provider catalog or proxy. Effort, context, fast, and thinking are ACP config options when the CLI advertises them, not Claude tiers. |
| `SelectsPermission` modes | Not implemented | Approvals are per tool request only. |
| `ProvidesCommands` | Not implemented | No `/goal`, custom slash commands from shell. |
| `QueuesMessages` | Not implemented | Cannot queue while busy. |
| `RewindsConversation` / `ForksConversation` | Not implemented | No rewind/fork from shell UI. |
| `RevertsChanges` / checkpoints | Not implemented | No per-turn file revert through kernel. |
| `RenamesSession` | Not implemented | Session titles from catalog only. |
| `SuggestsFiles` / `@` file picker backend | Not implemented | Composer file suggestions Claude-specific. |
| `SuggestsPrompts` | Not implemented | No Tab-to-accept next prompt. |
| `RunsBackgroundTasks` | Not implemented | No move-to-background on tools. |
| `ReportsContext` / `ReportsUsage` | Not implemented | No context window meter / rate limits. |
| `ManagesMcpServers` | Not implemented | MCP via `.cursor/mcp.json` + Cursor config, not shell MCP UI. |
| `AcceptsImages` | Not implemented | Image attachments not sent over ACP prompt. |
| Remote SSH Claude install / core | Claude remote stack | Remote workflows still Claude-oriented in settings copy. |
| Built-in Dart core (`bao_agent`) | Claude-only | Cursor fork uses external `agent` binary only. |

## Not applicable (Claude-only)

- Anthropic provider catalog and API proxy translation. Cursor effort / context / fast / thinking are ACP config options, not Claude's tiers.
- Claude `stream-json` control channel, SDK tools, goals (`/goal`), haiku sidecar, Claude settings file sync.
- `CLAUDE.md` / Claude plugin marketplace as first-class kernel features (IDE may still read project files).
- Commit attribution modes tied to Claude Code CLI behavior (settings still say Claude-only where enforced).

## Deferred intentionally

- **Slash commands from ACP** — `available_commands_update` is still ignored. Model `config_option_update` is applied when the payload matches the ACP select shape.
- **Bundle / repo rename** — display name `BaoCursor`; bundle id `dev.baocode.desktop` and repo `baocode-cursor-agent` unchanged for updates.
- **Hiding Claude-only Settings rows** — larger UX pass; kernel capability model already hides most composer controls for Cursor.

## High-value follow-ups (when protocol is confirmed)

1. Send image parts in `session/prompt` when CLI accepts them.
2. Implement `StartsPlans.startBuilding()` if Cursor documents a post-approval action beyond `accepted`.
3. Page a loaded transcript (`LoadsHistory`) when `session/load` replays more than the shell should show at once.

## Check on macOS with Cursor CLI

1. `agent login`, then in the project folder run `agent` and send a message so `~/.cursor/chats/<hash>/<id>/meta.json` (or `~/.cursor/acp-sessions/<id>/`) exists. `cwd` in that file should be the folder you will open.
2. Open that folder in BaoCursor. The sidebar lists that CLI chat next to BaoCursor chats. The top-right editor chip reads **BaoCursor**.
3. Open the CLI chat. If this `agent` build advertises `loadSession` and the id is an ACP session, the transcript replays via `session/load`. If load returns invalid params or the process exits, the chat stays usable: the empty state says the history stays in the CLI store, and a new message starts a new session. There is no red error that blocks the composer.
4. The composer shows a model pill beside Agent / Plan / Ask. With ACP `configOptions`, the menu is bare model ids, and effort / context / fast / thinking (when the CLI lists them) are rows in that menu. A pick sends `session/set_config_option`. The pill does not show `id[context=…]`, and the process does not exit with `Cannot use this model`. Otherwise the menu lists **CLI default**, the current id, recent ids, and **Other model…**. Picking a plain id asks to restart, then the process is `agent --model <id> acp`.
5. New Chat (sidebar and the shortcut) opens a new window when the app can create windows.
6. The sidebar section **Folders in this workspace** lists each folder path in the current workspace (multi-root folders and `--add-dir` roots), plus the named workspace when one is set. It is not only the chat group's title.
