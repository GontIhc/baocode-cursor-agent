import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../agent_kernel.dart';

/// Lists Cursor Agent CLI sessions under the usual config roots.
///
/// Interactive CLI chats live in `<root>/chats/<md5(cwd)>/<id>/`. ACP
/// sessions live in `<root>/acp-sessions/<id>/` (or the same two-level
/// layout). `meta.json` carries `cwd`, timestamps, and sometimes a title.
/// This is not `~/.cursor/projects/*/agent-transcripts` (IDE / Agents
/// window) and not Claude's config `projects/`.
///
/// Roots, first match wins for a given session id: `CURSOR_CONFIG_DIR`,
/// `$XDG_CONFIG_HOME/cursor`, `$XDG_CONFIG_HOME/Cursor`, `~/.cursor`,
/// `~/.config/cursor`, `~/.config/Cursor`.
Future<List<ProjectRecord>> cursorCliProjects({List<String>? roots}) async {
  final sessions = await _scan(roots);
  final grouped = <String, List<SessionRecord>>{};
  for (final session in sessions) {
    final cwd = session.cwd;
    if (cwd == null || cwd.isEmpty) continue;
    final key = cursorProjectKey(cwd);
    (grouped[key] ??= []).add(session.record(key));
  }
  final projects = [
    for (final MapEntry(:key, :value) in grouped.entries)
      ProjectRecord(path: key, sessions: _newestFirst(value)),
  ];
  projects.sort((a, b) {
    final left = a.updatedAt;
    final right = b.updatedAt;
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return right.compareTo(left);
  });
  return projects;
}

/// Sessions whose `cwd` (or workspace hash, when `cwd` was not written)
/// is [cwd].
Future<List<SessionRecord>> cursorCliSessionsIn(
  String cwd, {
  List<String>? roots,
}) async {
  final sessions = await _scan(roots);
  final hits = [
    for (final session in sessions)
      if (session.matches(cwd)) session.record(session.cwd ?? cwd),
  ];
  return _newestFirst(hits);
}

/// Removes the session directory named [id] under a known CLI root.
/// Anything outside those roots is left alone.
Future<void> deleteCursorCliSession(String id, {List<String>? roots}) async {
  if (!_safeId(id)) return;
  for (final session in await _scan(roots)) {
    if (session.id != id) continue;
    final dir = Directory(session.path);
    if (!dir.existsSync()) continue;
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // Already gone, or still open in the CLI.
    }
  }
}

/// [path] with a trailing slash removed, for comparing project folders.
String cursorProjectKey(String path) {
  var normalized = p.normalize(path.trim());
  while (normalized.length > 1 &&
      (normalized.endsWith('/') || normalized.endsWith(r'\'))) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

bool cursorSameProject(String a, String b) {
  final left = cursorProjectKey(a);
  final right = cursorProjectKey(b);
  if (left == right) return true;
  if (Platform.isMacOS || Platform.isWindows) {
    return left.toLowerCase() == right.toLowerCase();
  }
  return false;
}

/// Lowercase MD5 of [path], the bucket name under `chats/`.
String cursorWorkspaceKey(String path) =>
    md5.convert(utf8.encode(path)).toString();

List<String> cursorCliStoreRoots({
  Map<String, String>? environment,
  String? home,
}) {
  final env = environment ?? Platform.environment;
  final roots = <String>[];
  void add(String? path) {
    if (path == null) return;
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    final normalized = p.normalize(trimmed);
    if (!roots.contains(normalized)) roots.add(normalized);
  }

  add(env['CURSOR_CONFIG_DIR']);
  final xdg = env['XDG_CONFIG_HOME'];
  if (xdg != null && xdg.trim().isNotEmpty) {
    add(p.join(xdg.trim(), 'cursor'));
    add(p.join(xdg.trim(), 'Cursor'));
  }
  final homeDir = home ?? env['HOME'] ?? env['USERPROFILE'];
  if (homeDir != null && homeDir.trim().isNotEmpty) {
    add(p.join(homeDir.trim(), '.cursor'));
    add(p.join(homeDir.trim(), '.config', 'cursor'));
    add(p.join(homeDir.trim(), '.config', 'Cursor'));
  }
  return roots;
}

class _Hit {
  _Hit({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.cwd,
    required this.path,
    required this.workspaceKey,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final String? cwd;
  final String path;
  final String? workspaceKey;

  bool matches(String folder) {
    final stored = cwd;
    if (stored != null && stored.isNotEmpty) {
      return cursorSameProject(stored, folder);
    }
    final bucket = workspaceKey;
    if (bucket == null) return false;
    final want = bucket.toLowerCase();
    for (final variant in _pathVariants(folder)) {
      if (cursorWorkspaceKey(variant) == want) return true;
    }
    return false;
  }

  SessionRecord record(String cwd) => SessionRecord(
    id: id,
    title: title,
    updatedAt: updatedAt,
    cwd: cwd,
    path: path,
  );
}

Future<List<_Hit>> _scan(List<String>? roots) async {
  final byId = <String, _Hit>{};
  for (final root in roots ?? cursorCliStoreRoots()) {
    if (!Directory(root).existsSync()) continue;
    for (final name in const ['chats', 'acp-sessions']) {
      final dir = Directory(p.join(root, name));
      if (!dir.existsSync()) continue;
      await for (final hit in _walk(dir)) {
        final kept = byId[hit.id];
        if (kept == null || hit.updatedAt.isAfter(kept.updatedAt)) {
          byId[hit.id] = hit;
        }
      }
    }
  }
  return byId.values.toList();
}

Stream<_Hit> _walk(Directory root) async* {
  final pending = <Directory>[root];
  while (pending.isNotEmpty) {
    final dir = pending.removeLast();
    List<FileSystemEntity> children;
    try {
      children = dir.listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }
    for (final child in children) {
      if (child is! Directory) continue;
      final metaFile = File(p.join(child.path, 'meta.json'));
      final dbFile = File(p.join(child.path, 'store.db'));
      final hasMeta = metaFile.existsSync();
      final hasDb = dbFile.existsSync();
      if (!hasMeta && !hasDb) {
        // chats/<hash>/ before chats/<hash>/<id>/.
        if (p.equals(dir.path, root.path) ||
            p.equals(dir.parent.path, root.path)) {
          pending.add(child);
        }
        continue;
      }
      final hit = _readSession(
        child,
        metaFile,
        dbFile,
        storeName: p.basename(root.path),
      );
      if (hit != null) yield hit;
    }
  }
}

_Hit? _readSession(
  Directory dir,
  File metaFile,
  File dbFile, {
  required String storeName,
}) {
  final id = p.basename(dir.path);
  if (!_safeId(id)) return null;
  Map<String, Object?> meta = const {};
  if (metaFile.existsSync()) {
    try {
      final decoded = jsonDecode(metaFile.readAsStringSync());
      final map = decoded is Map ? Map<String, Object?>.from(decoded) : null;
      if (map != null) meta = map;
    } on Object {
      meta = const {};
    }
  }
  if (meta['isSubagent'] == true) return null;
  final cwd = _string(meta['cwd']) ?? _string(meta['workspacePath']);
  final fromFiles = _titleFromMeta(meta) ?? _titleFromPromptHistory(dir);
  final title = fromFiles ?? _titleFromStore(dbFile) ?? 'CLI ${_shortId(id)}';
  if (meta['hasConversation'] == false && fromFiles == null) return null;
  final updated =
      _time(meta['updatedAtMs']) ??
      _time(meta['updatedAt']) ??
      _time(meta['createdAtMs']) ??
      _time(meta['createdAt']) ??
      _mtime(metaFile.existsSync() ? metaFile : dbFile);
  final parent = dir.parent;
  final workspaceKey = p.basename(parent.path) == storeName
      ? null
      : p.basename(parent.path);
  return _Hit(
    id: id,
    title: title,
    updatedAt: updated,
    cwd: cwd ?? _cwdFromStore(dbFile),
    path: dir.path,
    workspaceKey: workspaceKey,
  );
}

String? _titleFromMeta(Map<String, Object?> meta) {
  for (final key in const ['title', 'name', 'summary']) {
    final title = _usableTitle(_string(meta[key]));
    if (title != null) return title;
  }
  return null;
}

String? _titleFromPromptHistory(Directory dir) {
  final file = File(p.join(dir.path, 'prompt_history.json'));
  if (!file.existsSync()) return null;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! List) return null;
    for (final entry in decoded) {
      final text = switch (entry) {
        final String value => value,
        final Map<Object?, Object?> map =>
          _string(map['text']) ?? _string(map['prompt']),
        _ => null,
      };
      final title = _usablePrompt(text);
      if (title != null) return title;
    }
  } on Object {
    return null;
  }
  return null;
}

String? _titleFromStore(File db) => _scanStore(db, _usablePrompt);

String? _cwdFromStore(File db) => _scanStore(db, (text) {
  final match = RegExp(r'"(?:cwd|workspacePath)"\s*:\s*"((?:\\.|[^"\\])*)"')
      .firstMatch(text);
  final raw = match?.group(1);
  if (raw == null || raw.isEmpty) return null;
  final path = raw
      .replaceAll(r'\/', '/')
      .replaceAll(r'\\', r'\')
      .replaceAll(r'\"', '"');
  if (path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
    return path;
  }
  return null;
});

String? _scanStore(File db, String? Function(String text) read) {
  if (!db.existsSync()) return null;
  RandomAccessFile? handle;
  try {
    final length = db.lengthSync();
    if (length <= 0) return null;
    handle = db.openSync();
    const cap = 512 * 1024;
    final head = handle.readSync(length > cap ? cap : length);
    final fromHead = read(_loose(head));
    if (fromHead != null || length <= cap) return fromHead;
    handle.setPositionSync(length - cap);
    return read(_loose(handle.readSync(cap)));
  } on Object {
    return null;
  } finally {
    handle?.closeSync();
  }
}

String _loose(List<int> bytes) => latin1.decode(bytes, allowInvalid: true);

String? _usableTitle(String? raw) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return null;
  const generic = {'new agent', 'new chat', 'untitled', 'untitled chat'};
  if (generic.contains(text.toLowerCase())) return null;
  return _clip(text.replaceAll(RegExp(r'\s+'), ' '));
}

String? _usablePrompt(String? raw) {
  if (raw == null) return null;
  final query = RegExp(
    r'<user_query>\s*([\s\S]*?)\s*</user_query>',
    caseSensitive: false,
  ).firstMatch(raw);
  if (query == null && raw.trimLeft().startsWith('<')) return null;
  return _usableTitle(query?.group(1) ?? raw);
}

String _clip(String text) =>
    text.length <= 80 ? text : '${text.substring(0, 79)}…';

String _shortId(String id) => id.length <= 8 ? id : id.substring(0, 8);

String? _string(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime? _time(Object? raw) {
  if (raw is! num) return null;
  final value = raw.toInt();
  if (value <= 0) return null;
  final ms = value < 100000000000 ? value * 1000 : value;
  return DateTime.fromMillisecondsSinceEpoch(ms);
}

DateTime _mtime(File file) {
  try {
    return file.statSync().modified;
  } on FileSystemException {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

bool _safeId(String id) =>
    id.isNotEmpty &&
    !id.contains('/') &&
    !id.contains(r'\') &&
    !id.contains('..') &&
    id != '.' &&
    id != '..';

List<String> _pathVariants(String path) {
  final variants = <String>{path, cursorProjectKey(path)};
  final dir = Directory(cursorProjectKey(path));
  if (dir.existsSync()) {
    try {
      variants.add(dir.resolveSymbolicLinksSync());
      variants.add(cursorProjectKey(dir.resolveSymbolicLinksSync()));
    } on FileSystemException {
      // The folder is not there; the stored hash is enough.
    }
  }
  return variants.toList();
}

List<SessionRecord> _newestFirst(List<SessionRecord> sessions) {
  final copy = [...sessions];
  copy.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return copy;
}
