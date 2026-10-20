import 'dart:io';

import '../../platform/app_paths.dart';
import 'cursor_agent_locator.dart';
import 'cursor_agent_path_setting.dart';

Future<CursorAgentExecutable> locateCursorAgent() async {
  final environment = Map<String, String>.from(Platform.environment);
  return resolveCursorAgent(
    environment: environment,
    home: AppPaths.home(environment),
    pathListSeparator: Platform.isWindows ? ';' : ':',
    fileSeparator: Platform.pathSeparator,
    windows: Platform.isWindows,
    configuredPath: CursorAgentPathSetting.current(),
    exists: _isFile,
  );
}

bool _isFile(String path) {
  final type = FileSystemEntity.typeSync(path);
  return type == FileSystemEntityType.file || type == FileSystemEntityType.link;
}
