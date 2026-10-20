import 'package:flutter/material.dart';

import '../kernel/kernel_registry.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'window_controls.dart';
import 'workspace.dart';

/// Over a new Cursor Agent chat: named workspace and extra roots before
/// the first message (writes [Workspace] preferences).
class CursorAgentWorkspaceBar extends StatefulWidget {
  const CursorAgentWorkspaceBar({super.key, required this.workspace});

  final Workspace workspace;

  @override
  State<CursorAgentWorkspaceBar> createState() => _CursorAgentWorkspaceBarState();
}

class _CursorAgentWorkspaceBarState extends State<CursorAgentWorkspaceBar> {
  late final TextEditingController _name = TextEditingController(
    text: widget.workspace.cursorAgentNamedWorkspace ?? '',
  );

  @override
  void initState() {
    super.initState();
    widget.workspace.addListener(_syncName);
  }

  @override
  void didUpdateWidget(CursorAgentWorkspaceBar old) {
    super.didUpdateWidget(old);
    if (old.workspace != widget.workspace) {
      old.workspace.removeListener(_syncName);
      widget.workspace.addListener(_syncName);
      _syncName();
    }
  }

  @override
  void dispose() {
    widget.workspace.removeListener(_syncName);
    _name.dispose();
    super.dispose();
  }

  void _syncName() {
    final value = widget.workspace.cursorAgentNamedWorkspace ?? '';
    if (_name.text != value) {
      _name.text = value;
      _name.selection = TextSelection.collapsed(offset: value.length);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final named = widget.workspace.cursorAgentNamedWorkspace ?? '';
    final extras = widget.workspace.cursorAgentExtraDirectories;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 180,
            height: 22,
            child: TextField(
              controller: _name,
              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.cursorAgentWorkspaceNameHint,
                hintStyle: TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 11.5,
                ),
                filled: true,
                fillColor: themeColors['toolbar.hoverBackground'],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
              ),
              onSubmitted: (value) =>
                  widget.workspace.cursorAgentNamedWorkspace = value.trim(),
            ),
          ),
          if (named.isEmpty) ...[
            for (final path in extras)
              _Chip(
                label: path,
                onRemove: () =>
                    widget.workspace.removeCursorAgentExtraDirectory(path),
              ),
            if (WindowControls.canPickDirectory)
              _AddRootButton(
                label: l10n.cursorAgentWorkspaceAddRoot,
                onTap: () async {
                  final picked = await WindowControls.pickDirectory();
                  if (picked != null) {
                    widget.workspace.addCursorAgentExtraDirectory(picked);
                  }
                },
              ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.only(left: 8, right: 2),
      decoration: BoxDecoration(
        color: themeColors['toolbar.hoverBackground'],
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            iconSize: 14,
            onPressed: onRemove,
            icon: Icon(Icons.close_rounded, color: AppColors.textFaint),
          ),
        ],
      ),
    );
  }
}

class _AddRootButton extends StatelessWidget {
  const _AddRootButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: themeColors['toolbar.hoverBackground'],
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Codicons.add, size: 12, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whether [thread] should show the workspace bar above its composer.
bool showsCursorAgentWorkspaceBar(AgentThread thread) =>
    thread.kernel.id == KernelRegistry.cursorAgent.id && thread.untouched;
