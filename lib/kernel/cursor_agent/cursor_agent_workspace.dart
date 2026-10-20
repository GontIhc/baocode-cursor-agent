import 'dart:convert';

import 'package:path/path.dart' as p;

import '../agent_kernel.dart';

/// Cursor CLI multi-root workspace settings (`cursorAgent.*` in
/// settings.json and the workspace preference store).
abstract final class CursorAgentWorkspaceSetting {
  static const workspaceKey = 'cursorAgent.workspace';
  static const extraDirsKey = 'cursorAgent.extraDirectories';

  static List<String> parseExtraDirectories(String? encoded) {
    if (encoded == null || encoded.isEmpty) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is String && entry.isNotEmpty) entry,
      ];
    } on FormatException {
      return const [];
    }
  }

  static String encodeExtraDirectories(List<String> directories) =>
      jsonEncode(directories);

  /// argv before the process starts: global flags, then the `acp`
  /// subcommand (see `agent --help`).
  static List<String> processArguments({
    String? namedWorkspace,
    required List<String> addDirectories,
  }) {
    final args = <String>[];
    final name = namedWorkspace?.trim();
    if (name != null && name.isNotEmpty) {
      args.addAll(['--workspace', name]);
    } else {
      for (final directory in addDirectories) {
        if (directory.isEmpty) continue;
        args.addAll(['--add-dir', directory]);
      }
    }
    args.add('acp');
    return args;
  }
}

/// What Cursor Agent will run with for one [KernelContext].
class ResolvedCursorAgentWorkspace {
  const ResolvedCursorAgentWorkspace({
    this.namedWorkspace,
    required this.primaryRoot,
    this.extraRoots = const [],
  });

  final String? namedWorkspace;
  final String primaryRoot;
  final List<String> extraRoots;

  bool get usesNamedWorkspace {
    final name = namedWorkspace?.trim();
    return name != null && name.isNotEmpty;
  }

  /// Directories passed as repeated `--add-dir` (not used with a named
  /// workspace).
  List<String> get cliAddDirectories {
    if (usesNamedWorkspace) return const [];
    final primary = p.normalize(primaryRoot);
    final seen = <String>{primary};
    final out = <String>[];
    for (final root in extraRoots) {
      if (root.isEmpty) continue;
      final normalized = p.normalize(root);
      if (seen.add(normalized)) out.add(root);
    }
    return out;
  }

  bool get usesCliWorkspaceFlags =>
      usesNamedWorkspace || cliAddDirectories.isNotEmpty;

  List<String> get processArguments => CursorAgentWorkspaceSetting.processArguments(
    namedWorkspace: namedWorkspace,
    addDirectories: cliAddDirectories,
  );

  /// Roots shown in the UI: primary first, then extras (named workspace
  /// still lists configured folders for context).
  List<String> get displayRoots {
    final primary = primaryRoot;
    if (primary.isEmpty) return [...extraRoots];
    final seen = <String>{p.normalize(primary)};
    return [
      primary,
      for (final root in extraRoots)
        if (root.isNotEmpty && seen.add(p.normalize(root))) root,
    ];
  }
}

ResolvedCursorAgentWorkspace resolveCursorAgentWorkspace(KernelContext context) {
  final cwd = context.cwd ?? '';
  final settings = context.settings;
  final named = settings[CursorAgentWorkspaceSetting.workspaceKey]?.trim();
  final configured = CursorAgentWorkspaceSetting.parseExtraDirectories(
    settings[CursorAgentWorkspaceSetting.extraDirsKey],
  );
  final workspaceFolders = context.workspace?.call()?.folders ?? const [];
  final extras = <String>[];
  final seen = <String>{};
  void add(String path) {
    if (path.isEmpty) return;
    if (seen.add(p.normalize(path))) extras.add(path);
  }
  for (final directory in configured) {
    add(directory);
  }
  if (named == null || named.isEmpty) {
    for (final folder in workspaceFolders) {
      add(folder);
    }
  }
  return ResolvedCursorAgentWorkspace(
    namedWorkspace: named?.isEmpty == true ? null : named,
    primaryRoot: cwd,
    extraRoots: extras,
  );
}
