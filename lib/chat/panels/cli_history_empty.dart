import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';

/// Shown when a CLI chat was opened and `session/load` could not restore
/// its transcript. The history still lives in the Cursor CLI store.
class CliHistoryEmpty extends StatelessWidget {
  const CliHistoryEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.history_rounded,
                size: 16,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.cliHistoryEmptyTitle,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.cliHistoryEmptyBody,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
