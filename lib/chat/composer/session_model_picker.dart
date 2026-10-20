import 'dart:async';

import 'package:flutter/material.dart';

import '../../channel/channel_setup.dart' show ChannelSetup;
import '../../ide/ide_dialog.dart';
import '../../kernel/agent_kernel.dart';
import '../../kernel/cursor_agent/cursor_agent_models.dart';
import '../../kernel/kernel_types.dart';
import '../../l10n/l10n.dart';
import '../../models/model_welcome.dart';
import '../../settings/settings_dialog.dart'
    show SettingsOpener, SettingsSection;
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../chat_session.dart';
import '../widgets/hover_builder.dart';
import 'composer_picker.dart';

/// The pill that picks [session]'s model, each model's settings (its
/// effort, its context) beside it: the composer's, and the one a plan is
/// started with. With no model to run on, one that sets a model up
/// ([showModelWelcome]); nothing where the kernel picks no model.
class SessionModelPicker extends StatelessWidget {
  const SessionModelPicker({
    super.key,
    required this.session,
    this.pickerKey,
    this.tooltip,
    this.tapRegionGroupId,
    this.focusNode,
  });

  final ChatSession session;

  /// The picker's own, to open it from a keybinding.
  final GlobalKey<ComposerPickerState>? pickerKey;

  /// See [ComposerPicker.tooltip], [ComposerPicker.tapRegionGroupId] and
  /// [ComposerPicker.focusNode].
  final String? tooltip;
  final Object? tapRegionGroupId;
  final FocusNode? focusNode;

  /// The model with its settings, e.g. "Opus · 1M · High": the context
  /// only when it is not the standard one; its upstream before it only
  /// when another upstream has a model of its name.
  String _label(KernelOption model, List<KernelOption> options) => [
    if (model.group case final group?
        when options.any(
          (other) => other.label == model.label && other.group?.id != group.id,
        ))
      group.label,
    model.label,
    for (final setting in session.modelSettings(model.id))
      if (setting.selected case final selected?
          when setting.kind != KernelChoiceKind.context ||
              selected != setting.options.first)
        selected.label,
  ].join(' · ');

  bool get _cursor => session.kernel.id == 'cursor-agent';

  /// The fallback menu's fixed rows, in the display language. ACP options
  /// and typed ids keep the label the kernel gave them.
  KernelOption _shown(KernelOption option, AppLocalizations l10n) {
    if (!_cursor) return option;
    return switch (option.id) {
      CursorAgentModels.cliDefaultId => KernelOption(
        option.id,
        l10n.cursorModelCliDefault,
        option.icon,
        l10n.cursorModelCliDefaultDescription,
      ),
      CursorAgentModels.otherId => KernelOption(
        option.id,
        l10n.cursorModelOther,
        option.icon,
        l10n.cursorModelOtherDescription,
      ),
      _ => option,
    };
  }

  /// Runs [pick], which switches to [option]: once confirmed, if that
  /// restarts the agent on another upstream mid-conversation.
  Future<void> _switch(
    BuildContext context,
    KernelOption option,
    VoidCallback pick,
  ) async {
    if (!session.switchRestarts(option.id)) return pick();
    final l10n = context.l10n;
    final choice = await showIdeDialog(
      context,
      message: l10n.modelsSwitchTitle(option.group?.label ?? option.label),
      detail: _cursor ? l10n.cursorModelSwitchDetail : l10n.modelsSwitchDetail,
      buttons: [l10n.modelsSwitchConfirm],
      type: IdeDialogType.question,
    );
    if (choice == 0 && context.mounted) pick();
  }

  Future<void> _pick(
    BuildContext context,
    KernelChoice model,
    KernelOption option,
  ) async {
    var chosen = option;
    if (option.id == CursorAgentModels.otherId) {
      final typed = await _askModelId(context);
      if (typed == null || !context.mounted) return;
      chosen = KernelOption(
        typed,
        typed,
        option.icon,
        'agent --model $typed acp',
      );
    }
    if (!context.mounted) return;
    await _switch(context, chosen, () => model.onSelected(chosen));
  }

  Future<String?> _askModelId(BuildContext context) async {
    final l10n = context.l10n;
    final result = await showIdeInputDialog(
      context,
      message: l10n.cursorModelOtherTitle,
      detail: l10n.cursorAgentModelSettingDescription,
      buttons: [l10n.commonOk],
      inputs: [IdeDialogInput(placeholder: l10n.cursorAgentModelSettingHint)],
      type: IdeDialogType.question,
    );
    if (result == null || result.button != 0) return null;
    final typed = result.values.first.trim();
    if (typed.isEmpty || typed == CursorAgentModels.otherId) return null;
    return typed;
  }

  @override
  Widget build(BuildContext context) {
    final model = session.models;
    final l10n = context.l10n;
    if (model == null) {
      if (!session.health.noModel) return const SizedBox.shrink();
      return _SetUpPill(
        label: l10n.modelSetUp,
        onTap: () => unawaited(showModelWelcome(context)),
      );
    }
    final options = [for (final option in model.options) _shown(option, l10n)];
    final selected = _shown(model.selected, l10n);
    return ComposerPicker(
      key: pickerKey,
      options: options,
      selected: selected,
      label: _label(selected, options),
      // Each its name alone, one line; its maker's logo and its upstream's
      // heading tell the rest.
      describes: false,
      settingsOf: (option) => [
        for (final setting in session.modelSettings(option.id))
          ModelSettingChoice(
            kind: setting.kind,
            options: setting.options,
            selected: setting.selected,
            toggle: setting.toggle,
            onSelected: (choice) => unawaited(
              _switch(context, option, () => setting.onSelected(choice)),
            ),
          ),
      ],
      tooltip: tooltip,
      menuWidth: 260,
      searchPlaceholder: l10n.modelsSearch,
      footer: _cursor
          ? null
          : switch (SettingsOpener.maybeOf(context)) {
              final open? => (
                label: ChannelSetup.channelBuild
                    ? l10n.channelAccountTitle
                    : l10n.modelsManage,
                icon: Icons.tune_rounded,
                onTap: () => open(SettingsSection.models),
              ),
              null => null,
            },
      tapRegionGroupId: tapRegionGroupId,
      focusNode: focusNode,
      onSelected: (option) => unawaited(_pick(context, model, option)),
    );
  }
}

/// In the model's place while there is none: as its pill, in the accent,
/// a click away from setting one up.
class _SetUpPill extends StatelessWidget {
  const _SetUpPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accent;
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: hovered ? .2 : .12),
            border: Border.all(color: accent.withValues(alpha: .4)),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Codicons.sparkle, size: 13, color: accent),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: accent, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
