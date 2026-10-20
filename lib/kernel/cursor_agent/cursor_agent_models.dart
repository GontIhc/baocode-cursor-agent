import 'package:flutter/material.dart';

import '../kernel_types.dart';
import 'cursor_agent_transport.dart';

/// Ids the composer uses for Cursor's fallback model menu.
///
/// Real model ids are whatever the CLI accepts as `agent --model <id>`.
/// [cliDefaultId] means the process starts without `--model`. [otherId] is
/// the menu row that asks for an id; it is never passed to the CLI.
abstract final class CursorAgentModels {
  static const cliDefaultId = '';
  static const otherId = '\u0000other';
  static const recentLimit = 6;

  static const cliDefaultLabel = 'CLI default';
  static const otherLabel = 'Other model…';
}

/// One model the ACP agent offered as a `select` config option.
class CursorAcpModelState {
  const CursorAcpModelState({
    required this.configId,
    required this.currentValue,
    required this.options,
  });

  /// `configId` (ACP v1 also used `id`) for `session/set_config_option`.
  final String configId;
  final String? currentValue;
  final List<KernelOption> options;
}

/// The model selector inside an ACP `configOptions` list, if there is one.
///
/// Accepts the list itself or a session result / `config_option_update`
/// object that carries `configOptions`. Select options with category
/// `model` win. With no category, an option whose id or name is `model`
/// is used. Mode and other categories are left to the mode picker.
///
/// https://agentclientprotocol.com/protocol/v1/session-config-options
CursorAcpModelState? parseCursorAcpModels(Object? raw) {
  final list = switch (raw) {
    final List<Object?> values => values,
    final Map<String, Object?> map when map['configOptions'] is List =>
      map['configOptions'] as List<Object?>,
    _ => null,
  };
  if (list == null) return null;
  Map<String, Object?>? model;
  for (final entry in list) {
    final map = cursorJsonMap(entry);
    if (map == null || !_isSelect(map)) continue;
    if (!_isModelOption(map)) continue;
    model = map;
    break;
  }
  if (model == null) return null;
  final configId = _configId(model);
  if (configId == null) return null;
  final optionsRaw = model['options'];
  if (optionsRaw is! List || optionsRaw.isEmpty) return null;
  final options = <KernelOption>[];
  final seen = <String>{};
  for (final rawOption in optionsRaw) {
    final option = cursorJsonMap(rawOption);
    if (option == null) continue;
    final value = option['value'] ?? option['id'];
    if (value is! String || value.isEmpty || !seen.add(value)) continue;
    final name = option['name'] ?? option['label'];
    final description = option['description'];
    options.add(
      KernelOption(
        value,
        name is String && name.isNotEmpty ? name : value,
        Icons.auto_awesome_outlined,
        description is String ? description : '',
      ),
    );
  }
  if (options.isEmpty) return null;
  final current = model['currentValue'];
  return CursorAcpModelState(
    configId: configId,
    currentValue: current is String && current.isNotEmpty ? current : null,
    options: options,
  );
}

bool _isSelect(Map<String, Object?> map) {
  final type = map['type'];
  return type == null || type == 'select';
}

bool _isModelOption(Map<String, Object?> map) {
  final category = map['category'];
  if (category == 'model') return true;
  if (category != null) return false;
  final id = (_configId(map) ?? '').toLowerCase();
  final name = map['name'];
  return id == 'model' || (name is String && name.toLowerCase() == 'model');
}

String? _configId(Map<String, Object?> map) {
  final id = map['configId'] ?? map['id'];
  if (id is! String || id.isEmpty) return null;
  return id;
}

/// Fallback menu when ACP has not advertised a model option: the CLI
/// default, the id in effect, recent ids, and a row that asks for one.
List<KernelOption> buildCursorFallbackModels({
  required String selected,
  required List<String> recent,
}) {
  final options = <KernelOption>[
    const KernelOption(
      CursorAgentModels.cliDefaultId,
      CursorAgentModels.cliDefaultLabel,
      Icons.tune_rounded,
      'No --model flag; the CLI picks',
    ),
  ];
  final seen = <String>{CursorAgentModels.cliDefaultId};
  void add(String id, {String? description}) {
    final model = id.trim();
    if (model.isEmpty || !seen.add(model)) return;
    options.add(
      KernelOption(
        model,
        model,
        Icons.auto_awesome_outlined,
        description ?? 'agent --model $model acp',
      ),
    );
  }

  if (selected != CursorAgentModels.cliDefaultId) add(selected);
  for (final id in recent) {
    add(id, description: 'Recent · agent --model ${id.trim()} acp');
  }
  options.add(
    const KernelOption(
      CursorAgentModels.otherId,
      CursorAgentModels.otherLabel,
      Icons.edit_outlined,
      'Type a model id',
    ),
  );
  return options;
}
