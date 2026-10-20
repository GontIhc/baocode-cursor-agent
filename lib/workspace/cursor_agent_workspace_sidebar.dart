import 'package:flutter/material.dart';

import '../kernel/cursor_agent/cursor_agent_workspace.dart';
import '../kernel/kernel_registry.dart';
import '../remote/remote_location.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import 'workspace.dart';

/// Sidebar chrome: which Cursor CLI workspace the current agent uses.
class CursorAgentWorkspaceSidebar extends StatelessWidget {
  const CursorAgentWorkspaceSidebar({
    super.key,
    required this.workspace,
    required this.thread,
  });

  final Workspace workspace;
  final AgentThread thread;

  @override
  Widget build(BuildContext context) {
    if (thread.kernel.id != KernelRegistry.cursorAgent.id) {
      return const SizedBox.shrink();
    }
    final resolved = workspace.cursorAgentWorkspaceFor(thread);
    final named = resolved.namedWorkspace?.trim();
    final roots = resolved.displayRoots;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.hover.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Codicons.folderLibrary,
                    size: 12,
                    color: AppColors.textFaint,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      named != null && named.isNotEmpty
                          ? 'Cursor workspace: $named'
                          : 'Cursor roots',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (roots.isNotEmpty) ...[
                const SizedBox(height: 4),
                for (final root in roots)
                  Padding(
                    padding: const EdgeInsets.only(left: 18, top: 1),
                    child: Text(
                      RemoteLocation.nameOf(root),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textFaint, fontSize: 10.5),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
