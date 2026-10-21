import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../kernel/kernel_registry.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import 'workspace.dart';

/// Sidebar chrome: the folders in the current Cursor workspace.
///
/// A named workspace (`--workspace`) and a multi-root workspace
/// (`--add-dir` / extra folders) both list those folders here, with the
/// path, so they are not only the chat group's title.
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
    final l10n = context.l10n;
    final resolved = workspace.cursorAgentWorkspaceFor(thread);
    final named = resolved.namedWorkspace?.trim();
    final folders = workspace.cursorAgentFoldersFor(thread);
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
                      l10n.cursorWorkspaceFoldersTitle,
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
              if (named != null && named.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 18, top: 2),
                  child: Text(
                    l10n.cursorWorkspaceFoldersNamed(named),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              if (folders.isNotEmpty) ...[
                const SizedBox(height: 4),
                for (final folder in folders)
                  Tooltip(
                    message: folder,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 18, top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.basename(folder).isEmpty
                                ? folder
                                : p.basename(folder),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            folder,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textFaint,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
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
