import 'cursor_agent_locator_stub.dart'
    if (dart.library.io) 'cursor_agent_locator_io.dart'
    as platform;
import 'cursor_agent_path_setting.dart';
import 'cursor_agent_transport.dart';

/// The `agent` binary to spawn, once it has been found.
class CursorAgentExecutable {
  const CursorAgentExecutable(this.path, {this.throughShell = false});

  final String path;

  /// A `.cmd` / `.bat` shim. [Process.start] has to run it through a shell.
  final bool throughShell;
}

/// Finds the Cursor Agent CLI on this machine. On the web, where there is
/// no process to start, fails saying so.
Future<CursorAgentExecutable> locateCursorAgent() =>
    platform.locateCursorAgent();

/// Install line quoted from the installation docs, for an error report.
///
/// https://cursor.com/docs/cli/installation
const cursorAgentInstallHint = '''
Install the Cursor CLI, then try again.
macOS, Linux, and WSL: curl https://cursor.com/install -fsS | bash
Windows: irm 'https://cursor.com/install?win32=true' | iex
https://cursor.com/docs/cli/installation''';

/// Resolves the CLI without touching the disk itself: [exists] says
/// whether a path is a file.
///
/// Order: the [configuredPath] (`cursorAgent.path`), then `agent` on
/// [environment]'s `PATH`, then `~/.local/bin/agent`, then the same two
/// places for `cursor-agent`. Installation docs name `agent`.
/// `cursor-agent` is only a fallback. A configured path that is not there
/// is an error, not a reason to keep looking.
///
/// https://cursor.com/docs/cli/installation
CursorAgentExecutable resolveCursorAgent({
  required Map<String, String> environment,
  required String home,
  required String pathListSeparator,
  required String fileSeparator,
  required bool windows,
  String? configuredPath,
  required bool Function(String path) exists,
}) {
  final configured = _expandHome(configuredPath, home: home);
  if (configured != null) {
    if (exists(configured)) {
      return CursorAgentExecutable(
        configured,
        throughShell: _throughShell(configured),
      );
    }
    throw CursorAgentUnavailable(
      'Cursor Agent CLI was not found at $configured',
      detail:
          'Clear ${CursorAgentPathSetting.settingKey} to search PATH, '
          'or install the CLI.\n\n$cursorAgentInstallHint',
    );
  }

  final dirs = _pathDirs(environment, pathListSeparator);
  for (final name in _names(windows: windows)) {
    for (final dir in dirs) {
      final candidate = _join(fileSeparator, dir, name.name);
      if (exists(candidate)) {
        return CursorAgentExecutable(candidate, throughShell: name.shell);
      }
    }
    if (home.isNotEmpty) {
      final local = _join(
        fileSeparator,
        _join(fileSeparator, _join(fileSeparator, home, '.local'), 'bin'),
        name.name,
      );
      if (exists(local)) {
        return CursorAgentExecutable(local, throughShell: name.shell);
      }
    }
  }

  throw const CursorAgentUnavailable(
    'Cursor Agent CLI was not found',
    detail: cursorAgentInstallHint,
  );
}

String? _expandHome(String? path, {required String home}) {
  if (path == null) return null;
  final trimmed = path.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed == '~') return home.isEmpty ? trimmed : home;
  if (trimmed.startsWith('~/') || trimmed.startsWith(r'~\')) {
    if (home.isEmpty) return trimmed;
    return '$home${trimmed.substring(1)}';
  }
  return trimmed;
}

List<String> _pathDirs(Map<String, String> environment, String separator) {
  String? value;
  for (final entry in environment.entries) {
    if (entry.key.toUpperCase() == 'PATH') {
      value = entry.value;
      break;
    }
  }
  if (value == null || value.isEmpty) return const [];
  return [
    for (final dir in value.split(separator))
      if (dir.isNotEmpty) dir,
  ];
}

String _join(String separator, String dir, String name) {
  if (dir.endsWith(separator) || dir.endsWith('/') || dir.endsWith(r'\')) {
    return '$dir$name';
  }
  return '$dir$separator$name';
}

bool _throughShell(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.cmd') || lower.endsWith('.bat');
}

List<({String name, bool shell})> _names({required bool windows}) {
  if (!windows) {
    return const [
      (name: 'agent', shell: false),
      (name: 'cursor-agent', shell: false),
    ];
  }
  return const [
    (name: 'agent.exe', shell: false),
    (name: 'agent.cmd', shell: true),
    (name: 'agent.bat', shell: true),
    (name: 'cursor-agent.exe', shell: false),
    (name: 'cursor-agent.cmd', shell: true),
    (name: 'cursor-agent.bat', shell: true),
  ];
}
