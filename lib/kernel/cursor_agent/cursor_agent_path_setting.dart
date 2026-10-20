/// Settings key for the Cursor Agent CLI to run (`cursorAgent.path` in
/// settings.json). Empty: look on `PATH`, then `~/.local/bin/agent`.
///
/// There is no Settings row yet. The key is read the same way as
/// `claudeCode.path`: [current] is filled in from settings.json at startup.
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
