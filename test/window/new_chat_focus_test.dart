import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/cursor_agent/cursor_agent_kernel.dart';
import 'package:baocode/kernel/cursor_agent/cursor_agent_transport.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/main.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/window/app_windows.dart';
import 'package:baocode/window/window_settings.dart';
import 'package:baocode/workspace/workspace.dart';

import 'fake_window_host.dart';

/// CLI history the sidebar lists, and `authenticate` fails the way the
/// Linux smoke did (`agent login`). No real `agent` process.
class _CliCatalog implements SessionCatalog {
  _CliCatalog(this._records);

  final List<SessionRecord> _records;

  @override
  Future<List<ProjectRecord>> projects() async => [
    ProjectRecord(path: _records.first.cwd, sessions: _records),
  ];

  @override
  Future<List<SessionRecord>> sessionsIn(String cwd) async => [
    for (final record in _records)
      if (record.cwd == cwd) record,
  ];

  @override
  Future<void> delete(String id) async {}
}

class _AuthTransport implements CursorAgentTransport {
  _AuthTransport(this.cwd);

  @override
  final String cwd;

  final _out = StreamController<Map<String, Object?>>.broadcast(sync: true);
  final _exited = Completer<void>();

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  @override
  Future<void> get exited => _exited.future;

  @override
  void close() {
    if (!_exited.isCompleted) _exited.complete();
  }

  @override
  void write(Map<String, Object?> message) {
    final method = message['method'];
    final id = message['id'];
    if (method == CursorAcp.initialize) {
      _emit({
        'id': id,
        'result': {
          'protocolVersion': 1,
          'agentCapabilities': {'loadSession': true},
        },
      });
      return;
    }
    if (method == CursorAcp.authenticate) {
      _emit({
        'id': id,
        'error': {'code': -32000, 'message': 'not logged in'},
      });
    }
  }

  void _emit(Map<String, Object?> message) {
    if (!_out.isClosed) _out.add(message);
  }
}

Finder _sidebarText(String text) => find.descendant(
  of: find.byType(Sidebar),
  matching: find.text(text),
);

ChatScreen _chat(WidgetTester tester) {
  final screens = tester.widgetList<ChatScreen>(find.byType(ChatScreen));
  expect(screens, hasLength(1), reason: 'one chat in the main window');
  return screens.single;
}

void main() {
  testWidgets(
    'New Chat from a CLI history session focuses the empty chat '
    'without a window',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final messenger = tester.binding.defaultBinaryMessenger;
      for (final name in ['baocode/window']) {
        messenger.setMockMethodCallHandler(
          MethodChannel(name),
          (call) async => null,
        );
        addTearDown(
          () => messenger.setMockMethodCallHandler(MethodChannel(name), null),
        );
      }

      final project = '/tmp/demo-project';
      final catalog = _CliCatalog([
        SessionRecord(
          id: 'cli-hello',
          title: 'Smoke CLI history hello',
          updatedAt: DateTime.now().subtract(const Duration(hours: 16)),
          cwd: project,
        ),
        SessionRecord(
          id: 'cli-tag',
          title: 'tag communication',
          updatedAt: DateTime.now().subtract(const Duration(hours: 14)),
          cwd: project,
        ),
      ]);
      late final KernelDescriptor cursor;
      cursor = KernelDescriptor(
        id: 'cursor-agent',
        label: 'Cursor Agent',
        icon: Icons.smart_toy_outlined,
        description: '',
        catalog: catalog,
        create: (context) => CursorAgentKernel(
          cursor,
          context,
          start: (launch) async => _AuthTransport(launch.cwd),
        ),
      );
      final workspace = Workspace(kernels: [cursor]);
      final host = FakeWindowHost(tester.view);
      final windows = AppWindows(
        host: host,
        workspace: workspace,
        l10n: () => englishLocalizations,
        settings: () =>
            const WindowSettings(ideWindows: IdeWindows.separate),
        isDirectory: (path) async => true,
        nextFrame: () => tester.binding.endOfFrame,
      );
      await windows.start();
      await tester.pumpWidget(
        BaoCodeApp(workspace: workspace, windows: windows),
        wrapWithView: false,
      );
      await tester.runAsync(workspace.load);
      await tester.pump();
      await tester.pump();

      expect(host.created, isEmpty);
      final cli = workspace.threads.firstWhere(
        (thread) => thread.title == 'Smoke CLI history hello',
      );
      expect(cli.record, isNotNull);

      await tester.tap(_sidebarText('Smoke CLI history hello'));
      await tester.pump();
      await tester.pump();

      expect(workspace.current, same(cli));
      expect(_chat(tester).session, same(cli.session));
      expect(_chat(tester).title, 'Smoke CLI history hello');
      final createdWindows = host.created.length;

      await tester.tap(_sidebarText('New Chat'));
      await tester.pump();
      await tester.pump();

      final opened = workspace.current!;
      expect(opened, isNot(same(cli)));
      expect(opened.untouched, isTrue);
      expect(opened.record, isNull);
      expect(opened.project.path, cli.project.path);
      expect(_chat(tester).session, same(opened.session));
      expect(_chat(tester).title, 'New Chat');
      expect(
        find.descendant(
          of: find.byType(ChatScreen),
          matching: find.text('Smoke CLI history hello'),
        ),
        findsNothing,
      );
      expect(windows.agentWindows, isEmpty);
      expect(host.created, hasLength(createdWindows));

      // Back on the CLI session, New Chat reuses the untouched one and
      // shows it again. The editor must not stay on the history chat.
      await tester.tap(_sidebarText('Smoke CLI history hello'));
      await tester.pump();
      await tester.pump();
      expect(_chat(tester).session, same(cli.session));

      await tester.tap(_sidebarText('New Chat').first);
      await tester.pump();
      await tester.pump();

      expect(workspace.current, same(opened));
      expect(opened.untouched, isTrue);
      expect(_chat(tester).session, same(opened.session));
      expect(_chat(tester).title, 'New Chat');
      expect(host.created, hasLength(createdWindows));
    },
    semanticsEnabled: false,
  );
}
