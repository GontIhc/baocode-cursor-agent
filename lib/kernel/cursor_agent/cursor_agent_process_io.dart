import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../platform/child_process_registry.dart';
import '../../platform/data_dir.dart';
import 'cursor_agent_locator.dart';
import 'cursor_agent_transport.dart';

/// `agent acp` as a child process. Stdout is newline-delimited JSON-RPC;
/// stderr is kept for the failure report. A [CursorAcp.transportExit]
/// notification is added once the process and its stdout are both done.
/// That notification is local: it is not part of ACP.
class CursorAgentProcess implements CursorAgentTransport {
  CursorAgentProcess._(this._process, {required this.cwd, this.executable}) {
    _live.add(this);
    unawaited(registry.add(_process.pid));
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

  /// Where the running processes are kept track of across runs.
  @visibleForTesting
  static CursorAgentProcessRegistry registry = CursorAgentProcessRegistry(
    file: File(DataDirectory.current.processRegistryFile('cursor-agent')),
  );

  /// The processes this run of the app started and that still run.
  static final Set<CursorAgentProcess> _live = {};

  /// Ends every Cursor Agent process this run started, and waits (up to
  /// [timeout] each) for them to go: done as the app quits.
  static Future<void> stopAll({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    await Future.wait([
      for (final transport in [..._live]) transport._stop(timeout),
    ]);
    await registry.flush();
  }

  /// Ends the processes an earlier run left behind; see
  /// [CursorAgentProcessRegistry].
  static Future<void> reapLeftovers() => registry.reaped;

  Future<void> _stop(Duration timeout) async {
    close();
    try {
      await _process.exitCode.timeout(timeout);
    } on TimeoutException {
      _process.kill(ProcessSignal.sigkill);
    }
  }

  static Future<CursorAgentTransport> start(CursorAgentLaunch launch) async {
    await registry.reaped;
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
      final arguments = launch.processArguments.isEmpty
          ? const ['acp']
          : launch.processArguments;
      final process = await Process.start(
        executable.path,
        arguments,
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
    _live.remove(this);
    unawaited(registry.remove(_process.pid));
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
    if (Platform.isWindows) {
      unawaited(_endTree());
    } else {
      _process.kill();
    }
  }

  /// Windows ends a killed process alone, and the MCP servers it started
  /// go on without it: given a moment to end them itself, its input
  /// closed, then ended with all it started.
  Future<void> _endTree() async {
    final ended = await _process.exitCode
        .timeout(const Duration(seconds: 1))
        .then((_) => true, onError: (Object _) => false);
    if (ended) return;
    try {
      await Process.run('taskkill', ['/pid', '${_process.pid}', '/T', '/F']);
    } on ProcessException {
      _process.kill();
    }
  }
}

/// The Cursor Agent processes the app has running
/// (`cursor-agent-processes.json`); see [ChildProcessRegistry].
class CursorAgentProcessRegistry extends ChildProcessRegistry {
  CursorAgentProcessRegistry({
    required super.file,
    super.ownPid,
    super.lookup,
    super.signal,
  }) : super(recognizes: _isCursorAgent);

  static bool _isCursorAgent(String command) {
    final lower = command.toLowerCase();
    return lower.contains('agent') && lower.contains('acp');
  }
}

Future<CursorAgentTransport> startCursorAgent(CursorAgentLaunch launch) =>
    CursorAgentProcess.start(launch);
