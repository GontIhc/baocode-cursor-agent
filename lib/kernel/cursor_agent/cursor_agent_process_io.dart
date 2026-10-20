import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'cursor_agent_locator.dart';
import 'cursor_agent_transport.dart';

/// `agent acp` as a child process. Stdout is newline-delimited JSON-RPC;
/// stderr is kept for the failure report. A [CursorAcp.transportExit]
/// notification is added once the process and its stdout are both done.
/// That notification is local: it is not part of ACP.
///
/// TODO: processes left behind by a crash are not reaped. Claude Code's
/// transport keeps a pid file for that; this first pass only kills the
/// child it still holds.
class CursorAgentProcess implements CursorAgentTransport {
  CursorAgentProcess._(this._process, {required this.cwd, this.executable}) {
    _process.stdout
        .transform(_decoder)
        .transform(const LineSplitter())
        .listen(_line, onError: _undecodable, onDone: _stdoutDone);
    _process.stderr
        .transform(_decoder)
        .transform(const LineSplitter())
        .listen(_stderrLine, onError: _undecodable);
    unawaited(_process.exitCode.then(_exited));
  }

  /// Not strict: a line that is not UTF-8 takes the replacement character
  /// and is kept as a non-protocol line, the way Claude's transport does.
  static const _decoder = Utf8Decoder(allowMalformed: true);

  static Future<CursorAgentTransport> start(CursorAgentLaunch launch) async {
    if (!Directory(launch.cwd).existsSync()) {
      throw CursorAgentFolderGone(launch.cwd);
    }
    final cwd = Directory(launch.cwd).absolute.path;
    final executable = launch.executable == null
        ? await locateCursorAgent()
        : CursorAgentExecutable(
            launch.executable!,
            throughShell: launch.throughShell,
          );
    try {
      final process = await Process.start(
        executable.path,
        const ['acp'],
        workingDirectory: cwd,
        runInShell: executable.throughShell,
      );
      return CursorAgentProcess._(
        process,
        cwd: cwd,
        executable: executable.path,
      );
    } on ProcessException catch (error) {
      throw CursorAgentUnavailable(
        'Cursor Agent could not start',
        detail: '${executable.path}\n${error.message}',
      );
    }
  }

  final Process _process;

  @override
  final String cwd;

  /// The binary that was run, named in a failure report.
  final String? executable;

  /// Single-subscription, so lines printed before the kernel listens are
  /// buffered rather than dropped. [add] after the listener is cancelled
  /// (release, restart) is ignored.
  final StreamController<Map<String, Object?>> _messages = StreamController();

  final List<String> _stderr = [];
  static const _stderrLines = 30;

  int? _exitCode;
  bool _stdoutClosed = false;
  bool _finished = false;
  bool _closed = false;

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  @override
  Future<void> get exited => _process.exitCode.then((_) {});

  void _undecodable(Object error) => _stderrLine('$error');

  void _line(String line) {
    if (line.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(line);
      final message = cursorJsonMap(decoded);
      if (message != null) {
        _emit(message);
        return;
      }
    } on FormatException {
      // Not protocol: kept for the failure report.
    }
    _stderrLine(line);
  }

  void _stderrLine(String line) {
    _stderr.add(line);
    if (_stderr.length > _stderrLines) _stderr.removeAt(0);
  }

  void _stdoutDone() {
    _stdoutClosed = true;
    _finish();
  }

  void _exited(int code) {
    _exitCode = code;
    _finish();
  }

  /// The exit follows the last stdout line, so a turn's last update is
  /// delivered before the kernel hears that the process is gone.
  void _finish() {
    final code = _exitCode;
    if (code == null || !_stdoutClosed || _finished || _messages.isClosed) {
      return;
    }
    _finished = true;
    _emit({
      'method': CursorAcp.transportExit,
      'params': {
        'code': code,
        'stderr': _stderr.join('\n'),
        'executable': ?executable,
      },
    });
    unawaited(_messages.close().catchError((_) {}));
  }

  void _emit(Map<String, Object?> message) {
    if (_messages.isClosed) return;
    try {
      _messages.add(message);
    } on StateError {
      // The kernel cancelled its subscription.
    }
  }

  @override
  void write(Map<String, Object?> message) {
    if (_exitCode != null || _closed) return;
    try {
      _process.stdin.writeln(jsonEncode(message));
    } on StateError {
      // Closed under us: the exit message follows.
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    unawaited(_process.stdin.close().catchError((_) {}));
    _process.kill();
  }
}

Future<CursorAgentTransport> startCursorAgent(CursorAgentLaunch launch) =>
    CursorAgentProcess.start(launch);
