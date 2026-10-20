import 'cursor_agent_process_stub.dart'
    if (dart.library.io) 'cursor_agent_process_io.dart'
    as platform;
import 'cursor_agent_transport.dart';

/// Starts `agent acp` as a local process. On the web, where there are no
/// processes, fails saying so.
Future<CursorAgentTransport> startCursorAgent(CursorAgentLaunch launch) =>
    platform.startCursorAgent(launch);

/// Ends every Cursor Agent process the app started, and waits for them: for
/// when the app quits.
Future<void> stopCursorAgentProcesses() => platform.CursorAgentProcess.stopAll();

/// Ends the Cursor Agent processes an earlier run left running (a crash, a
/// force quit, a hot restart); none on the web.
Future<void> reapCursorAgentProcesses() =>
    platform.CursorAgentProcess.reapLeftovers();
