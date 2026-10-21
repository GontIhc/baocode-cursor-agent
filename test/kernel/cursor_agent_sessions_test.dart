import 'dart:convert';
import 'dart:io';

import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/cursor_agent/cursor_agent_models.dart';
import 'package:baocode/kernel/cursor_agent/cursor_agent_sessions_io.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ACP model config options become the picker list', () {
    final parsed = parseCursorAcpModels({
      'configOptions': [
        {
          'id': 'mode',
          'category': 'mode',
          'type': 'select',
          'currentValue': 'ask',
          'options': [
            {'value': 'ask', 'name': 'Ask'},
          ],
        },
        {
          'configId': 'model',
          'name': 'Model',
          'category': 'model',
          'type': 'select',
          'currentValue': 'composer-2.5',
          'options': [
            {'value': 'composer-2.5', 'name': 'Composer 2.5'},
            {
              'value': 'gpt-5',
              'name': 'GPT-5',
              'description': 'A larger model',
            },
          ],
        },
      ],
    });
    expect(parsed, isNotNull);
    expect(parsed!.configId, 'model');
    expect(parsed.currentValue, 'composer-2.5');
    expect(parsed.options.map((option) => option.id), [
      'composer-2.5',
      'gpt-5',
    ]);
    expect(parsed.options.last.description, 'A larger model');
  });

  test('bracket model ids split into a bare id and parameters', () {
    final spec = parseCursorModelSpec(
      'claude-opus-5-5[context=300k,effort=medium,fast=false]',
    );
    expect(spec, isNotNull);
    expect(spec!.bareId, 'claude-opus-5-5');
    expect(spec.context, '300k');
    expect(spec.effort, 'medium');
    expect(spec.fast, isFalse);
    expect(spec.hasParams, isTrue);
    expect(cursorBareModelId('composer-2.5'), 'composer-2.5');
    expect(
      cursorModelOptionLabel(
        'claude-opus-5-5[context=300k,effort=medium,fast=false]',
        'claude-opus-5-5[context=300k,effort=medium,fast=false]',
      ),
      'claude-opus-5-5',
    );
  });

  test('model match is exact, then the longest hyphen prefix', () {
    final options = [
      const KernelOption(
        'claude-opus-5',
        'Opus',
        Icons.auto_awesome_outlined,
        '',
      ),
      const KernelOption(
        'claude-opus-5-thinking-high',
        'Opus thinking',
        Icons.auto_awesome_outlined,
        '',
      ),
      const KernelOption('gpt-5', 'GPT-5', Icons.auto_awesome_outlined, ''),
    ];
    expect(
      matchCursorModelOption('claude-opus-5-5', options)?.id,
      'claude-opus-5',
    );
    expect(
      matchCursorModelOption('claude-opus-5-thinking-high', options)?.id,
      'claude-opus-5-thinking-high',
    );
    expect(matchCursorModelOption('gpt-5.3-codex', options), isNull);
  });

  test('ACP config options include effort, context, fast, and thinking', () {
    final parsed = parseCursorAcpConfig({
      'configOptions': [
        {
          'id': 'model',
          'category': 'model',
          'type': 'select',
          'currentValue': 'claude-opus-5',
          'options': [
            {'value': 'claude-opus-5', 'name': 'Opus'},
          ],
        },
        {
          'id': 'reasoning',
          'type': 'select',
          'currentValue': 'low',
          'options': [
            {'value': 'low', 'name': 'Low'},
            {'value': 'high', 'name': 'High'},
          ],
        },
        {
          'id': 'effort',
          'category': 'effort',
          'type': 'select',
          'currentValue': 'medium',
          'options': [
            {'value': 'medium', 'name': 'Medium'},
            {'value': 'high', 'name': 'High'},
          ],
        },
        {
          'id': 'context',
          'type': 'select',
          'currentValue': '200k',
          'options': [
            {'value': '200k', 'name': '200k'},
            {'value': '300k', 'name': '300k'},
          ],
        },
        {
          'id': 'fast',
          'type': 'boolean',
          'name': 'Fast',
          'currentValue': false,
        },
        {
          'id': 'thinking',
          'type': 'boolean',
          'name': 'Thinking',
          'currentValue': true,
        },
      ],
    });
    expect(parsed, isNotNull);
    expect(parsed!.model!.currentValue, 'claude-opus-5');
    expect(parsed.parameters.map((param) => param.kind), [
      KernelChoiceKind.context,
      KernelChoiceKind.effort,
      KernelChoiceKind.thinking,
      KernelChoiceKind.fast,
    ]);
    final effort = parsed.parameters.firstWhere(
      (param) => param.kind == KernelChoiceKind.effort,
    );
    expect(effort.configId, 'effort');
    expect(effort.currentValue, 'medium');
    final fast = parsed.parameters.firstWhere(
      (param) => param.kind == KernelChoiceKind.fast,
    );
    expect(fast.toggle, isTrue);
    expect(fast.options.single.id, 'true');
    expect(fast.currentValue, 'false');
  });

  test('fallback menu is default, current, recent, and free text', () {
    final options = buildCursorFallbackModels(
      selected: 'composer-2.5',
      recent: const ['composer-2.5', 'gpt-5'],
    );
    expect(options.map((option) => option.id), [
      CursorAgentModels.cliDefaultId,
      'composer-2.5',
      'gpt-5',
      CursorAgentModels.otherId,
    ]);
    expect(options.first.label, CursorAgentModels.cliDefaultLabel);
    expect(options.last.icon, Icons.edit_outlined);
  });

  test('CLI chats and ACP sessions for one folder are listed', () async {
    final root = Directory.systemTemp.createTempSync('cursor-cli-sessions');
    addTearDown(() => root.deleteSync(recursive: true));
    const cwd = '/work/hammer-workspace_E';
    final hash = cursorWorkspaceKey(cwd);
    final chat = Directory(
      '${root.path}/chats/$hash/11111111-1111-4111-8111-111111111111',
    )..createSync(recursive: true);
    File('${chat.path}/meta.json').writeAsStringSync(
      jsonEncode({
        'cwd': cwd,
        'title': 'New Agent',
        'createdAtMs': 1_700_000_000_000,
        'updatedAtMs': 1_700_000_005_000,
        'hasConversation': true,
      }),
    );
    File('${chat.path}/prompt_history.json').writeAsStringSync(
      jsonEncode([
        '<user_info>hidden</user_info>\n<user_query>\nfix the build\n</user_query>',
      ]),
    );
    final acp = Directory(
      '${root.path}/acp-sessions/22222222-2222-4222-8222-222222222222',
    )..createSync(recursive: true);
    File('${acp.path}/meta.json').writeAsStringSync(
      jsonEncode({
        'cwd': '$cwd/',
        'title': 'ACP hello',
        'updatedAtMs': 1_700_000_009_000,
      }),
    );
    final other = Directory(
      '${root.path}/chats/${cursorWorkspaceKey('/other')}/33333333-3333-4333-8333-333333333333',
    )..createSync(recursive: true);
    File('${other.path}/meta.json').writeAsStringSync(
      jsonEncode({
        'cwd': '/other',
        'title': 'Elsewhere',
        'updatedAtMs': 1_700_000_020_000,
      }),
    );
    final sub = Directory(
      '${root.path}/chats/$hash/44444444-4444-4444-8444-444444444444',
    )..createSync(recursive: true);
    File('${sub.path}/meta.json').writeAsStringSync(
      jsonEncode({
        'cwd': cwd,
        'title': 'sub',
        'isSubagent': true,
        'updatedAtMs': 1_700_000_030_000,
      }),
    );
    final hashed = Directory(
      '${root.path}/chats/$hash/55555555-5555-4555-8555-555555555555',
    )..createSync(recursive: true);
    File('${hashed.path}/meta.json').writeAsStringSync(
      jsonEncode({'updatedAtMs': 1_700_000_001_000, 'hasConversation': true}),
    );
    File('${hashed.path}/store.db').writeAsStringSync(
      '{"role":"user","content":"<user_query>hash only</user_query>"}',
    );

    final projects = await cursorCliProjects(roots: [root.path]);
    final hammer = projects.where((project) => project.path == cwd).single;
    expect(hammer.sessions.map((session) => session.title), [
      'ACP hello',
      'fix the build',
    ]);
    expect(projects.map((project) => project.path), contains('/other'));

    final inFolder = await cursorCliSessionsIn(cwd, roots: [root.path]);
    expect(inFolder.map((session) => session.id), [
      '22222222-2222-4222-8222-222222222222',
      '11111111-1111-4111-8111-111111111111',
      '55555555-5555-4555-8555-555555555555',
    ]);
    expect(
      inFolder
          .singleWhere((session) => session.id.startsWith('55555555'))
          .title,
      'hash only',
    );

    await deleteCursorCliSession(
      '22222222-2222-4222-8222-222222222222',
      roots: [root.path],
    );
    expect(acp.existsSync(), isFalse);
    final after = await cursorCliSessionsIn('/other', roots: [root.path]);
    expect(after.single.title, 'Elsewhere');
  });

  test('Image and Untitled titles yield to the first prompt', () async {
    final root = Directory.systemTemp.createTempSync('cursor-cli-titles');
    addTearDown(() => root.deleteSync(recursive: true));
    const cwd = '/work/titles';
    final hash = cursorWorkspaceKey(cwd);
    final image = Directory(
      '${root.path}/chats/$hash/66666666-6666-4666-8666-666666666666',
    )..createSync(recursive: true);
    File('${image.path}/meta.json').writeAsStringSync(
      jsonEncode({
        'cwd': cwd,
        'title': 'Image',
        'updatedAtMs': 1_700_000_010_000,
        'hasConversation': true,
      }),
    );
    File('${image.path}/prompt_history.json').writeAsStringSync(
      jsonEncode(['<user_query>rename the sidebar chip</user_query>']),
    );
    final untitled = Directory(
      '${root.path}/acp-sessions/77777777-7777-4777-8777-777777777777',
    )..createSync(recursive: true);
    File('${untitled.path}/meta.json').writeAsStringSync(
      jsonEncode({
        'cwd': cwd,
        'title': 'Untitled',
        'updatedAtMs': 1_700_000_011_000,
      }),
    );
    File('${untitled.path}/store.db').writeAsStringSync(
      '{"text":"<user_query>wire the sign-in button</user_query>"}',
    );
    final onlyImage = Directory(
      '${root.path}/chats/$hash/88888888-8888-4888-8888-888888888888',
    )..createSync(recursive: true);
    File('${onlyImage.path}/meta.json').writeAsStringSync(
      jsonEncode({
        'cwd': cwd,
        'title': '[Image 1]',
        'updatedAtMs': 1_700_000_012_000,
        'hasConversation': true,
      }),
    );

    final sessions = await cursorCliSessionsIn(cwd, roots: [root.path]);
    expect(
      sessions.map((session) => session.title),
      containsAll(['rename the sidebar chip', 'wire the sign-in button']),
    );
    expect(
      sessions.map((session) => session.title),
      isNot(containsAll(['Image', 'Untitled', '[Image 1]'])),
    );
    expect(
      sessions
          .singleWhere((session) => session.id.startsWith('88888888'))
          .title,
      startsWith('CLI '),
    );
  });

  test('config roots prefer CURSOR_CONFIG_DIR, then XDG, then ~/.cursor', () {
    expect(
      cursorCliStoreRoots(
        environment: const {
          'CURSOR_CONFIG_DIR': '/cfg',
          'XDG_CONFIG_HOME': '/xdg',
          'HOME': '/home/u',
        },
      ),
      [
        '/cfg',
        '/xdg/cursor',
        '/xdg/Cursor',
        '/home/u/.cursor',
        '/home/u/.config/cursor',
        '/home/u/.config/Cursor',
      ],
    );
  });
}
