@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:baocode/kernel/cursor_agent/cursor_agent_process_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('baocode-cursor-agent');
    file = File(p.join(dir.path, 'cursor-agent-processes.json'));
    CursorAgentProcess.registry = CursorAgentProcessRegistry(
      file: file,
      ownPid: 500,
      lookup: (_) async => null,
      signal: (_) => false,
    );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  const agent = '/home/user/.local/bin/agent acp';

  test('reaps orphaned agent acp processes', () async {
    file.writeAsStringSync(
      jsonEncode([
        {'pid': 11, 'parent': 400, 'command': agent},
        {'pid': 12, 'parent': 500, 'command': agent},
      ]),
    );
    final running = <int, ({int parent, String command})>{
      11: (parent: 1, command: agent),
      12: (parent: 500, command: agent),
    };
    final signalled = <int>[];
    CursorAgentProcess.registry = CursorAgentProcessRegistry(
      file: file,
      ownPid: 500,
      lookup: (pid) async => running[pid],
      signal: (pid) {
        signalled.add(pid);
        return true;
      },
    );

    await CursorAgentProcess.reapLeftovers();
    expect(signalled, [11, 12]);
  });
}
