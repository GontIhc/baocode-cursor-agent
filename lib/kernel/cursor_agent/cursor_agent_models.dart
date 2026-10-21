import 'package:flutter/material.dart';

import '../agent_kernel.dart';
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

/// A model id plus the parameters ACP sometimes packs into it.
///
/// `claude-opus-5-5[context=300k,effort=medium,fast=false]` is one ACP
/// option value. The CLI's `--model` flag wants the bare id only, and with
/// a parameterized picker the id and each parameter are separate config
/// options. A bare id (`composer-2.5`, `claude-opus-5-thinking-high`) has
/// no parameters.
class CursorModelSpec {
  const CursorModelSpec({
    required this.bareId,
    this.context,
    this.effort,
    this.fast,
    this.thinking,
  });

  final String bareId;
  final String? context;
  final String? effort;
  final bool? fast;
  final String? thinking;

  bool get hasParams =>
      context != null || effort != null || fast != null || thinking != null;
}

/// Parses [raw] as a bare model id or `id[context=…,effort=…,fast=…]`.
///
/// Empty and non-strings are null. Unknown keys are ignored. `effort`,
/// `reasoning`, and `reasoning_effort` all fill [CursorModelSpec.effort];
/// the first one in the bracket wins.
CursorModelSpec? parseCursorModelSpec(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed == CursorAgentModels.otherId) return null;
  final open = trimmed.indexOf('[');
  if (open < 0) return CursorModelSpec(bareId: trimmed);
  if (!trimmed.endsWith(']') || open == 0) return null;
  final bare = trimmed.substring(0, open).trim();
  if (bare.isEmpty) return null;
  String? context;
  String? effort;
  String? thinking;
  bool? fast;
  final body = trimmed.substring(open + 1, trimmed.length - 1);
  for (final part in body.split(',')) {
    final eq = part.indexOf('=');
    if (eq <= 0) continue;
    final key = part.substring(0, eq).trim().toLowerCase();
    final value = part.substring(eq + 1).trim();
    if (value.isEmpty) continue;
    switch (key) {
      case 'context':
        context ??= value;
      case 'effort':
      case 'reasoning':
      case 'reasoning_effort':
        effort ??= value;
      case 'fast':
        fast ??= value == 'true';
      case 'thinking':
        thinking ??= value;
    }
  }
  return CursorModelSpec(
    bareId: bare,
    context: context,
    effort: effort,
    fast: fast,
    thinking: thinking,
  );
}

/// The id without a `[context=…]` suffix. Null when [id] is not a model id.
String? cursorBareModelId(String? id) => parseCursorModelSpec(id)?.bareId;

/// Label for an ACP model value. Exploded ids show the bare id (or the
/// name ACP gave) so the pill does not read `id[context=…]`.
String cursorModelOptionLabel(String id, String label) {
  if (!id.contains('[')) return label;
  final bare = parseCursorModelSpec(id)?.bareId;
  if (bare == null || bare.isEmpty) return label;
  if (label.isEmpty || label == id) return bare;
  return label;
}

/// The ACP option [id] selects.
///
/// An exact id or bare id wins. Otherwise the longest option whose id is
/// a hyphen-boundary prefix (`claude-opus-5-5` matches `claude-opus-5`).
KernelOption? matchCursorModelOption(String id, List<KernelOption> options) {
  final spec = parseCursorModelSpec(id);
  if (spec == null) return null;
  final bare = spec.bareId;
  KernelOption? exactBare;
  KernelOption? prefix;
  var prefixLength = -1;
  for (final option in options) {
    if (option.id == id) return option;
    final optionBare = parseCursorModelSpec(option.id)?.bareId ?? option.id;
    if (option.id == bare || optionBare == bare) {
      exactBare ??= option;
      continue;
    }
    if (bare.length > optionBare.length &&
        bare.startsWith(optionBare) &&
        bare[optionBare.length] == '-' &&
        optionBare.length > prefixLength) {
      prefix = option;
      prefixLength = optionBare.length;
    }
  }
  return exactBare ?? prefix;
}

/// One ACP config option that is a model parameter (effort, context, fast,
/// thinking), already mapped onto a [KernelChoiceKind].
class CursorAcpParameter {
  const CursorAcpParameter({
    required this.kind,
    required this.configId,
    required this.options,
    required this.currentValue,
    required this.toggle,
  });

  final KernelChoiceKind kind;
  final String configId;
  final List<KernelOption> options;
  final String? currentValue;

  /// On or off. The single option id is `true`.
  final bool toggle;
}

/// The model selector and the parameter selectors from one ACP payload.
class CursorAcpConfig {
  const CursorAcpConfig({this.model, this.parameters = const []});

  final CursorAcpModelState? model;
  final List<CursorAcpParameter> parameters;
}

/// Model plus effort / context / fast / thinking from an ACP
/// `configOptions` list (or a session result that carries one).
///
/// Parameter ids: `context`; `fast` (a toggle); `effort`, then `reasoning`,
/// then `reasoning_effort`; `thinking`. The model option is the one
/// [parseCursorAcpModels] already accepts.
CursorAcpConfig? parseCursorAcpConfig(Object? raw) {
  final list = switch (raw) {
    final List<Object?> values => values,
    final Map<String, Object?> map when map['configOptions'] is List =>
      map['configOptions'] as List<Object?>,
    _ => null,
  };
  if (list == null) return null;
  final model = parseCursorAcpModels(raw);
  final byKind = <KernelChoiceKind, CursorAcpParameter>{};
  final rank = <KernelChoiceKind, int>{};
  for (final entry in list) {
    final map = cursorJsonMap(entry);
    if (map == null) continue;
    final kind = _parameterKind(map);
    if (kind == null) continue;
    final param = _parameterFrom(map, kind);
    if (param == null) continue;
    final score = _parameterRank(kind, param.configId);
    final previous = rank[kind];
    if (previous != null && previous <= score) continue;
    byKind[kind] = param;
    rank[kind] = score;
  }
  if (model == null && byKind.isEmpty) return null;
  return CursorAcpConfig(
    model: model,
    parameters: [
      for (final kind in const [
        KernelChoiceKind.context,
        KernelChoiceKind.effort,
        KernelChoiceKind.thinking,
        KernelChoiceKind.fast,
      ])
        ?byKind[kind],
    ],
  );
}

KernelChoiceKind? _parameterKind(Map<String, Object?> map) {
  final id = (_configId(map) ?? '').toLowerCase();
  final category = map['category'];
  final cat = category is String ? category.toLowerCase() : '';
  final name = map['name'];
  final named = name is String ? name.toLowerCase() : '';
  for (final candidate in [cat, id, named]) {
    switch (candidate) {
      case 'context':
      case 'context_size':
      case 'contextwindow':
        return KernelChoiceKind.context;
      case 'fast':
        return KernelChoiceKind.fast;
      case 'thinking':
        return KernelChoiceKind.thinking;
      case 'effort':
      case 'reasoning':
      case 'reasoning_effort':
        return KernelChoiceKind.effort;
    }
  }
  return null;
}

/// Lower is a better match. `effort` beats `reasoning` beats
/// `reasoning_effort`; an id that is exactly the kind name beats a category
/// that only happens to match.
int _parameterRank(KernelChoiceKind kind, String configId) {
  final id = configId.toLowerCase();
  if (kind == KernelChoiceKind.effort) {
    return switch (id) {
      'effort' => 0,
      'reasoning' => 1,
      'reasoning_effort' => 2,
      _ => 3,
    };
  }
  return id == kind.name ? 0 : 1;
}

CursorAcpParameter? _parameterFrom(
  Map<String, Object?> map,
  KernelChoiceKind kind,
) {
  final configId = _configId(map);
  if (configId == null) return null;
  final type = map['type'];
  final current = _configValue(map['currentValue']);
  if (type == 'boolean' || _boolOptions(map)) {
    final name = map['name'];
    final label = name is String && name.isNotEmpty
        ? name
        : switch (kind) {
            KernelChoiceKind.fast => 'Fast',
            KernelChoiceKind.thinking => 'Thinking',
            _ => configId,
          };
    return CursorAcpParameter(
      kind: kind,
      configId: configId,
      options: [KernelOption('true', label, _parameterIcon(kind), '')],
      currentValue: current == 'true' ? 'true' : 'false',
      toggle: true,
    );
  }
  if (type != null && type != 'select') return null;
  final optionsRaw = map['options'];
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
    final label = name is String && name.isNotEmpty ? name : value;
    options.add(
      KernelOption(
        value,
        cursorModelOptionLabel(value, label),
        _parameterIcon(kind),
        description is String ? description : '',
      ),
    );
  }
  if (options.isEmpty) return null;
  return CursorAcpParameter(
    kind: kind,
    configId: configId,
    options: options,
    currentValue: current,
    toggle: false,
  );
}

bool _boolOptions(Map<String, Object?> map) {
  final options = map['options'];
  if (options is! List || options.isEmpty) return false;
  var saw = false;
  for (final raw in options) {
    final option = cursorJsonMap(raw);
    final value = option?['value'] ?? option?['id'];
    if (value is! String || (value != 'true' && value != 'false')) {
      return false;
    }
    saw = true;
  }
  return saw;
}

String? _configValue(Object? value) => switch (value) {
  final String text when text.isNotEmpty => text,
  true => 'true',
  false => 'false',
  _ => null,
};

IconData _parameterIcon(KernelChoiceKind kind) => switch (kind) {
  KernelChoiceKind.context => Icons.notes_outlined,
  KernelChoiceKind.effort => Icons.speed_outlined,
  KernelChoiceKind.fast => Icons.bolt_rounded,
  KernelChoiceKind.thinking => Icons.psychology_outlined,
  _ => Icons.tune_rounded,
};

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
