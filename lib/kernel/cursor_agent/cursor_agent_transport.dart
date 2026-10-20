import 'dart:async';

/// Cursor Agent's side of the adapter: JSON-RPC 2.0 with `agent acp` over
/// stdio, one message per line.
///
/// https://cursor.com/docs/cli/acp
/// https://agentclientprotocol.com/protocol/v1/overview
abstract interface class CursorAgentTransport {
  /// Responses (`id` + `result` or `error`), notifications (`method` +
  /// `params`, no `id`) and server requests (`id` + `method` + `params`).
  Stream<Map<String, Object?>> get messages;

  /// Writes a request, a notification, or the response to a server request.
  /// The kernel adds the JSON-RPC envelope.
  void write(Map<String, Object?> message);

  /// Absolute project directory the process was started in. ACP `cwd` has
  /// to be absolute.
  String get cwd;

  /// Ends the process.
  void close();

  /// Completes once the process is gone, closed or not.
  Future<void> get exited;
}

/// How to start `agent acp` for one session.
class CursorAgentLaunch {
  const CursorAgentLaunch({
    required this.cwd,
    this.executable,
    this.throughShell = false,
    this.processArguments = const ['acp'],
  });

  /// The project directory. Made absolute before the process starts.
  final String cwd;

  /// The `agent` binary. Null: [locateCursorAgent] looks it up.
  final String? executable;

  /// A Windows npm-style `.cmd` / `.bat` shim, which only the shell runs.
  final bool throughShell;

  /// Flags before the `acp` subcommand (`--workspace`, `--add-dir`, …).
  final List<String> processArguments;
}

typedef CursorAgentStarter = Future<CursorAgentTransport> Function(
  CursorAgentLaunch launch,
);

/// Methods this adapter sends or handles.
///
/// The ones under `session/` and `initialize` / `authenticate` are ACP.
/// The `cursor/` ones are Cursor's extension methods. `transport/exit` is
/// not on the wire: the process transport adds it after the CLI exits so
/// the kernel can tell a dead process from a notification.
///
/// https://cursor.com/docs/cli/acp
/// https://agentclientprotocol.com/protocol/v1/schema
abstract final class CursorAcp {
  static const initialize = 'initialize';
  static const authenticate = 'authenticate';
  static const sessionNew = 'session/new';
  static const sessionLoad = 'session/load';
  static const sessionPrompt = 'session/prompt';
  static const sessionCancel = 'session/cancel';
  static const sessionSetMode = 'session/set_mode';
  static const sessionUpdate = 'session/update';
  static const requestPermission = 'session/request_permission';
  static const askQuestion = 'cursor/ask_question';
  static const createPlan = 'cursor/create_plan';
  static const updateTodos = 'cursor/update_todos';
  static const task = 'cursor/task';
  static const generateImage = 'cursor/generate_image';

  /// Local sentinel, not an ACP method.
  static const transportExit = 'transport/exit';

  /// What the minimal client in the ACP docs sends.
  static const protocolVersion = 1;

  static const authMethod = 'cursor_login';
}

/// A JSON object, whatever [jsonDecode] actually built.
Map<String, Object?>? cursorJsonMap(Object? value) {
  if (value is! Map) return null;
  return Map<String, Object?>.from(value);
}

/// Cursor Agent cannot start, or a request failed before a session existed.
class CursorAgentUnavailable implements Exception {
  const CursorAgentUnavailable(this.message, {this.detail});

  final String message;
  final String? detail;

  @override
  String toString() => message;
}

/// The project folder the agent was to work in is not there.
class CursorAgentFolderGone extends CursorAgentUnavailable {
  const CursorAgentFolderGone(this.folder)
    : super('The project folder is not there');

  final String folder;
}

/// A JSON-RPC error, or a request that never answered.
class CursorAgentRpcException implements Exception {
  const CursorAgentRpcException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() => message;
}
