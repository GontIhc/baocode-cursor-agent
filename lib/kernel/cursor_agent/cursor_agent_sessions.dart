import '../agent_kernel.dart';
import 'cursor_agent_sessions_stub.dart'
    if (dart.library.io) 'cursor_agent_sessions_io.dart'
    as platform;

/// Cursor Agent CLI sessions on this machine (`chats/` and `acp-sessions/`
/// under the CLI config root). Not Claude's `projects/*.jsonl` store.
class CursorAgentCatalog implements SessionCatalog {
  const CursorAgentCatalog();

  @override
  Future<List<ProjectRecord>> projects() => platform.cursorCliProjects();

  @override
  Future<List<SessionRecord>> sessionsIn(String cwd) =>
      platform.cursorCliSessionsIn(cwd);

  @override
  Future<void> delete(String id) => platform.deleteCursorCliSession(id);
}
