/// The drift check an app runs inside `flutter test`, and the file logic
/// behind `dart run forge_core:sync_supabase`. Pure Dart: no Flutter
/// imports, so the executable can use it under the plain VM.
///
/// ```dart
/// test('supabase files match the pinned forge_core', () async {
///   expect(await forgeSupabaseDrift(), isEmpty);
/// });
/// ```
library;

import 'dart:io';

import 'src/sync/supabase_files.dart';

export 'src/sync/supabase_files.dart' show ForgeSupabaseFiles;

/// Problems between the app's `supabase/` folder (under [appDir], default
/// the current directory) and the files the pinned forge_core ships. Empty
/// means in sync. Fix by running `dart run forge_core:sync_supabase`.
Future<List<String>> forgeSupabaseDrift({Directory? appDir}) async {
  final app = appDir ?? Directory.current;
  return ForgeSupabaseFiles.drift(
    await ForgeSupabaseFiles.packageRoot(from: Directory.current),
    app,
  );
}
