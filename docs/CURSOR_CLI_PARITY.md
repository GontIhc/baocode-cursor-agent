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
| Settings | `general_page.dart`, `cursor_agent_path_setting.dart` | CLI path (`cursorAgent.path`); does not change locator hacks. |
| Health / errors | `cursor_agent_kernel.dart` | Failed start, folder missing, RPC errors → `KernelHealth` + notices. |

## Partial / stub

| Area | What the UI or code does | Gap |
| --- | --- | --- |
| Plan → build | Plan approval works; no `StartsPlans` | No “Start building” handoff like Claude; accepted plan does not set `planUri` (see kernel TODO). |
| Session resume | `session/load` only when capability set | No `session/resume` without replay; new session if load unsupported. |
| Permission modes | Per-request approvals only | No `SelectsPermission` (no global yolo / ask-once mode in shell). |
| Model picker | Hidden (kernel does not implement `SelectsModel`) | Cursor model choice is CLI/account-side; shell does not yet map `config_option_update` / `available_commands_update`. |
| Slash commands | Hidden (no `ProvidesCommands`) | Not wired from ACP command list. |
| Account usage / cost | No `ReportsUsage` | `usage_update` may appear in-thread only; no account limits bar like Claude. |
| History paging | No `LoadsHistory` | No Claude-style transcript paging; rely on `session/load` replay when available. |
| FS / terminal ACP | Declined at `initialize` | `clientCapabilities` fs + terminal false; notifications ignored. |
| Images in prompts | `KernelTurn.images` not sent in ACP prompt parts | Text-only prompt array today. |
| Client identity | `clientInfo.name: baocursor` in `initialize` | ACP client id; display branding is BaoCursor in the app shell. |

## Missing vs Claude path (matters for daily use)

| Claude (`claude_code_kernel.dart`) | Cursor today | Impact |
| --- | --- | --- |
| `SelectsModel` + providers / proxy | Not implemented | Expected: model chosen in Cursor CLI or account, not in shell picker. |
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

- Anthropic provider catalog, API proxy translation, effort/context/fast tiers (`SelectsEffort`, `SelectsContextSize`, `SelectsFast`).
- Claude `stream-json` control channel, SDK tools, goals (`/goal`), haiku sidecar, Claude settings file sync.
- `CLAUDE.md` / Claude plugin marketplace as first-class kernel features (IDE may still read project files).
- Commit attribution modes tied to Claude Code CLI behavior (settings still say Claude-only where enforced).

## Deferred intentionally

- **Model / commands from ACP notifications** — translator TODO until confirmed on live `agent acp` traces (`config_option_update`, `available_commands_update`).
- **Bundle / repo rename** — display name `BaoCursor`; bundle id `dev.baocode.desktop` and repo `baocode-cursor-agent` unchanged for updates.
- **Hiding Claude-only Settings rows** — larger UX pass; kernel capability model already hides most composer controls for Cursor.

## High-value follow-ups (when protocol is confirmed)

1. Map `config_option_update` to a read-only or picker model display if Cursor exposes models on ACP.
2. Send image parts in `session/prompt` when CLI accepts them.
3. Implement `StartsPlans.startBuilding()` if Cursor documents a post-approval action beyond `accepted`.
4. `LoadsHistory` or slimmer “open old session” if `session/load` is absent but resume ids exist in catalog.
