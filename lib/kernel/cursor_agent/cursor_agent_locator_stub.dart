import 'cursor_agent_locator.dart';
import 'cursor_agent_transport.dart';

Future<CursorAgentExecutable> locateCursorAgent() async =>
    throw const CursorAgentUnavailable(
      'Cursor Agent runs in the desktop app',
      detail: 'The browser cannot start local processes.',
    );
