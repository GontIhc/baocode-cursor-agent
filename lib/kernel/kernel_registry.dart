import 'package:flutter/material.dart';

import 'agent_kernel.dart';
import 'claude_code/claude_code_kernel.dart';
import 'cursor_agent/cursor_agent_kernel.dart';
import '../remote/remote_claude.dart';

/// Kernels the app can run. This fork registers only Cursor Agent for
/// normal use; [claudeCode] stays for tests and internal tooling.
abstract final class KernelRegistry {
  static final KernelDescriptor claudeCode = KernelDescriptor(
    id: 'claude-code',
    label: 'Claude Code',
    icon: Icons.auto_awesome_rounded,
    description: 'Anthropic’s coding agent',
    create: (context) => ClaudeCodeKernel(
      claudeCode,
      context,
      // On the project's host: this machine, or a remote one's.
      start: startClaude,
      readHistoryPage: readClaudeHistoryPage,
      readGoal: readClaudeGoal,
      forkSession: forkClaudeSession,
      usageOffBy: () => claudeUsageOffByAt(context.cwd),
      rejectTooOld: rejectTooOldClaude,
    ),
    catalog: const ClaudeCatalog(),
  );

  /// Cursor Agent CLI (`agent acp`) over stdio JSON-RPC. On this fork it is
  /// the default when the `agent` binary is on the machine.
  static final KernelDescriptor cursorAgent = KernelDescriptor(
    id: 'cursor-agent',
    label: 'Cursor Agent',
    icon: Icons.smart_toy_outlined,
    description: 'Cursor’s coding agent, over ACP',
    create: (context) => CursorAgentKernel(cursorAgent, context),
  );

  static List<KernelDescriptor> _all = [cursorAgent];

  static List<KernelDescriptor> get all => _all;

  /// Replaces the kernels on offer, e.g. with mock ones under test.
  static void use(List<KernelDescriptor> kernels) => _all = kernels;
}
