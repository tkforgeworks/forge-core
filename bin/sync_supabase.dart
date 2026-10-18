// Copies forge_core's Supabase files into the app that depends on it, at the
// version the app pins, and writes supabase/forge_core.lock. Run from the
// app's root:
//
//   dart run forge_core:sync_supabase          # copy and write the lock
//   dart run forge_core:sync_supabase --check  # exit 1 and list drift
//
// The app then deploys with the Supabase CLI (docs/supabase-deploy.md), and
// a test calling forgeSupabaseDrift() keeps the copies honest.
import 'dart:io';

import 'package:forge_core/sync_check.dart';

Future<void> main(List<String> args) async {
  final check = args.contains('--check');
  final dirArg = args.indexOf('--app-dir');
  final appDir = dirArg >= 0 && dirArg + 1 < args.length
      ? Directory(args[dirArg + 1])
      : Directory.current;
  final root = await ForgeSupabaseFiles.packageRoot();
  final version = ForgeSupabaseFiles.packageVersion(root);

  if (check) {
    final problems = ForgeSupabaseFiles.drift(root, appDir);
    if (problems.isEmpty) {
      stdout.writeln('supabase/ matches forge_core $version');
      return;
    }
    stderr.writeln('supabase/ differs from forge_core $version:');
    for (final p in problems) {
      stderr.writeln('  $p');
    }
    stderr.writeln('Run `dart run forge_core:sync_supabase` to update.');
    exitCode = 1;
    return;
  }

  final written = ForgeSupabaseFiles.sync(root, appDir);
  stdout.writeln(
    'Synced ${written.length} files from forge_core $version into '
    '${appDir.path}/supabase:',
  );
  for (final p in written) {
    stdout.writeln('  $p');
  }
  stdout.writeln('Wrote supabase/${ForgeSupabaseFiles.lockFile}.');
  stdout.writeln('Next: deploy per docs/supabase-deploy.md in forge-core.');
}
