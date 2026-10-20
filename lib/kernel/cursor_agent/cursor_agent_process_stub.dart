import 'cursor_agent_transport.dart';

Future<CursorAgentTransport> startCursorAgent(CursorAgentLaunch launch) async =>
    throw const CursorAgentUnavailable(
      'Cursor Agent runs in the desktop app',
      detail: 'The browser cannot start local processes.',
    );

abstract final class CursorAgentProcess {
  static Future<void> stopAll() async {}

  static Future<void> reapLeftovers() async {}
}
