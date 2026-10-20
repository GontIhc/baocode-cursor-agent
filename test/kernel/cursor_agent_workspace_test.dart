import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/cursor_agent/cursor_agent_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('named workspace becomes --workspace before acp', () {
    expect(
      CursorAgentWorkspaceSetting.processArguments(
        namedWorkspace: 'my-platform',
        addDirectories: const ['/other'],
      ),
      ['--workspace', 'my-platform', 'acp'],
    );
  });

  test('extra directories become repeated --add-dir before acp', () {
    expect(
      CursorAgentWorkspaceSetting.processArguments(
        addDirectories: const ['/work', '/lib'],
      ),
      ['--add-dir', '/work', '--add-dir', '/lib', 'acp'],
    );
  });

  test('resolve merges settings, workspace folders, and cwd', () {
    final resolved = resolveCursorAgentWorkspace(
      KernelContext(
        cwd: '/work',
        settings: {
          CursorAgentWorkspaceSetting.extraDirsKey:
              '["/configured"]',
        },
        workspace: () => const KernelWorkspace(
          folders: ['/work', '/also'],
        ),
      ),
    );
    expect(resolved.usesNamedWorkspace, isFalse);
    expect(resolved.cliAddDirectories, ['/configured', '/also']);
    expect(resolved.processArguments, [
      '--add-dir',
      '/configured',
      '--add-dir',
      '/also',
      'acp',
    ]);
  });

  test('named workspace skips add-dir and folder merge', () {
    final resolved = resolveCursorAgentWorkspace(
      KernelContext(
        cwd: '/work',
        settings: {CursorAgentWorkspaceSetting.workspaceKey: 'saved'},
        workspace: () => const KernelWorkspace(folders: ['/also']),
      ),
    );
    expect(resolved.usesNamedWorkspace, isTrue);
    expect(resolved.cliAddDirectories, isEmpty);
    expect(resolved.processArguments, ['--workspace', 'saved', 'acp']);
  });
}
