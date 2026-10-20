import 'dart:convert';

import '../../chat/chat_models.dart';
import '../kernel_event.dart';
import '../kernel_types.dart';
import 'cursor_agent_transport.dart';

/// Turns ACP `session/update` payloads, and the Cursor extension
/// notifications whose bodies are documented, into [KernelEvent]s.
///
/// Turns, the JSON-RPC id match, and the user's answers stay in the
/// kernel. Field names below are the ones in the ACP docs or Cursor's ACP
/// page; anything not shown there is left alone.
///
/// https://cursor.com/docs/cli/acp
/// https://agentclientprotocol.com/protocol/v1/prompt-turn
/// https://agentclientprotocol.com/protocol/v1/tool-calls
class CursorAgentTranslator {
  CursorAgentTranslator({
    required this.emit,
    required this.nextSeq,
    this.onMode,
  });

  final void Function(KernelEvent event) emit;
  final int Function() nextSeq;

  /// The agent's `current_mode_update`, an id such as `agent` or `plan`.
  final void Function(String modeId)? onMode;

  /// True while `session/load` replays history. A live prompt already
  /// showed the user message, so user chunks are kept only here.
  bool replaying = false;

  String? _messageKey;
  String _message = '';
  String? _thoughtKey;
  String _thought = '';
  DateTime? _thoughtStarted;

  final Map<String, _Tool> _tools = {};
  final Map<String, String> _userText = {};
  final List<_TodoRow> _todos = [];

  /// The todo list as `cursor/update_todos` would echo it back.
  List<Map<String, Object?>> get todosWire => [
    for (final row in _todos)
      {
        'id': row.id,
        'content': row.entry.content,
        'status': _wireStatus(row.entry.status),
      },
  ];

  void sessionUpdate(Map<String, Object?> update) {
    switch (update['sessionUpdate']) {
      case 'agent_message_chunk':
        _chunk(update, thought: false);
      case 'agent_thought_chunk':
        _chunk(update, thought: true);
      case 'user_message_chunk':
        _userChunk(update);
      case 'tool_call':
      case 'tool_call_update':
        _tool(update);
      case 'plan':
        _plan(update['entries']);
      case 'usage_update':
        _usage(update);
      case 'current_mode_update':
        final id = update['currentModeId'];
        if (id is String && id.isNotEmpty) onMode?.call(id);
      default:
        // TODO: available_commands_update, config_option_update (models),
        // session_info_update, notice, compaction. Not mapped until a live
        // `agent acp` trace shows the fields Cursor actually sends.
        // https://cursor.com/docs/cli/acp
        // https://agentclientprotocol.com/protocol/v1/schema
        break;
    }
  }

  /// `cursor/update_todos`. [merge] false replaces the list.
  ///
  /// https://cursor.com/docs/cli/acp
  void updateTodos(Map<String, Object?> params) {
    final incoming = _cursorTodos(params['todos']);
    if (params['merge'] == true) {
      for (final row in incoming) {
        final index = _todos.indexWhere((kept) => kept.id == row.id);
        if (index < 0) {
          _todos.add(row);
        } else if (row.dropped) {
          _todos.removeAt(index);
        } else {
          _todos[index] = row;
        }
      }
    } else {
      _todos
        ..clear()
        ..addAll(incoming.where((row) => !row.dropped));
    }
    _emitTodos();
  }

  /// `cursor/task`. Documented as a notification about a subagent.
  ///
  /// TODO: the page also shows a response body. Whether a message that
  /// carries an id is waiting on the client is not settled here.
  void task(Map<String, Object?> params) {
    final id = params['toolCallId'];
    final description = params['description'];
    if (id is! String || description is! String) return;
    final prompt = params['prompt'];
    emit(
      ItemUpserted(
        nextSeq(),
        'task:$id',
        ToolCallItem(
          kind: ToolKind.agent,
          target: description,
          detail: _subagentType(params['subagentType']),
          output: prompt is String ? prompt : null,
          tool: 'task',
          callId: id,
          status: params['durationMs'] is num
              ? ToolStatus.succeeded
              : ToolStatus.running,
        ),
      ),
    );
  }

  /// `cursor/generate_image`. The file path is shown; the bytes are not
  /// read.
  ///
  /// TODO: render [imageData] when Cursor sends the response form, and
  /// decide whether a request id means the client must generate the file.
  void generateImage(Map<String, Object?> params) {
    final id = params['toolCallId'];
    final description = params['description'];
    if (id is! String || description is! String) return;
    final filePath = params['filePath'];
    final path = filePath is String && filePath.isNotEmpty ? filePath : null;
    emit(
      ItemUpserted(
        nextSeq(),
        'image:$id',
        ToolCallItem(
          kind: ToolKind.image,
          target: description,
          path: path,
          imageFiles: [?path],
          tool: 'generate_image',
          callId: id,
        ),
      ),
    );
  }

  /// Closes text and thoughts still streaming.
  void finish() {
    _finishMessage();
    _finishThought();
  }

  void _chunk(Map<String, Object?> update, {required bool thought}) {
    final content = cursorJsonMap(update['content']);
    final text = content?['text'];
    if (content?['type'] != 'text' || text is! String || text.isEmpty) return;
    final messageId = update['messageId'];
    final key = messageId is String && messageId.isNotEmpty
        ? messageId
        : (thought ? 'thought' : 'message');
    if (thought) {
      if (_thoughtKey != null && _thoughtKey != key) _finishThought();
      final fresh = _thoughtKey != key;
      _thoughtKey = key;
      final offset = _thought.length;
      _thought += text;
      final id = 'thought:$key';
      if (fresh) {
        _thoughtStarted = DateTime.now();
        emit(
          ItemUpserted(
            nextSeq(),
            id,
            ThinkingItem(
              text: _thought,
              tokens: _thought.length,
              startedAt: _thoughtStarted,
            ),
            streaming: true,
          ),
        );
      } else {
        emit(TextDelta(nextSeq(), id, offset, text, tokens: _thought.length));
      }
      return;
    }
    if (_messageKey != null && _messageKey != key) _finishMessage();
    final fresh = _messageKey != key;
    _messageKey = key;
    final offset = _message.length;
    _message += text;
    final id = 'message:$key';
    if (fresh) {
      emit(
        ItemUpserted(
          nextSeq(),
          id,
          AssistantTextItem(_message),
          streaming: true,
        ),
      );
    } else {
      emit(TextDelta(nextSeq(), id, offset, text));
    }
  }

  void _finishMessage() {
    final key = _messageKey;
    if (key == null) return;
    emit(
      ItemCompleted(
        nextSeq(),
        'message:$key',
        item: AssistantTextItem(_message),
      ),
    );
    _messageKey = null;
    _message = '';
  }

  void _finishThought() {
    final key = _thoughtKey;
    if (key == null) return;
    final started = _thoughtStarted;
    final elapsed = started == null
        ? 1
        : DateTime.now().difference(started).inSeconds;
    final seconds = elapsed < 1 ? 1 : elapsed;
    emit(
      ItemCompleted(
        nextSeq(),
        'thought:$key',
        item: ThinkingItem(
          text: _thought,
          tokens: _thought.length,
          seconds: seconds,
        ),
      ),
    );
    _thoughtKey = null;
    _thought = '';
    _thoughtStarted = null;
  }

  void _userChunk(Map<String, Object?> update) {
    if (!replaying) return;
    final content = cursorJsonMap(update['content']);
    final text = content?['text'];
    if (content?['type'] != 'text' || text is! String || text.isEmpty) return;
    final messageId = update['messageId'];
    final key = messageId is String && messageId.isNotEmpty
        ? messageId
        : 'user';
    final id = 'user:$key';
    final next = (_userText[id] ?? '') + text;
    _userText[id] = next;
    emit(ItemUpserted(nextSeq(), id, UserMessageItem(text: next)));
  }

  void _tool(Map<String, Object?> update) {
    final id = update['toolCallId'];
    if (id is! String || id.isEmpty) return;
    final tool = _tools.putIfAbsent(id, _Tool.new);
    final title = update['title'];
    final name = update['name'];
    final kind = update['kind'];
    final status = update['status'];
    if (title is String && title.isNotEmpty) tool.title = title;
    if (name is String && name.isNotEmpty) tool.name = name;
    if (kind is String && kind.isNotEmpty) tool.kind = kind;
    if (status is String && status.isNotEmpty) tool.status = status;
    if (update.containsKey('rawInput')) tool.rawInput = update['rawInput'];
    final locations = update['locations'];
    if (locations is List && locations.isNotEmpty) {
      final first = cursorJsonMap(locations.first);
      final path = first?['path'];
      if (path is String && path.isNotEmpty) tool.path = path;
    }
    _takeContent(tool, id, update['content']);
    emit(ItemUpserted(nextSeq(), id, tool.item));
  }

  void _takeContent(_Tool tool, String id, Object? raw) {
    if (raw is! List) return;
    var diffIndex = tool.diffs;
    for (final entry in raw) {
      final block = cursorJsonMap(entry);
      if (block == null) continue;
      switch (block['type']) {
        case 'content':
          final content = cursorJsonMap(block['content']);
          final text = content?['text'];
          if (content?['type'] == 'text' && text is String && text.isNotEmpty) {
            if (tool.output.isNotEmpty) tool.output.write('\n');
            tool.output.write(text);
          }
        case 'diff':
          // oldText/newText are the documented diff body. A full line diff
          // is a follow-up; a new file (no old text) is shown as added.
          final path = block['path'];
          if (path is String && path.isNotEmpty) tool.path ??= path;
          final oldText = block['oldText'];
          final newText = block['newText'];
          if (oldText == null && newText is String && path is String) {
            _emitNewFile(id, diffIndex, path, newText);
            diffIndex++;
          }
        case 'terminal':
          // TODO: embed the terminal once `terminal/create` is implemented.
          // The minimal client advertises terminal: false, so this should
          // not arrive. https://agentclientprotocol.com/protocol/v1/terminals
          final terminalId = block['terminalId'];
          if (terminalId is String && terminalId.isNotEmpty) {
            if (tool.output.isNotEmpty) tool.output.write('\n');
            tool.output.write('terminal $terminalId');
          }
      }
    }
    tool.diffs = diffIndex;
  }

  void _emitNewFile(String toolId, int index, String path, String text) {
    final lines = <DiffLine>[
      for (final (number, line) in text.split('\n').indexed)
        DiffLine(DiffLineType.added, number + 1, line),
    ];
    final cut = path.replaceAll(r'\', '/');
    final slash = cut.lastIndexOf('/');
    emit(
      ItemUpserted(
        nextSeq(),
        '$toolId:diff:$index',
        CodeDiffItem(
          fileName: slash < 0 ? cut : cut.substring(slash + 1),
          directory: slash < 0 ? '' : cut.substring(0, slash),
          lines: lines,
        ),
      ),
    );
  }

  void _plan(Object? entries) {
    final todos = cursorPlanTodos(entries);
    _todos
      ..clear()
      ..addAll([
        for (var i = 0; i < todos.length; i++)
          _TodoRow('$i', todos[i], dropped: false),
      ]);
    _emitTodos();
  }

  void _usage(Map<String, Object?> update) {
    final used = update['used'];
    final size = update['size'];
    if (used is! num || size is! num) return;
    emit(
      UsageReported(
        nextSeq(),
        ContextUsage(window: size.round(), used: used.round()),
      ),
    );
    // TODO: surface cost.amount when the chat should show USD. The field
    // is documented (currency + amount) but not wired to UsageStats yet.
    // https://agentclientprotocol.com/protocol/v1/prompt-turn
  }

  void _emitTodos() {
    emit(TodosReported(nextSeq(), [for (final row in _todos) row.entry]));
  }
}

class _Tool {
  String? title;
  String? name;
  String? kind;
  String? status;
  String? path;
  Object? rawInput;
  final StringBuffer output = StringBuffer();
  int diffs = 0;

  ToolCallItem get item {
    final label = title ?? name ?? kind ?? 'tool';
    final input = rawInput is Map
        ? Map<String, Object?>.from(rawInput as Map)
        : const <String, Object?>{};
    return ToolCallItem(
      kind: _toolKind(kind),
      target: label,
      detail: name != null && name != label ? name : null,
      path: path,
      label: title,
      status: _toolStatus(status),
      output: output.isEmpty ? null : output.toString(),
      tool: name,
      input: input,
    );
  }
}

class _TodoRow {
  _TodoRow(this.id, this.entry, {required this.dropped});

  final String id;
  final TodoEntry entry;

  /// A `cancelled` cursor todo: dropped from the list the UI can show.
  final bool dropped;
}

ToolKind _toolKind(String? kind) => switch (kind) {
  'read' => ToolKind.read,
  'edit' || 'delete' || 'move' => ToolKind.edit,
  'search' => ToolKind.grep,
  'execute' => ToolKind.command,
  'fetch' => ToolKind.web,
  'think' => ToolKind.other,
  _ => ToolKind.other,
};

ToolStatus _toolStatus(String? status) => switch (status) {
  'failed' => ToolStatus.failed,
  'completed' => ToolStatus.succeeded,
  _ => ToolStatus.running,
};

String _wireStatus(TodoStatus status) => switch (status) {
  TodoStatus.pending => 'pending',
  TodoStatus.inProgress => 'in_progress',
  TodoStatus.completed => 'completed',
};

String? _subagentType(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  final custom = cursorJsonMap(value)?['custom'];
  if (custom is String && custom.isNotEmpty) return custom;
  return null;
}

TodoStatus? cursorTodoStatus(String? status) => switch (status) {
  'pending' => TodoStatus.pending,
  'in_progress' => TodoStatus.inProgress,
  'completed' => TodoStatus.completed,
  _ => null,
};

/// ACP `plan` entries (`content`, `priority`, `status`). Priority is not
/// shown: [TodoEntry] has no place for it.
List<TodoEntry> cursorPlanTodos(Object? entries) {
  if (entries is! List) return const [];
  final todos = <TodoEntry>[];
  for (final raw in entries) {
    final entry = cursorJsonMap(raw);
    final content = entry?['content'];
    final status = cursorTodoStatus(entry?['status'] as String?);
    if (content is! String || content.isEmpty || status == null) continue;
    todos.add(TodoEntry(content, status));
  }
  return todos;
}

List<_TodoRow> _cursorTodos(Object? raw) {
  if (raw is! List) return const [];
  final rows = <_TodoRow>[];
  for (final item in raw) {
    final todo = cursorJsonMap(item);
    final id = todo?['id'];
    final content = todo?['content'];
    if (id is! String || content is! String) continue;
    final status = cursorTodoStatus(todo?['status'] as String?);
    if (todo?['status'] == 'cancelled' || status == null) {
      rows.add(
        _TodoRow(id, TodoEntry(content, TodoStatus.pending), dropped: true),
      );
      continue;
    }
    rows.add(_TodoRow(id, TodoEntry(content, status), dropped: false));
  }
  return rows;
}

/// `session/request_permission`, as the ACP tool-call page shows it.
/// Option ids fall back to Cursor's `allow-once` / `allow-always` /
/// `reject-once` when the request lists none.
///
/// https://cursor.com/docs/cli/acp
/// https://agentclientprotocol.com/protocol/v1/tool-calls
class CursorPermissionChoice {
  const CursorPermissionChoice({
    required this.title,
    required this.toolName,
    this.reason,
    this.preview,
    this.alwaysAllowLabel,
    this.allowOnceId = 'allow-once',
    this.allowAlwaysId,
    this.rejectId = 'reject-once',
  });

  final String title;
  final String toolName;
  final String? reason;
  final ApprovalPreview? preview;
  final String? alwaysAllowLabel;
  final String allowOnceId;
  final String? allowAlwaysId;
  final String rejectId;
}

CursorPermissionChoice cursorPermissionChoice(Map<String, Object?> params) {
  final tool = cursorJsonMap(params['toolCall']) ?? const {};
  final title =
      _firstString([tool['title'], tool['name'], tool['kind']]) ?? 'Permission';
  final toolName = _firstString([tool['name'], tool['kind']]) ?? 'tool';
  String? allowOnce;
  String? allowAlways;
  String? reject;
  String? alwaysLabel;
  final options = params['options'];
  if (options is List) {
    for (final raw in options) {
      final option = cursorJsonMap(raw);
      final id = option?['optionId'];
      if (id is! String || id.isEmpty) continue;
      final kind = option?['kind'];
      final name = option?['name'];
      switch (kind) {
        case 'allow_once':
          allowOnce ??= id;
        case 'allow_always':
          allowAlways ??= id;
          if (name is String && name.isNotEmpty) alwaysLabel ??= name;
        case 'reject_once' || 'reject_always':
          reject ??= id;
        default:
          // Cursor's example uses these ids inside `optionId`.
          switch (id) {
            case 'allow-once':
              allowOnce ??= id;
            case 'allow-always':
              allowAlways ??= id;
              if (name is String && name.isNotEmpty) alwaysLabel ??= name;
            case 'reject-once':
              reject ??= id;
          }
      }
    }
  }
  return CursorPermissionChoice(
    title: title,
    toolName: toolName,
    reason: _permissionReason(tool),
    preview: _permissionPreview(tool),
    alwaysAllowLabel: allowAlways == null
        ? null
        : alwaysLabel ?? 'Allow always',
    allowOnceId: allowOnce ?? 'allow-once',
    allowAlwaysId: allowAlways,
    rejectId: reject ?? 'reject-once',
  );
}

String? _permissionReason(Map<String, Object?> tool) {
  final locations = tool['locations'];
  if (locations is! List || locations.isEmpty) return null;
  final path = cursorJsonMap(locations.first)?['path'];
  return path is String && path.isNotEmpty ? path : null;
}

ApprovalPreview? _permissionPreview(Map<String, Object?> tool) {
  final raw = tool['rawInput'];
  if (raw == null) return null;
  if (raw is String && raw.isEmpty) return null;
  if (tool['kind'] == 'execute' && raw is String) return CommandPreview(raw);
  if (raw is String) return TextPreview(raw);
  return TextPreview(jsonEncode(raw));
}

/// `cursor/ask_question`. Null when there is nothing to ask, so the kernel
/// can answer `skipped` and not leave the agent blocked.
class CursorQuestionForm {
  const CursorQuestionForm({required this.title, required this.questions});

  final String title;
  final List<CursorQuestionBinding> questions;
}

class CursorQuestionBinding {
  const CursorQuestionBinding({
    required this.id,
    required this.question,
    required this.labelToId,
  });

  final String id;
  final Question question;

  /// The label the chat UI sends back, to the option id ACP wants.
  final Map<String, String> labelToId;
}

CursorQuestionForm? cursorQuestionForm(Map<String, Object?> params) {
  final rawQuestions = params['questions'];
  if (rawQuestions is! List) return null;
  final questions = <CursorQuestionBinding>[];
  for (final raw in rawQuestions) {
    final question = cursorJsonMap(raw);
    final id = question?['id'];
    final prompt = question?['prompt'];
    final options = question?['options'];
    if (id is! String || prompt is! String || options is! List) continue;
    final labelToId = <String, String>{};
    final choices = <QuestionOption>[];
    for (final optionRaw in options) {
      final option = cursorJsonMap(optionRaw);
      final optionId = option?['id'];
      final label = option?['label'];
      if (optionId is! String || label is! String || label.isEmpty) continue;
      labelToId[label] = optionId;
      choices.add(QuestionOption(label));
    }
    if (choices.isEmpty) continue;
    questions.add(
      CursorQuestionBinding(
        id: id,
        labelToId: labelToId,
        question: Question(
          prompt: prompt,
          header: id.length <= 24 ? id : '',
          options: choices,
          allowMultiple: question?['allowMultiple'] == true,
          // The documented options are a fixed list. No free-text field.
          allowOther: false,
        ),
      ),
    );
  }
  if (questions.isEmpty) return null;
  final title = params['title'];
  return CursorQuestionForm(
    title: title is String && title.isNotEmpty ? title : 'Question',
    questions: questions,
  );
}

/// Todos from `cursor/create_plan`, top-level plus each phase's, in order.
/// `cancelled` entries are left out: the chat's todo row has no such state.
///
/// TODO: phase grouping in the plan card, and `planUri` after accept.
/// https://cursor.com/docs/cli/acp
List<TodoEntry> cursorCreatePlanTodos(Map<String, Object?> params) {
  final todos = <TodoEntry>[];
  void take(Object? raw, String prefix) {
    if (raw is! List) return;
    for (final item in raw) {
      final todo = cursorJsonMap(item);
      final content = todo?['content'];
      final status = cursorTodoStatus(todo?['status'] as String?);
      if (content is! String || content.isEmpty || status == null) continue;
      todos.add(
        TodoEntry(prefix.isEmpty ? content : '$prefix: $content', status),
      );
    }
  }

  take(params['todos'], '');
  final phases = params['phases'];
  if (phases is List) {
    for (final raw in phases) {
      final phase = cursorJsonMap(raw);
      final name = phase?['name'];
      take(phase?['todos'], name is String ? name : '');
    }
  }
  return todos;
}

String? _firstString(List<Object?> values) {
  for (final value in values) {
    if (value is String && value.isNotEmpty) return value;
  }
  return null;
}
