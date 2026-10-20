import 'dart:async';

import 'package:flutter/material.dart';

import '../../chat/chat_models.dart';
import '../agent_kernel.dart';
import '../kernel_event.dart';
import '../kernel_types.dart';
import 'cursor_agent_model_setting.dart';
import 'cursor_agent_process.dart';
import 'cursor_agent_translator.dart';
import 'cursor_agent_transport.dart';
import 'cursor_agent_workspace.dart';

/// Adapts Cursor Agent CLI (`agent acp`) to [AgentKernel].
///
/// One session, one process. The process speaks ACP over stdio JSON-RPC
/// (newline-delimited), the same shape as the Codex `codex app-server`
/// adapter: the client sends requests, the CLI sends notifications and
/// server requests (permissions, questions). This is not Claude Code's
/// `--input-format stream-json` control channel. Print / `stream-json` is
/// a one-shot scripting mode and is not used here.
///
/// https://cursor.com/docs/cli/acp
/// https://cursor.com/docs/cli/headless
/// https://agentclientprotocol.com/protocol/v1/overview
///
/// Wired in this pass: initialize, `authenticate` (`cursor_login`),
/// `session/new` or `session/load`, `session/prompt`, `session/cancel`,
/// `session/set_mode`, text and thought chunks, tool calls, plans, usage,
/// permission replies, and the documented `cursor/ask_question` and
/// `cursor/create_plan` bodies.
class CursorAgentKernel
    with KernelEventSource
    implements AgentKernel, SelectsMode {
  CursorAgentKernel(this.descriptor, this._context, {CursorAgentStarter? start})
    : _start = start ?? startCursorAgent {
    mode = LocalChoice([...modes], onChanged: _modeChanged);
    final initial = _context.settings[KernelChoiceKind.mode.name];
    if (initial != null && initial.isNotEmpty) {
      mode.reported = initial;
      _modeTouched = true;
    }
    _translator = CursorAgentTranslator(
      emit: emit,
      nextSeq: () => nextSeq,
      onMode: _modeReported,
    );
  }

  @override
  final KernelDescriptor descriptor;

  final KernelContext _context;
  final CursorAgentStarter _start;

  /// Modes Cursor's ACP page names. Replaced when `session/new` returns
  /// its own `modes` list.
  ///
  /// https://cursor.com/docs/cli/acp
  static const modes = <KernelOption>[
    KernelOption(
      'agent',
      'Agent',
      Icons.build_rounded,
      'Edit the workspace, with approvals',
    ),
    KernelOption(
      'plan',
      'Plan',
      Icons.account_tree_outlined,
      'Plan first; read-only until you build',
    ),
    KernelOption(
      'ask',
      'Ask',
      Icons.chat_bubble_outline_rounded,
      'Q&A, read-only',
    ),
  ];

  @override
  late final LocalChoice mode;

  late final CursorAgentTranslator _translator;

  KernelHealth _health = KernelHealth.idle;
  CursorAgentTransport? _transport;
  StreamSubscription<Map<String, Object?>>? _subscription;
  Future<void>? _booting;
  final Completer<void> _stopped = Completer<void>();

  int _nextId = 0;
  final Map<Object, Completer<Map<String, Object?>>> _responses = {};
  String? _sessionId;
  bool _loadSession = false;
  bool _additionalDirectories = false;

  /// The mode the agent last confirmed, so a repeat pick is not sent.
  String? _agentMode;
  bool _modeTouched = false;

  String? _turn;
  DateTime? _turnStarted;
  final Set<String> _sentTurns = {};
  final Map<String, _Pending> _pending = {};

  bool _disposed = false;
  bool _sawExit = false;

  /// Bumped when the process is dropped, so a boot still in flight does not
  /// attach to the next one.
  int _epoch = 0;
  bool _releaseWhenIdle = false;
  String _stderr = '';

  @override
  KernelHealth get health => _health;

  @override
  String? get sessionId => _sessionId;

  @override
  Future<void> get stopped => _stopped.future;

  @override
  void prepare() {
    _releaseWhenIdle = false;
    if (_health.status == KernelHealthStatus.failed) return;
    if (_transport != null || _booting != null) return;
    unawaited(_ensureReady().then<void>((_) {}, onError: (_) {}));
  }

  @override
  void restart() {
    final turn = _turn;
    _shutdown(keepSession: _sessionId != null);
    if (turn != null) _endTurn(turn, interrupted: true);
    _health = KernelHealth.idle;
    emitInfoChanged();
    prepare();
  }

  @override
  void release() {
    if (_turn != null) {
      _releaseWhenIdle = true;
      return;
    }
    _shutdown(keepSession: true);
    _health = KernelHealth.idle;
    emitInfoChanged();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    unawaited(_subscription?.cancel());
    _subscription = null;
    final transport = _transport;
    _transport = null;
    transport?.close();
    if (transport == null) {
      _markStopped();
    } else {
      unawaited(transport.exited.whenComplete(_markStopped));
    }
    closeEvents();
  }

  @override
  void send(KernelTurn turn) {
    if (!_sentTurns.add(turn.id)) return;
    if (_turn != null) cancel();
    _turn = turn.id;
    _turnStarted = DateTime.now();
    emit(TurnStarted(nextSeq, turn.id));
    emit(
      ItemUpserted(
        nextSeq,
        turn.id,
        UserMessageItem(text: turn.text, images: turn.images),
      ),
    );
    unawaited(_prompt(turn));
  }

  @override
  void answer(String requestId, InteractionAnswer answer) {
    final pending = _pending.remove(requestId);
    if (pending == null) return;
    emit(InteractionResolved(nextSeq, requestId));
    switch (pending) {
      case _PermissionPending():
        _answerPermission(pending, answer);
      case _QuestionPending():
        _answerQuestion(pending, answer);
      case _PlanPending():
        _answerPlan(pending, answer);
    }
  }

  @override
  void cancel() {
    final turn = _turn;
    if (turn == null) return;
    final session = _sessionId;
    if (session != null) {
      _notify(CursorAcp.sessionCancel, {'sessionId': session});
    }
    _cancelPending();
    _endTurn(turn, interrupted: true);
  }

  Future<void> _prompt(KernelTurn turn) async {
    try {
      await _ensureReady();
      if (_disposed || _turn != turn.id) return;
      final session = _sessionId;
      if (session == null) {
        throw const CursorAgentUnavailable('Cursor Agent has no session');
      }
      final result = await _request(CursorAcp.sessionPrompt, {
        'sessionId': session,
        'prompt': [
          {'type': 'text', 'text': turn.text},
          for (final note in turn.notes)
            if (note.isNotEmpty) {'type': 'text', 'text': note},
        ],
      });
      if (_turn != turn.id) return;
      _endTurn(turn.id, interrupted: result['stopReason'] == 'cancelled');
    } on _BootCancelled {
      // restart() or dispose() dropped this process.
    } on Object catch (error) {
      if (_disposed || _turn != turn.id) return;
      _notice(_errorText(error));
      _endTurn(turn.id, interrupted: true);
    }
  }

  Future<void> _ensureReady() {
    final pending = _booting;
    if (pending != null) return pending;
    final run = _boot();
    _booting = run;
    return run;
  }

  Future<void> _boot() async {
    final epoch = _epoch;
    try {
      final cwd = _context.cwd;
      if (cwd == null || cwd.isEmpty) {
        throw const CursorAgentUnavailable(
          'Open a project folder to use Cursor Agent',
        );
      }
      _setHealth(const KernelHealth(KernelHealthStatus.starting));
      _sawExit = false;
      final resolved = resolveCursorAgentWorkspace(_context);
      final transport = await _start(
        CursorAgentLaunch(
          cwd: cwd,
          processArguments: resolved.processArguments,
          model:
              CursorAgentModelSetting.current() ??
              CursorAgentModelSetting.parse(
                _context.settings[CursorAgentModelSetting.settingKey],
              ),
        ),
      );
      if (_disposed || epoch != _epoch) {
        transport.close();
        if (_disposed) _markStopped();
        throw const _BootCancelled();
      }
      _transport = transport;
      _subscription = transport.messages.listen(
        (message) {
          if (!identical(_transport, transport)) return;
          _receive(message);
        },
        onError: (Object error) {
          if (identical(_transport, transport)) _stderr = '$error';
        },
        onDone: () {
          if (!identical(_transport, transport) || _sawExit) return;
          _onExit({'code': -1, 'stderr': _stderr});
        },
      );
      final initialized = await _request(CursorAcp.initialize, {
        'protocolVersion': CursorAcp.protocolVersion,
        'clientCapabilities': {
          'fs': {'readTextFile': false, 'writeTextFile': false},
          'terminal': false,
        },
        'clientInfo': const {'name': 'baocode', 'version': '1.5.0'},
      }, timeout: const Duration(seconds: 20));
      _readCapabilities(initialized);
      try {
        await _request(CursorAcp.authenticate, const {
          'methodId': CursorAcp.authMethod,
        }, timeout: const Duration(minutes: 2));
      } on CursorAgentRpcException catch (error) {
        // TODO: confirm whether an already logged-in CLI still requires
        // this call, or rejects it. The published minimal client always
        // sends it. https://cursor.com/docs/cli/acp
        throw CursorAgentRpcException(
          '${error.message}\nSign in with `agent login`, or set CURSOR_API_KEY.',
          code: error.code,
        );
      }
      await _openSession();
      if (_disposed || epoch != _epoch) throw const _BootCancelled();
      _setHealth(KernelHealth.ready);
      await _applyMode(mode.selected);
    } on _BootCancelled {
      rethrow;
    } on Object catch (error) {
      if (epoch != _epoch || _disposed) throw const _BootCancelled();
      _booting = null;
      _fail(error);
      final transport = _transport;
      _transport = null;
      unawaited(_subscription?.cancel());
      _subscription = null;
      transport?.close();
      rethrow;
    }
  }

  Future<void> _openSession() async {
    final resume = _sessionId ?? _context.resume?.id;
    final params = <String, Object?>{
      'cwd': _transport!.cwd,
      'mcpServers': const <Object?>[],
      // Cursor reads `.cursor/mcp.json` itself when launched in the
      // project. This client does not inject servers.
    };
    final resolved = resolveCursorAgentWorkspace(_context);
    if (!resolved.usesCliWorkspaceFlags) {
      final extra = _workspaceFolders();
      if (_additionalDirectories && extra.isNotEmpty) {
        params['additionalDirectories'] = extra;
      }
    }
    if (resume != null && resume.isNotEmpty && _loadSession) {
      _sessionId = resume;
      _translator.replaying = true;
      try {
        final loaded = await _request(CursorAcp.sessionLoad, {
          ...params,
          'sessionId': resume,
        }, timeout: const Duration(seconds: 30));
        _noteModes(loaded);
        return;
      } on CursorAgentRpcException catch (error) {
        _sessionId = null;
        _notice('Could not load Cursor session $resume: ${error.message}');
      } finally {
        _translator.replaying = false;
      }
    } else if (resume != null && resume.isNotEmpty && !_loadSession) {
      // TODO: `session/resume` (no replay) when the CLI advertises
      // sessionCapabilities.resume. Cursor's page names `session/load`
      // and not `session/resume`. https://cursor.com/docs/cli/acp
      _notice(
        'This Cursor Agent build did not offer session loading. '
        'Starting a new session.',
      );
    }
    final created = await _request(
      CursorAcp.sessionNew,
      params,
      timeout: const Duration(seconds: 30),
    );
    final id = created['sessionId'];
    if (id is! String || id.isEmpty) {
      throw const CursorAgentRpcException(
        'session/new did not return a sessionId',
      );
    }
    _sessionId = id;
    _noteModes(created);
  }

  void _readCapabilities(Map<String, Object?> result) {
    final caps = cursorJsonMap(result['agentCapabilities']);
    if (caps == null) return;
    _loadSession = caps['loadSession'] == true;
    final sessionCaps = cursorJsonMap(caps['sessionCapabilities']);
    _additionalDirectories =
        sessionCaps != null && sessionCaps['additionalDirectories'] != null;
  }

  List<String> _workspaceFolders() {
    final folders = _context.workspace?.call()?.folders ?? const [];
    final cwd = _transport?.cwd;
    return [
      for (final folder in folders)
        if (folder != cwd && _absolute(folder)) folder,
    ];
  }

  bool _absolute(String path) =>
      path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);

  void _noteModes(Map<String, Object?> result) {
    final modesState = cursorJsonMap(result['modes']);
    if (modesState == null) return;
    final available = modesState['availableModes'];
    if (available is List && available.isNotEmpty) {
      final options = <KernelOption>[];
      for (final raw in available) {
        final mode = cursorJsonMap(raw);
        final id = mode?['id'];
        if (id is! String || id.isEmpty) continue;
        final name = mode?['name'];
        final description = mode?['description'];
        options.add(
          KernelOption(
            id,
            name is String && name.isNotEmpty ? name : id,
            _modeIcon(id),
            description is String ? description : '',
          ),
        );
      }
      if (options.isNotEmpty) mode.options = options;
    }
    final current = modesState['currentModeId'];
    if (current is String && current.isNotEmpty) {
      _agentMode = current;
      if (!_modeTouched) mode.reported = current;
    }
    emitInfoChanged();
  }

  void _modeChanged(String id) {
    _modeTouched = true;
    emitInfoChanged();
    unawaited(_applyMode(id));
  }

  void _modeReported(String id) {
    _agentMode = id;
    mode.reported = id;
    emitInfoChanged();
  }

  /// ACP `session/set_mode`. Cursor documents the mode ids (`agent`,
  /// `plan`, `ask`) and not this method; the method is the ACP one. A CLI
  /// that rejects it keeps the choice locally.
  ///
  /// https://cursor.com/docs/cli/acp
  /// https://agentclientprotocol.com/protocol/v1/session-modes
  Future<void> _applyMode(String? id) async {
    final session = _sessionId;
    if (id == null || id.isEmpty || session == null || id == _agentMode) {
      return;
    }
    try {
      await _request(CursorAcp.sessionSetMode, {
        'sessionId': session,
        'modeId': id,
      }, timeout: const Duration(seconds: 15));
      _agentMode = id;
    } on CursorAgentRpcException {
      // Left as the local choice. The next current_mode_update wins.
    }
  }

  IconData _modeIcon(String id) {
    for (final option in modes) {
      if (option.id == id) return option.icon;
    }
    return Icons.tune_rounded;
  }

  void _receive(Map<String, Object?> message) {
    final method = message['method'];
    if (method == CursorAcp.transportExit) {
      _onExit(cursorJsonMap(message['params']) ?? const {});
      return;
    }
    if (method is String) {
      final params = cursorJsonMap(message['params']) ?? const {};
      if (message.containsKey('id')) {
        _serverRequest(message['id'], method, params);
        return;
      }
      _notification(method, params);
      return;
    }
    final id = message['id'];
    final waiting = id == null ? null : _responses.remove(id);
    if (waiting == null) return;
    final error = cursorJsonMap(message['error']);
    if (error != null) {
      final text = error['message'];
      final code = error['code'];
      waiting.completeError(
        CursorAgentRpcException(
          text is String && text.isNotEmpty ? text : 'Request failed',
          code: code is int ? code : null,
        ),
      );
      return;
    }
    waiting.complete(cursorJsonMap(message['result']) ?? const {});
  }

  void _notification(String method, Map<String, Object?> params) {
    switch (method) {
      case CursorAcp.sessionUpdate:
        final session = params['sessionId'];
        if (_sessionId != null && session is String && session != _sessionId) {
          return;
        }
        final update = cursorJsonMap(params['update']);
        if (update != null) _translator.sessionUpdate(update);
      case CursorAcp.updateTodos:
        _translator.updateTodos(params);
      case CursorAcp.task:
        _translator.task(params);
      case CursorAcp.generateImage:
        _translator.generateImage(params);
      default:
        // TODO: fs/* and terminal/* are declined at initialize
        // (clientCapabilities false). A notification we do not know is
        // ignored. https://cursor.com/docs/cli/acp
        break;
    }
  }

  void _serverRequest(
    Object? rpcId,
    String method,
    Map<String, Object?> params,
  ) {
    switch (method) {
      case CursorAcp.requestPermission:
        _askPermission(rpcId, params);
      case CursorAcp.askQuestion:
        _askQuestion(rpcId, params);
      case CursorAcp.createPlan:
        _askPlan(rpcId, params);
      case CursorAcp.updateTodos:
        _translator.updateTodos(params);
        _respond(rpcId, {
          'outcome': {'outcome': 'accepted', 'todos': _translator.todosWire},
        });
      case CursorAcp.task:
        _translator.task(params);
        // Documented as a notification. If Cursor sends an id anyway, ack
        // so the turn cannot block. TODO: confirm against a live trace.
        _respond(rpcId, {
          'outcome': {
            'outcome': 'completed',
            if (params['agentId'] is String) 'agentId': params['agentId'],
            if (params['durationMs'] is num) 'durationMs': params['durationMs'],
          },
        });
      case CursorAcp.generateImage:
        _translator.generateImage(params);
        final path = params['filePath'];
        if (path is String && path.isNotEmpty) {
          _respond(rpcId, {
            'outcome': {'outcome': 'generated', 'filePath': path},
          });
        } else {
          _respond(rpcId, {
            'outcome': {'outcome': 'cancelled'},
          });
        }
      default:
        _respondError(rpcId, -32601, 'Method not implemented: $method');
    }
  }

  void _askPermission(Object? rpcId, Map<String, Object?> params) {
    final choice = cursorPermissionChoice(params);
    final id = 'perm:$rpcId';
    _pending[id] = _PermissionPending(
      rpcId,
      allowOnceId: choice.allowOnceId,
      allowAlwaysId: choice.allowAlwaysId,
      rejectId: choice.rejectId,
    );
    emit(
      InteractionRequested(
        nextSeq,
        ApprovalRequest(
          id: id,
          title: choice.title,
          toolName: choice.toolName,
          reason: choice.reason,
          preview: choice.preview,
          alwaysAllowLabel: choice.alwaysAllowLabel,
        ),
      ),
    );
  }

  void _askQuestion(Object? rpcId, Map<String, Object?> params) {
    final form = cursorQuestionForm(params);
    if (form == null) {
      _respond(rpcId, {
        'outcome': {'outcome': 'skipped'},
      });
      return;
    }
    final id = 'ask:$rpcId';
    _pending[id] = _QuestionPending(rpcId, form.questions);
    emit(
      InteractionRequested(
        nextSeq,
        QuestionRequest(
          id: id,
          title: form.title,
          questions: [for (final question in form.questions) question.question],
        ),
      ),
    );
  }

  void _askPlan(Object? rpcId, Map<String, Object?> params) {
    final name = params['name'];
    final overview = params['overview'];
    final previewBody = cursorCreatePlanPreview(params);
    final title = name is String && name.isNotEmpty ? name : 'Plan';
    final toolCallId = params['toolCallId'];
    final itemId = 'plan:${toolCallId ?? rpcId}';
    if (previewBody.isNotEmpty) {
      emit(ItemUpserted(nextSeq, itemId, AssistantTextItem(previewBody)));
    }
    final todos = cursorCreatePlanTodos(params);
    if (todos.isNotEmpty) emit(TodosReported(nextSeq, todos));
    final planUri = params['planUri'];
    // TODO: StartsPlans / open planUri in the IDE when the CLI returns one.
    final id = 'plan:$rpcId';
    _pending[id] = _PlanPending(
      rpcId,
      planUri: planUri is String && planUri.isNotEmpty ? planUri : null,
    );
    emit(
      InteractionRequested(
        nextSeq,
        ApprovalRequest(
          id: id,
          title: title,
          toolName: 'create_plan',
          reason: overview is String && overview.isNotEmpty ? overview : null,
          preview: previewBody.isEmpty ? null : TextPreview(previewBody),
          allowOnceLabel: 'Confirm plan',
          denyLabel: 'Reject plan',
          denyHint: 'Tell the agent what to change',
        ),
      ),
    );
  }

  void _answerPermission(_PermissionPending pending, InteractionAnswer answer) {
    final optionId = switch (answer) {
      ApprovalAnswer(decision: ApprovalDecision.allowOnce) =>
        pending.allowOnceId,
      ApprovalAnswer(decision: ApprovalDecision.allowAlways) =>
        pending.allowAlwaysId ?? pending.allowOnceId,
      _ => pending.rejectId,
    };
    _respond(pending.rpcId, {
      'outcome': {'outcome': 'selected', 'optionId': optionId},
    });
  }

  void _answerQuestion(_QuestionPending pending, InteractionAnswer answer) {
    if (answer is! QuestionAnswer || answer.skipped) {
      _respond(pending.rpcId, {
        'outcome': {'outcome': 'skipped'},
      });
      return;
    }
    _respond(pending.rpcId, {
      'outcome': {
        'outcome': 'answered',
        'answers': [
          for (var i = 0; i < pending.questions.length; i++)
            {
              'questionId': pending.questions[i].id,
              'selectedOptionIds': [
                for (final label
                    in i < answer.picks.length
                        ? answer.picks[i]
                        : const <String>[])
                  ?pending.questions[i].labelToId[label],
              ],
            },
        ],
      },
    });
  }

  void _answerPlan(_PlanPending pending, InteractionAnswer answer) {
    final outcome = switch (answer) {
      ApprovalAnswer(decision: ApprovalDecision.deny, :final message) => {
        'outcome': 'rejected',
        if (message != null && message.isNotEmpty) 'reason': message,
      },
      ApprovalAnswer() => {
        'outcome': 'accepted',
        if (pending.planUri != null) 'planUri': pending.planUri,
      },
      _ => {'outcome': 'rejected'},
    };
    _respond(pending.rpcId, {'outcome': outcome});
  }

  void _cancelPending() {
    for (final id in [..._pending.keys]) {
      final pending = _pending.remove(id);
      if (pending == null) continue;
      emit(InteractionResolved(nextSeq, id));
      _respond(pending.rpcId, {
        'outcome': {'outcome': 'cancelled'},
      });
    }
  }

  Future<Map<String, Object?>> _request(
    String method,
    Map<String, Object?> params, {
    Duration? timeout,
  }) async {
    final id = ++_nextId;
    final response = Completer<Map<String, Object?>>();
    _responses[id] = response;
    _write({'id': id, 'method': method, 'params': params});
    try {
      if (timeout == null) return await response.future;
      return await response.future.timeout(timeout);
    } on TimeoutException {
      _responses.remove(id);
      throw CursorAgentRpcException('Timed out waiting for $method');
    }
  }

  void _notify(String method, Map<String, Object?> params) {
    _write({'method': method, 'params': params});
  }

  void _respond(Object? id, Map<String, Object?> result) {
    _write({'id': id, 'result': result});
  }

  void _respondError(Object? id, int code, String message) {
    _write({
      'id': id,
      'error': {'code': code, 'message': message},
    });
  }

  void _write(Map<String, Object?> message) {
    final transport = _transport;
    if (transport == null || _disposed) return;
    transport.write({'jsonrpc': '2.0', ...message});
  }

  void _endTurn(String turn, {required bool interrupted}) {
    if (_turn != turn) return;
    _turn = null;
    _translator.finish();
    final started = _turnStarted;
    _turnStarted = null;
    emit(
      TurnEnded(
        nextSeq,
        turn,
        interrupted: interrupted,
        worked: started == null ? null : DateTime.now().difference(started),
      ),
    );
    if (_releaseWhenIdle) {
      _releaseWhenIdle = false;
      release();
    }
  }

  void _notice(String text) {
    final seq = nextSeq;
    emit(ItemUpserted(seq, 'notice:$seq', NoticeItem(NoticeKind.error, text)));
  }

  void _onExit(Map<String, Object?> params) {
    if (_sawExit) return;
    _sawExit = true;
    final stderr = params['stderr'];
    if (stderr is String) _stderr = stderr;
    if (_turn != null) {
      _notice('Cursor Agent stopped');
      _endTurn(_turn!, interrupted: true);
    }
    if (!_disposed) {
      final code = params['code'];
      _fail(
        CursorAgentUnavailable(
          code == 0 ? 'Cursor Agent stopped' : 'Cursor Agent exited ($code)',
          detail: _stderr.isEmpty ? null : _stderr,
        ),
      );
      _booting = null;
      _transport = null;
    }
    if (_disposed) _markStopped();
  }

  void _shutdown({required bool keepSession}) {
    _epoch++;
    final transport = _transport;
    _transport = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _booting = null;
    _responses.clear();
    if (!keepSession) _sessionId = null;
    transport?.close();
  }

  void _fail(Object error) {
    final (message, detail, folder) = switch (error) {
      CursorAgentFolderGone(:final folder) => (
        'The project folder is not there',
        null,
        folder,
      ),
      CursorAgentUnavailable(:final message, :final detail) => (
        message,
        detail,
        null,
      ),
      CursorAgentRpcException(:final message) => (message, null, null),
      _ => ('Cursor Agent could not start', '$error', null),
    };
    _health = KernelHealth(
      KernelHealthStatus.failed,
      message: message,
      detail: detail,
      missingFolder: folder,
    );
    emitInfoChanged();
  }

  void _setHealth(KernelHealth health) {
    _health = health;
    emitInfoChanged();
  }

  String _errorText(Object error) => switch (error) {
    CursorAgentUnavailable(:final message, :final detail) =>
      detail == null || detail.isEmpty ? message : '$message\n$detail',
    _ => '$error',
  };

  void _markStopped() {
    if (!_stopped.isCompleted) _stopped.complete();
  }
}

sealed class _Pending {
  const _Pending(this.rpcId);

  final Object? rpcId;
}

final class _PermissionPending extends _Pending {
  const _PermissionPending(
    super.rpcId, {
    required this.allowOnceId,
    required this.allowAlwaysId,
    required this.rejectId,
  });

  final String allowOnceId;
  final String? allowAlwaysId;
  final String rejectId;
}

final class _QuestionPending extends _Pending {
  const _QuestionPending(super.rpcId, this.questions);

  final List<CursorQuestionBinding> questions;
}

final class _PlanPending extends _Pending {
  const _PlanPending(super.rpcId, {this.planUri});

  final String? planUri;
}

/// The process this boot started was dropped by [CursorAgentKernel.restart]
/// or [CursorAgentKernel.dispose].
final class _BootCancelled implements Exception {
  const _BootCancelled();
}
