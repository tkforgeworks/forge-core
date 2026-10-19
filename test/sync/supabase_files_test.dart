import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/sync_check.dart';

void main() {
  late Directory root;
  late Directory app;

  setUp(() async {
    root = await ForgeSupabaseFiles.packageRoot();
    app = await Directory.systemTemp.createTemp('forge-sync-app');
    addTearDown(() => app.delete(recursive: true));
  });

  test('the package root resolves to this repo (via package_config)', () {
    expect(File('${root.path}/pubspec.yaml').existsSync(), isTrue);
    expect(ForgeSupabaseFiles.packageVersion(root), startsWith('0.1.0'));
    expect(Directory('${root.path}/supabase/migrations').existsSync(), isTrue);
  });

  test('owned files are the forge migrations, functions and templates', () {
    final owned = ForgeSupabaseFiles.ownedPaths(root);
    expect(owned, contains('migrations/20261018120000_forge_accounts.sql'));
    expect(owned, contains('functions/forge-purge/index.ts'));
    expect(owned, contains('functions/_shared/mail.ts'));
    expect(owned, contains('templates/confirmation.html'));
    expect(owned.where((p) => p.startsWith('smoke/')), isEmpty);
    expect(owned, equals([...owned]..sort()));
  });

  test('sync copies everything and writes the lock; drift is then empty', () {
    final written = ForgeSupabaseFiles.sync(root, app);
    expect(written, ForgeSupabaseFiles.ownedPaths(root));
    for (final rel in written) {
      expect(
        File('${app.path}/supabase/$rel').existsSync(),
        isTrue,
        reason: rel,
      );
    }
    final lock = jsonDecode(
      File('${app.path}/supabase/${ForgeSupabaseFiles.lockFile}')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(lock['forge_core'], ForgeSupabaseFiles.packageVersion(root));
    expect((lock['files'] as Map).keys, containsAll(written));
    expect(ForgeSupabaseFiles.drift(root, app), isEmpty);
  });

  test('drift reports differing, missing, stale files and a bad lock', () {
    ForgeSupabaseFiles.sync(root, app);
    File('${app.path}/supabase/functions/forge-purge/index.ts')
        .writeAsStringSync('// tampered\n', mode: FileMode.append);
    File('${app.path}/supabase/templates/recovery.html').deleteSync();
    File('${app.path}/supabase/migrations/20990101000000_forge_old.sql')
      ..createSync(recursive: true)
      ..writeAsStringSync('-- no longer shipped');
    File('${app.path}/supabase/${ForgeSupabaseFiles.lockFile}')
        .writeAsStringSync('{"forge_core": "0.0.1+1", "files": {}}');
    final problems = ForgeSupabaseFiles.drift(root, app);
    expect(problems, contains('differs functions/forge-purge/index.ts'));
    expect(problems, contains('missing templates/recovery.html'));
    expect(problems, contains('stale migrations/20990101000000_forge_old.sql'));
    expect(
      problems.where((p) => p.startsWith('lock records forge_core 0.0.1+1')),
      hasLength(1),
    );
    // The app's own migrations are not the package's business.
    File('${app.path}/supabase/migrations/20261101000000_entries.sql')
        .writeAsStringSync('-- app file');
    expect(
      ForgeSupabaseFiles.drift(root, app).where((p) => p.contains('entries')),
      isEmpty,
    );
  });

  test('forgeSupabaseDrift reads the current directory by default', () async {
    final problems = await forgeSupabaseDrift(appDir: app);
    expect(problems.first, startsWith('missing '));
    expect(problems.last, startsWith('lock '));
  });
}
