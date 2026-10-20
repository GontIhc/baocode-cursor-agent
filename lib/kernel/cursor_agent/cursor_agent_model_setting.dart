import 'dart:convert';

/// Settings → General → Cursor Agent: model id passed to the CLI as
/// `agent --model <id> acp` (`cursorAgent.model` in settings.json).
/// Empty: the CLI picks its default. The composer writes the same key,
/// and keeps a short list of recent ids (`cursorAgent.recentModels`).
abstract final class CursorAgentModelSetting {
  static const settingKey = 'cursorAgent.model';
  static const recentKey = 'cursorAgent.recentModels';

  static String? parse(Object? value) => switch (value) {
    final String model when model.trim().isNotEmpty => model.trim(),
    _ => null,
  };

  static List<String> parseRecent(Object? value) {
    final raw = switch (value) {
      final List<Object?> list => list,
      final String text when text.trim().isNotEmpty => _decodeList(text),
      _ => const <Object?>[],
    };
    final models = <String>[];
    for (final entry in raw) {
      final model = parse(entry);
      if (model == null || models.contains(model)) continue;
      models.add(model);
    }
    return models;
  }

  static List<Object?> _decodeList(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is List ? decoded : const [];
    } on FormatException {
      return const [];
    }
  }

  /// The model set now. [main.dart] reads it from settings.json.
  static String? Function() current = () => null;

  /// Recent composer picks, newest first.
  static List<String> Function() recent = () => const [];

  /// Writes the model (null clears it) and the recent list.
  static void Function(String? model, List<String> recent) persist = (_, _) {};
}
