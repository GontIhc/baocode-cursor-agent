import 'dart:async';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/cursor_agent/cursor_agent_kernel.dart';
import 'package:baocode/kernel/cursor_agent/cursor_agent_model_setting.dart';
import 'package:baocode/kernel/cursor_agent/cursor_agent_models.dart';
import 'package:baocode/kernel/cursor_agent/cursor_agent_sessions.dart';
import 'package:baocode/kernel/cursor_agent/cursor_agent_transport.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_registry.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Cursor Agent is the only user-facing kernel', () {
    // test/flutter_test_config.dart replaces KernelRegistry.all with mocks
    // before any test. The descriptor the app ships is still Cursor Agent.
    expect(KernelRegistry.cursorAgent.id, 'cursor-agent');
    expect(KernelRegistry.claudeCode.id, 'claude-code');
    final kernel = KernelRegistry.cursorAgent.create(
      const KernelContext(cwd: '/work'),
    );
    expect(kernel, isA<CursorAgentKernel>());
    expect(kernel, isA<SelectsMode>());
    expect(kernel, isA<SelectsModel>());
    expect(KernelRegistry.cursorAgent.catalog, isA<CursorAgentCatalog>());
    kernel.dispose();
  });

  test('a prompt streams text over ACP and ends the turn', () async {
    final transport = ScriptedCursorTransport(
      onPrompt: (transport, message) {
        transport.notify(CursorAcp.sessionUpdate, {
          'sessionId': 'sess_1',
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'messageId': 'm1',
            'content': {'type': 'text', 'text': 'Hello'},
          },
        });
        transport.reply(message['id'], {'stopReason': 'end_turn'});
      },
    );
    final kernel = _kernel(transport);
    final events = <KernelEvent>[];
    kernel.events.listen(events.add);

    kernel.send(const KernelTurn(id: 't1', text: 'Hi'));
    await pumpEventQueue();

    expect(kernel.health.status, KernelHealthStatus.ready);
    expect(kernel.sessionId, 'sess_1');
    expect(transport.methods, [
      CursorAcp.initialize,
      CursorAcp.authenticate,
      CursorAcp.sessionNew,
      CursorAcp.sessionPrompt,
    ]);
    final initialize = transport.written.firstWhere(
      (message) => message['method'] == CursorAcp.initialize,
    );
    final params = initialize['params'] as Map;
    expect(params['protocolVersion'], 1);
    expect((initialize['params'] as Map)['clientInfo'], {
      'name': 'baocursor',
      'version': '1.5.0',
    });
    final auth = transport.written.firstWhere(
      (message) => message['method'] == CursorAcp.authenticate,
    );
    expect((auth['params'] as Map)['methodId'], 'cursor_login');
    final prompt = transport.written.lastWhere(
      (message) => message['method'] == CursorAcp.sessionPrompt,
    );
    expect(((prompt['params'] as Map)['prompt'] as List).first, {
      'type': 'text',
      'text': 'Hi',
    });
    expect(
      events.whereType<ItemUpserted>().map((event) => event.item),
      contains(
        isA<AssistantTextItem>().having((item) => item.text, 'text', 'Hello'),
      ),
    );
    expect(events.whereType<TurnEnded>().single.interrupted, isFalse);
    kernel.dispose();
  });

  test('permission answers use the ACP selected outcome', () async {
    final transport = ScriptedCursorTransport(
      onPrompt: (transport, message) {
        transport.holdPrompt(message['id']);
        transport.request(9, CursorAcp.requestPermission, {
          'sessionId': 'sess_1',
          'toolCall': {
            'toolCallId': 'call_1',
            'title': 'Run tests',
            'kind': 'execute',
            'rawInput': 'flutter test',
          },
          'options': [
            {
              'optionId': 'allow-once',
              'name': 'Allow once',
              'kind': 'allow_once',
            },
            {
              'optionId': 'reject-once',
              'name': 'Reject',
              'kind': 'reject_once',
            },
          ],
        });
      },
    );
    final kernel = _kernel(transport);
    final events = <KernelEvent>[];
    kernel.events.listen(events.add);
    kernel.send(const KernelTurn(id: 't1', text: 'test'));
    await pumpEventQueue();

    final request = events.whereType<InteractionRequested>().single.request;
    expect(request, isA<ApprovalRequest>());
    kernel.answer(request.id, const ApprovalAnswer(ApprovalDecision.allowOnce));
    await pumpEventQueue();

    final response = transport.written.lastWhere(
      (message) => message['method'] == null && message.containsKey('result'),
    );
    expect(response['result'], {
      'outcome': {'outcome': 'selected', 'optionId': 'allow-once'},
    });
    expect(events.whereType<TurnEnded>().single.interrupted, isFalse);
    kernel.dispose();
  });

  test('ask_question uses QuestionRequest with multiple picks', () async {
    final transport = ScriptedCursorTransport(
      onPrompt: (transport, message) {
        transport.holdPrompt(message['id']);
        transport.request(11, CursorAcp.askQuestion, {
          'sessionId': 'sess_1',
          'title': 'Pick',
          'questions': [
            {
              'id': 'q1',
              'prompt': 'Which?',
              'allowMultiple': true,
              'options': [
                {'id': 'a', 'label': 'A'},
                {'id': 'b', 'label': 'B'},
              ],
            },
          ],
        });
      },
    );
    final kernel = _kernel(transport);
    final events = <KernelEvent>[];
    kernel.events.listen(events.add);
    kernel.send(const KernelTurn(id: 't1', text: 'ask'));
    await pumpEventQueue();

    final request = events.whereType<InteractionRequested>().single.request;
    expect(request, isA<QuestionRequest>());
    final questions = (request as QuestionRequest).questions;
    expect(questions.single.allowMultiple, isTrue);
    kernel.answer(
      request.id,
      const QuestionAnswer([
        ['A', 'B'],
      ]),
    );
    await pumpEventQueue();

    final response = transport.written.lastWhere(
      (message) => message['method'] == null && message.containsKey('result'),
    );
    expect(response['result'], {
      'outcome': {
        'outcome': 'answered',
        'answers': [
          {
            'questionId': 'q1',
            'selectedOptionIds': ['a', 'b'],
          },
        ],
      },
    });
    kernel.dispose();
  });

  test('create_plan confirm returns accepted with planUri', () async {
    final transport = ScriptedCursorTransport(
      onPrompt: (transport, message) {
        transport.holdPrompt(message['id']);
        transport.request(12, CursorAcp.createPlan, {
          'sessionId': 'sess_1',
          'name': 'My plan',
          'overview': 'Do things',
          'plan': '## Steps\n1. One',
          'planUri': 'file:///tmp/plan.md',
        });
      },
    );
    final kernel = _kernel(transport);
    final events = <KernelEvent>[];
    kernel.events.listen(events.add);
    kernel.send(const KernelTurn(id: 't1', text: 'plan'));
    await pumpEventQueue();

    final request = events.whereType<InteractionRequested>().single.request;
    expect(request, isA<ApprovalRequest>());
    final approval = request as ApprovalRequest;
    expect(approval.allowOnceLabel, 'Confirm plan');
    expect(approval.preview, isA<TextPreview>());
    kernel.answer(request.id, const ApprovalAnswer(ApprovalDecision.allowOnce));
    await pumpEventQueue();

    final response = transport.written.lastWhere(
      (message) => message['method'] == null && message.containsKey('result'),
    );
    expect(response['result'], {
      'outcome': {'outcome': 'accepted', 'planUri': 'file:///tmp/plan.md'},
    });
    kernel.dispose();
  });

  test('cancel notifies session/cancel and cancels the permission', () async {
    final transport = ScriptedCursorTransport(
      onPrompt: (transport, message) {
        transport.holdPrompt(message['id']);
        transport.request(9, CursorAcp.requestPermission, {
          'sessionId': 'sess_1',
          'toolCall': {'toolCallId': 'call_1', 'title': 'Run'},
          'options': [
            {'optionId': 'allow-once', 'kind': 'allow_once'},
            {'optionId': 'reject-once', 'kind': 'reject_once'},
          ],
        });
      },
    );
    final kernel = _kernel(transport);
    kernel.send(const KernelTurn(id: 't1', text: 'go'));
    await pumpEventQueue();
    kernel.cancel();
    await pumpEventQueue();

    expect(
      transport.written.map((message) => message['method']),
      contains(CursorAcp.sessionCancel),
    );
    final cancelled = transport.written.lastWhere(
      (message) => message['method'] == null && message.containsKey('result'),
    );
    expect(cancelled['result'], {
      'outcome': {'outcome': 'cancelled'},
    });
    kernel.dispose();
  });

  test('a missing CLI fails the kernel and ends the turn', () async {
    final kernel = CursorAgentKernel(
      _descriptor,
      const KernelContext(cwd: '/work'),
      start: (_) async =>
          throw const CursorAgentUnavailable('Cursor Agent CLI was not found'),
    );
    final events = <KernelEvent>[];
    kernel.events.listen(events.add);
    kernel.send(const KernelTurn(id: 't1', text: 'Hi'));
    await pumpEventQueue();

    expect(kernel.health.status, KernelHealthStatus.failed);
    expect(kernel.health.message, contains('not found'));
    expect(events.whereType<TurnEnded>().single.interrupted, isTrue);
    kernel.dispose();
  });

  test('fallback model menu passes --model and restarts', () async {
    final launches = <String?>[];
    final transport = ScriptedCursorTransport(onPrompt: (_, _) {});
    final kernel = CursorAgentKernel(
      _descriptor,
      const KernelContext(cwd: '/work'),
      start: (launch) async {
        launches.add(launch.model);
        return transport;
      },
    );
    kernel.prepare();
    await pumpEventQueue();
    expect(launches, [null]);
    expect(kernel.model.options.map((option) => option.id), [
      CursorAgentModels.cliDefaultId,
      CursorAgentModels.otherId,
    ]);
    expect(kernel.switchRestarts('composer-2.5'), isTrue);

    String? saved;
    List<String>? recent;
    CursorAgentModelSetting.persist = (model, models) {
      saved = model;
      recent = models;
    };
    addTearDown(() {
      CursorAgentModelSetting.persist = (_, _) {};
    });
    kernel.model.select('composer-2.5');
    await pumpEventQueue();

    expect(launches, [null, 'composer-2.5']);
    expect(kernel.model.selected, 'composer-2.5');
    expect(saved, 'composer-2.5');
    expect(recent, ['composer-2.5']);
    kernel.dispose();
  });

  test('a resumed CLI chat omits --model until the user picks', () async {
    final launches = <String?>[];
    final transport = ScriptedCursorTransport(
      onPrompt: (_, _) {},
      loadSession: true,
    );
    CursorAgentModelSetting.current = () => 'composer-2.5';
    addTearDown(() => CursorAgentModelSetting.current = () => null);
    final kernel = CursorAgentKernel(
      _descriptor,
      KernelContext(
        cwd: '/work',
        resume: SessionRecord(
          id: 'cli-session',
          title: 'Old',
          updatedAt: DateTime.utc(2026, 1, 1),
          cwd: '/work',
        ),
      ),
      start: (launch) async {
        launches.add(launch.model);
        return transport;
      },
    );
    kernel.prepare();
    await pumpEventQueue();

    expect(launches, [null]);
    expect(transport.methods, contains(CursorAcp.sessionLoad));
    kernel.model.select('gpt-5');
    await pumpEventQueue();
    expect(launches, [null, 'gpt-5']);
    kernel.dispose();
  });

  test('ACP model options use session/set_config_option', () async {
    const options = [
      {
        'id': 'model',
        'category': 'model',
        'type': 'select',
        'currentValue': 'composer-2.5',
        'options': [
          {'value': 'composer-2.5', 'name': 'Composer'},
          {'value': 'gpt-5', 'name': 'GPT-5'},
        ],
      },
    ];
    final launches = <CursorAgentLaunch>[];
    final transport = ScriptedCursorTransport(
      onPrompt: (_, _) {},
      configOptions: options,
    );
    final kernel = CursorAgentKernel(
      _descriptor,
      const KernelContext(cwd: '/work'),
      start: (launch) async {
        launches.add(launch);
        return transport;
      },
    );
    kernel.prepare();
    await pumpEventQueue();

    expect(kernel.model.options.map((option) => option.label), [
      'Composer',
      'GPT-5',
    ]);
    expect(kernel.switchRestarts('gpt-5'), isFalse);
    kernel.model.select('gpt-5');
    await pumpEventQueue();

    expect(launches, hasLength(1));
    final set = transport.written.lastWhere(
      (message) => message['method'] == CursorAcp.sessionSetConfigOption,
    );
    expect(set['params'], {
      'sessionId': 'sess_1',
      'configId': 'model',
      'value': 'gpt-5',
    });
    kernel.dispose();
  });

  test('without session/load the CLI chat still opens with a notice', () async {
    final transport = ScriptedCursorTransport(onPrompt: (_, _) {});
    final kernel = CursorAgentKernel(
      _descriptor,
      KernelContext(
        cwd: '/work',
        resume: SessionRecord(
          id: 'cli-session',
          title: 'Old',
          updatedAt: DateTime.utc(2026, 1, 1),
          cwd: '/work',
        ),
      ),
      start: (_) async => transport,
    );
    final events = <KernelEvent>[];
    kernel.events.listen(events.add);
    kernel.prepare();
    await pumpEventQueue();

    expect(kernel.sessionId, 'sess_1');
    expect(transport.methods, isNot(contains(CursorAcp.sessionLoad)));
    expect(
      events.whereType<ItemUpserted>().map((event) => event.item),
      contains(
        isA<NoticeItem>().having(
          (item) => item.text,
          'text',
          contains('session/load'),
        ),
      ),
    );
    kernel.dispose();
  });
}

KernelDescriptor get _descriptor => KernelDescriptor(
  id: 'cursor-agent',
  label: 'Cursor Agent',
  icon: Icons.smart_toy_outlined,
  description: 'test',
  create: (_) => throw UnimplementedError(),
);

CursorAgentKernel _kernel(ScriptedCursorTransport transport) =>
    CursorAgentKernel(
      _descriptor,
      const KernelContext(cwd: '/work'),
      start: (_) async => transport,
    );

class ScriptedCursorTransport implements CursorAgentTransport {
  ScriptedCursorTransport({
    required this.onPrompt,
    this.loadSession = false,
    this.configOptions,
  });

  final void Function(
    ScriptedCursorTransport transport,
    Map<String, Object?> message,
  )
  onPrompt;

  final bool loadSession;
  final Object? configOptions;

  final StreamController<Map<String, Object?>> _out =
      StreamController.broadcast(sync: true);
  final List<Map<String, Object?>> written = [];
  final Completer<void> _exited = Completer<void>();
  Object? _heldPrompt;

  List<Object?> get methods => [
    for (final message in written)
      if (message['method'] != null) message['method'],
  ];

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  @override
  String get cwd => '/work';

  @override
  Future<void> get exited => _exited.future;

  @override
  void close() {
    if (!_exited.isCompleted) _exited.complete();
  }

  @override
  void write(Map<String, Object?> message) {
    written.add(message);
    final method = message['method'] as String?;
    if (method == null) {
      if (_heldPrompt != null && message.containsKey('result')) {
        final id = _heldPrompt;
        _heldPrompt = null;
        reply(id, {'stopReason': 'end_turn'});
      }
      return;
    }
    final id = message['id'];
    switch (method) {
      case CursorAcp.initialize:
        reply(id, {
          'protocolVersion': 1,
          'agentCapabilities': {'loadSession': loadSession},
        });
      case CursorAcp.authenticate:
        reply(id, const {});
      case CursorAcp.sessionNew:
        reply(id, {
          'sessionId': 'sess_1',
          'modes': {
            'currentModeId': 'agent',
            'availableModes': [
              {'id': 'agent', 'name': 'Agent', 'description': 'Act'},
            ],
          },
          if (configOptions != null) 'configOptions': configOptions,
        });
      case CursorAcp.sessionLoad:
        reply(id, {
          'modes': {
            'currentModeId': 'agent',
            'availableModes': [
              {'id': 'agent', 'name': 'Agent', 'description': 'Act'},
            ],
          },
          if (configOptions != null) 'configOptions': configOptions,
        });
      case CursorAcp.sessionSetConfigOption:
        final params = message['params'];
        final value = params is Map ? params['value'] : null;
        reply(id, {
          'configOptions': [
            {
              'id': 'model',
              'category': 'model',
              'type': 'select',
              'currentValue': value,
              'options': [
                {'value': 'composer-2.5', 'name': 'Composer'},
                {'value': 'gpt-5', 'name': 'GPT-5'},
              ],
            },
          ],
        });
      case CursorAcp.sessionPrompt:
        onPrompt(this, message);
      case CursorAcp.sessionSetMode:
        reply(id, const {});
      default:
        if (id != null) reply(id, const {});
    }
  }

  void holdPrompt(Object? id) => _heldPrompt = id;

  void request(Object id, String method, Map<String, Object?> params) {
    if (!_out.isClosed) {
      _out.add({'id': id, 'method': method, 'params': params});
    }
  }

  void reply(Object? id, Map<String, Object?> result) {
    if (!_out.isClosed) _out.add({'id': id, 'result': result});
  }

  void notify(String method, Map<String, Object?> params) {
    if (!_out.isClosed) _out.add({'method': method, 'params': params});
  }
}
