import 'cursor_agent_locator_stub.dart'
    if (dart.library.io) 'cursor_agent_locator_io.dart'
    as platform;

/// Settings → General → Cursor Agent: the `agent` binary to run on this
/// machine (`cursorAgent.path` in settings.json). Empty: `PATH`, then
/// `~/.local/bin/agent`.
abstract final class CursorAgentPathSetting {
  static const settingKey = 'cursorAgent.path';

  /// The path a setting's [value] names; null for none.
  static String? parse(Object? value) => switch (value) {
    final String path when path.trim().isNotEmpty => path.trim(),
    _ => null,
  };

  /// The path set now. main.dart reads it from settings.json.
  static String? Function() current = () => null;
}

/// The Cursor Agent CLI Settings shows as running on this machine.
sealed class LocalCursorAgentStatus {
  const LocalCursorAgentStatus();
}

/// [path] is the `agent` binary that would run.
class LocalCursorAgentFound extends LocalCursorAgentStatus {
  const LocalCursorAgentFound(this.path);

  final String path;
}

/// None on `PATH` or in `~/.local/bin`, and no path set.
class LocalCursorAgentMissing extends LocalCursorAgentStatus {
  const LocalCursorAgentMissing();
}

/// A path was set or looked up, but nothing runs there ([message] says why).
class LocalCursorAgentFailed extends LocalCursorAgentStatus {
  const LocalCursorAgentFailed(this.message);

  final String message;
}

/// The Cursor Agent CLI on this machine now; null on the web.
Future<LocalCursorAgentStatus?> localCursorAgentStatus() =>
    platform.localCursorAgentStatus();

/// Whether the `agent` CLI can be found; false on the web.
Future<bool> cursorAgentInstalled() => platform.cursorAgentInstalled();
