import '../agent_kernel.dart';

/// No CLI session store on the web.
Future<List<ProjectRecord>> cursorCliProjects({List<String>? roots}) async =>
    const [];

Future<List<SessionRecord>> cursorCliSessionsIn(
  String cwd, {
  List<String>? roots,
}) async => const [];

Future<void> deleteCursorCliSession(String id, {List<String>? roots}) async {}
