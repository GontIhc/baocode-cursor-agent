import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Saved Cursor CLI workspace names, if they can be found on disk.
///
/// The CLI documents `/save-workspace` and `--workspace <name>` but not
/// where names are stored. When a known file appears, list it here.
Future<List<String>> listSavedCursorCliWorkspaces() async {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) return const [];
  final candidates = <File>[
    File(p.join(home, '.cursor', 'workspaces.json')),
    File(p.join(home, '.cursor', 'agent-workspaces.json')),
  ];
  for (final file in candidates) {
    if (!file.existsSync()) continue;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) {
        final names = decoded.keys.whereType<String>().toList();
        if (names.isNotEmpty) names.sort();
        return names;
      }
      if (decoded is List) {
        final names = decoded.whereType<String>().toList();
        if (names.isNotEmpty) names.sort();
        return names;
      }
    } on FormatException {
      continue;
    }
  }
  return const [];
}
