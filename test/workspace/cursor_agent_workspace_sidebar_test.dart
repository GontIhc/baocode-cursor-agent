import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/cursor_agent/cursor_agent_kernel.dart';
import 'package:baocode/kernel/cursor_agent/cursor_agent_transport.dart';
import 'package:baocode/kernel/cursor_agent/cursor_agent_workspace.dart';
import 'package:baocode/kernel/kernel_registry.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/workspace/cursor_agent_workspace_sidebar.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// CLI history in two folders. No real `agent` process.
class _Catalog implements SessionCatalog {
  _Catalog(this.records);

  final List<SessionRecord> records;

  @override
  Future<List<ProjectRecord>> projects() async {
    final paths = <String>{for (final record in records) record.cwd};
    return [
      for (final path in paths)
        ProjectRecord(
          path: path,
          sessions: [
            for (final record in records)
              if (record.cwd == path) record,
          ],
        ),
    ];
  }

  @override
  Future<List<SessionRecord>> sessionsIn(String cwd) async => [
    for (final record in records)
      if (record.cwd == cwd) record,
  ];

  @override
  Future<void> delete(String id) async {}
}

class _IdleTransport implements CursorAgentTransport {
  _IdleTransport(this.cwd);

  @override
  final String cwd;

  @override
  Stream<Map<String, Object?>> get messages => const Stream.empty();

  @override
  Future<void> get exited => Future<void>.value();

  @override
  void close() {}

  @override
  void write(Map<String, Object?> message) {}
}

Finder _inChrome(Finder finder) => find.descendant(
  of: find.byType(CursorAgentWorkspaceSidebar),
  matching: finder,
);

/// Row clicks share a double-tap clock. [WidgetTester.tap] stamps every
/// pointer event at zero, so a second click on a row renames it.
Duration _tapAt = Duration.zero;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  _tapAt += const Duration(seconds: 1);
  final gesture = await tester.createGesture();
  final position = tester.getCenter(finder);
  await gesture.down(position, timeStamp: _tapAt);
  await gesture.up(timeStamp: _tapAt);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const hammer = '/Users/jay/Documents/hammer-workspace_C';
  const tencent = '/Users/jay/Documents/TencentMap';

  late KernelDescriptor cursor;

  setUp(() {
    _tapAt = Duration.zero;
  });

  Future<Workspace> loadHistory() async {
    final catalog = _Catalog([
      SessionRecord(
        id: 'cli-hammer',
        title: 'Hello There',
        updatedAt: DateTime.now().subtract(const Duration(minutes: 1)),
        cwd: hammer,
      ),
      SessionRecord(
        id: 'cli-tencent',
        title: 'Android Project Run',
        updatedAt: DateTime.now().subtract(const Duration(minutes: 4)),
        cwd: tencent,
      ),
    ]);
    cursor = KernelDescriptor(
      id: KernelRegistry.cursorAgent.id,
      label: 'Cursor Agent',
      icon: Icons.smart_toy_outlined,
      description: '',
      catalog: catalog,
      create: (context) => CursorAgentKernel(
        cursor,
        context,
        start: (launch) async => _IdleTransport(launch.cwd),
      ),
    );
    final workspace = Workspace(kernels: [cursor]);
    await workspace.load();
    return workspace;
  }

  Future<void> show(WidgetTester tester, Workspace workspace) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: Sidebar(workspace: workspace, onCollapse: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('folders chrome follows the selected chat’s project', (
    tester,
  ) async {
    final workspace = await loadHistory();
    // Global prefs must not pin every chat to one folder list.
    workspace.cursorAgentNamedWorkspace = 'hammer';
    workspace.cursorAgentExtraDirectories = const [hammer];
    await show(tester, workspace);

    final hello = workspace.threads.firstWhere(
      (thread) => thread.title == 'Hello There',
    );
    final android = workspace.threads.firstWhere(
      (thread) => thread.title == 'Android Project Run',
    );

    await _tap(tester, find.text('Hello There'));
    await tester.pump();
    expect(workspace.current, same(hello));
    expect(_inChrome(find.text('hammer-workspace_C')), findsOneWidget);
    expect(_inChrome(find.text(hammer)), findsOneWidget);
    expect(_inChrome(find.text('TencentMap')), findsNothing);

    await _tap(tester, find.text('Android Project Run'));
    await tester.pump();
    expect(workspace.current, same(android));
    expect(
      _inChrome(find.text('TencentMap')),
      findsOneWidget,
      reason: _chromeTexts(tester),
    );
    expect(_inChrome(find.text(tencent)), findsOneWidget);
    expect(_inChrome(find.text('hammer-workspace_C')), findsNothing);
    expect(_inChrome(find.text(hammer)), findsNothing);
    // A global name is not this chat’s workspace.
    expect(_inChrome(find.textContaining('hammer')), findsNothing);
  });

  test(
    'folder list is the selected thread’s project, not global prefs',
    () async {
      final workspace = await loadHistory();
      workspace.cursorAgentNamedWorkspace = 'hammer';
      workspace.cursorAgentExtraDirectories = const [hammer];
      final hello = workspace.threads.firstWhere(
        (thread) => thread.title == 'Hello There',
      );
      final android = workspace.threads.firstWhere(
        (thread) => thread.title == 'Android Project Run',
      );
      expect(workspace.cursorAgentFoldersFor(hello), [hammer]);
      expect(workspace.cursorAgentFoldersFor(android), [tencent]);
      expect(workspace.cursorAgentWorkspaceFor(android).namedWorkspace, isNull);
    },
  );

  test('a new chat still follows the live workspace prefs', () async {
    final workspace = await loadHistory();
    workspace.cursorAgentNamedWorkspace = 'hammer';
    workspace.cursorAgentExtraDirectories = const ['/extra/one'];
    final created = workspace.create(project: workspace.threads.first.project);
    expect(created.untouched, isTrue);
    expect(
      workspace.cursorAgentFoldersFor(created),
      containsAll([created.project.path, '/extra/one']),
    );
    expect(workspace.cursorAgentWorkspaceFor(created).namedWorkspace, 'hammer');
    expect(
      workspace.cursorAgentFoldersFor(
        workspace.threads.firstWhere(
          (thread) => thread.title == 'Android Project Run',
        ),
      ),
      [tencent],
    );
  });
}

String _chromeTexts(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(_inChrome(find.byType(Text)))
      .map((text) => text.data)
      .toList();
  return 'chrome texts: $texts';
}
