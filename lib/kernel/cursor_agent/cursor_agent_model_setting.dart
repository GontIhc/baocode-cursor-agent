/// Settings → General → Cursor Agent: model id passed to the CLI as
/// `agent --model <id> acp` (`cursorAgent.model` in settings.json).
/// Empty: the CLI picks its default.
abstract final class CursorAgentModelSetting {
  static const settingKey = 'cursorAgent.model';

  static String? parse(Object? value) => switch (value) {
    final String model when model.trim().isNotEmpty => model.trim(),
    _ => null,
  };

  /// The model set now. [main.dart] reads it from settings.json.
  static String? Function() current = () => null;
}
