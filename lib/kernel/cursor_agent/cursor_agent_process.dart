import 'cursor_agent_process_stub.dart'
    if (dart.library.io) 'cursor_agent_process_io.dart'
    as platform;
import 'cursor_agent_transport.dart';

/// Starts `agent acp` as a local process. On the web, where there are no
/// processes, fails saying so.
Future<CursorAgentTransport> startCursorAgent(CursorAgentLaunch launch) =>
    platform.startCursorAgent(launch);
