import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/kernel/cursor_agent/cursor_agent_locator.dart';
import 'package:baocode/kernel/cursor_agent/cursor_agent_translator.dart';
import 'package:baocode/kernel/cursor_agent/cursor_agent_transport.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveCursorAgent', () {
    test('uses the configured path and does not search past a miss', () {
      final found = resolveCursorAgent(
        environment: const {'PATH': '/bin'},
        home: '/home/u',
        pathListSeparator: ':',
        fileSeparator: '/',
        windows: false,
        configuredPath: '~/bin/agent',
        exists: (path) => path == '/home/u/bin/agent',
      );
      expect(found.path, '/home/u/bin/agent');

      expect(
        () => resolveCursorAgent(
          environment: const {'PATH': '/usr/bin'},
          home: '/home/u',
          pathListSeparator: ':',
          fileSeparator: '/',
          windows: false,
          configuredPath: '/missing/agent',
          exists: (path) => path == '/usr/bin/agent',
        ),
        throwsA(
          isA<CursorAgentUnavailable>().having(
            (error) => error.message,
            'message',
            contains('/missing/agent'),
          ),
        ),
      );
    });

    test('prefers PATH agent, then ~/.local/bin/agent, then cursor-agent', () {
      final onPath = resolveCursorAgent(
        environment: const {'PATH': '/opt/bin:/usr/bin'},
        home: '/home/u',
        pathListSeparator: ':',
        fileSeparator: '/',
        windows: false,
        exists: (path) =>
            path == '/usr/bin/agent' ||
            path == '/home/u/.local/bin/cursor-agent',
      );
      expect(onPath.path, '/usr/bin/agent');

      final local = resolveCursorAgent(
        environment: const {'Path': '/usr/bin'},
        home: '/home/u',
        pathListSeparator: ':',
        fileSeparator: '/',
        windows: false,
        exists: (path) => path == '/home/u/.local/bin/agent',
      );
      expect(local.path, '/home/u/.local/bin/agent');

      final alias = resolveCursorAgent(
        environment: const {'PATH': '/opt'},
        home: '/home/u',
        pathListSeparator: ':',
        fileSeparator: '/',
        windows: false,
        exists: (path) => path == '/opt/cursor-agent',
      );
      expect(alias.path, '/opt/cursor-agent');
    });

    test('names the install docs when nothing is installed', () {
      expect(
        () => resolveCursorAgent(
          environment: const {'PATH': '/usr/bin'},
          home: '/home/u',
          pathListSeparator: ':',
          fileSeparator: '/',
          windows: false,
          exists: (_) => false,
        ),
        throwsA(
          isA<CursorAgentUnavailable>().having(
            (error) => error.detail,
            'detail',
            contains('https://cursor.com/docs/cli/installation'),
          ),
        ),
      );
    });

    test('a Windows .cmd shim is run through the shell', () {
      final found = resolveCursorAgent(
        environment: const {'PATH': r'C:\Tools'},
        home: r'C:\Users\u',
        pathListSeparator: ';',
        fileSeparator: r'\',
        windows: true,
        exists: (path) => path == r'C:\Tools\agent.cmd',
      );
      expect(found.throughShell, isTrue);
    });
  });

  group('CursorAgentTranslator', () {
    late List<KernelEvent> events;
    late CursorAgentTranslator translator;

    setUp(() {
      events = [];
      var seq = 0;
      translator = CursorAgentTranslator(
        emit: events.add,
        nextSeq: () => ++seq,
      );
    });

    test('streams an agent message in chunks', () {
      translator.sessionUpdate({
        'sessionUpdate': 'agent_message_chunk',
        'messageId': 'm1',
        'content': {'type': 'text', 'text': 'Hel'},
      });
      translator.sessionUpdate({
        'sessionUpdate': 'agent_message_chunk',
        'messageId': 'm1',
        'content': {'type': 'text', 'text': 'lo'},
      });
      translator.finish();

      final upsert = events.whereType<ItemUpserted>().single;
      expect(upsert.id, 'message:m1');
      expect(upsert.item, isA<AssistantTextItem>());
      expect((upsert.item as AssistantTextItem).text, 'Hel');
      final delta = events.whereType<TextDelta>().single;
      expect(delta.offset, 3);
      expect(delta.text, 'lo');
      final done = events.whereType<ItemCompleted>().single;
      expect((done.item as AssistantTextItem).text, 'Hello');
    });

    test('updates a tool call in place', () {
      translator.sessionUpdate({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call_1',
        'title': 'Read config',
        'kind': 'read',
        'status': 'pending',
        'locations': [
          {'path': '/work/config.json'},
        ],
      });
      translator.sessionUpdate({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call_1',
        'status': 'completed',
        'content': [
          {
            'type': 'content',
            'content': {'type': 'text', 'text': 'ok'},
          },
        ],
      });
      final items = events.whereType<ItemUpserted>().map(
        (event) => event.item as ToolCallItem,
      );
      expect(items.first.status, ToolStatus.running);
      expect(items.first.path, '/work/config.json');
      expect(items.last.status, ToolStatus.succeeded);
      expect(items.last.output, 'ok');
      expect(items.last.kind, ToolKind.read);
    });

    test('replaces the plan and reports context usage', () {
      translator.sessionUpdate({
        'sessionUpdate': 'plan',
        'entries': [
          {'content': 'Look around', 'priority': 'high', 'status': 'pending'},
          {'content': 'Edit', 'priority': 'low', 'status': 'in_progress'},
        ],
      });
      translator.sessionUpdate({
        'sessionUpdate': 'usage_update',
        'used': 10,
        'size': 200,
      });
      final todos = events.whereType<TodosReported>().single.todos;
      expect(todos.map((todo) => todo.content), ['Look around', 'Edit']);
      expect(todos.last.status, TodoStatus.inProgress);
      final usage = events.whereType<UsageReported>().single.usage;
      expect(usage.used, 10);
      expect(usage.window, 200);
    });

    test('merges cursor todos and drops cancelled ones', () {
      translator.updateTodos({
        'merge': false,
        'todos': [
          {'id': '1', 'content': 'A', 'status': 'pending'},
          {'id': '2', 'content': 'B', 'status': 'completed'},
        ],
      });
      translator.updateTodos({
        'merge': true,
        'todos': [
          {'id': '1', 'content': 'A2', 'status': 'in_progress'},
          {'id': '2', 'content': 'B', 'status': 'cancelled'},
        ],
      });
      final latest = events.whereType<TodosReported>().last.todos;
      expect(latest, hasLength(1));
      expect(latest.single.content, 'A2');
      expect(latest.single.status, TodoStatus.inProgress);
    });

    test('permission options keep Cursor ids', () {
      final choice = cursorPermissionChoice({
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
            'optionId': 'allow-always',
            'name': 'Always allow',
            'kind': 'allow_always',
          },
          {'optionId': 'reject-once', 'name': 'Reject', 'kind': 'reject_once'},
        ],
      });
      expect(choice.allowOnceId, 'allow-once');
      expect(choice.allowAlwaysId, 'allow-always');
      expect(choice.rejectId, 'reject-once');
      expect(choice.alwaysAllowLabel, 'Always allow');
      expect(choice.preview, isA<CommandPreview>());
      expect((choice.preview as CommandPreview).command, 'flutter test');
    });

    test('ask_question keeps option ids behind the labels', () {
      final form = cursorQuestionForm({
        'title': 'Need input',
        'questions': [
          {
            'id': 'q1',
            'prompt': 'Which mode?',
            'allowMultiple': false,
            'options': [
              {'id': 'agent', 'label': 'Agent'},
              {'id': 'plan', 'label': 'Plan'},
            ],
          },
        ],
      });
      expect(form, isNotNull);
      expect(form!.questions.single.labelToId['Plan'], 'plan');
      expect(form.questions.single.question.allowOther, isFalse);
    });
  });
}
