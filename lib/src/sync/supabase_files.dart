// Pure Dart (no Flutter imports): used by `bin/sync_supabase.dart` under the
// plain Dart VM and by the drift check inside an app's `flutter test`.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// The files forge_core ships for an app's `supabase/` folder: the
/// `*_forge_*` migrations, the `forge-*` Edge Functions with `_shared`, and
/// the auth email templates. Smoke tests stay in this repo.
class ForgeSupabaseFiles {
  const ForgeSupabaseFiles._();

  /// Where the lock file lives inside an app's `supabase/` folder.
  static const lockFile = 'forge_core.lock';

  /// Relative paths (under `supabase/`) of every file forge_core owns in
  /// [packageRoot].
  static List<String> ownedPaths(Directory packageRoot) {
    final base = Directory('${packageRoot.path}/supabase');
    final out = <String>[];
    void walk(Directory dir, bool Function(String rel) keep) {
      if (!dir.existsSync()) return;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        final rel = _relative(entity.path, base.path);
        if (keep(rel)) out.add(rel);
      }
    }

    walk(
      Directory('${base.path}/migrations'),
      (rel) => rel.endsWith('.sql') && rel.contains('_forge_'),
    );
    walk(
      Directory('${base.path}/functions'),
      (rel) =>
          rel.startsWith('functions/forge-') ||
          rel.startsWith('functions/_shared/'),
    );
    walk(Directory('${base.path}/templates'), (_) => true);
    out.sort();
    return out;
  }

  /// Copies every owned file from [packageRoot] into [appDir]/supabase and
  /// writes the lock. Returns the paths written.
  static List<String> sync(Directory packageRoot, Directory appDir) {
    final paths = ownedPaths(packageRoot);
    final hashes = <String, String>{};
    for (final rel in paths) {
      final src = File('${packageRoot.path}/supabase/$rel');
      final dst = File('${appDir.path}/supabase/$rel')
        ..parent.createSync(recursive: true);
      src.copySync(dst.path);
      hashes[rel] = _sha256(src);
    }
    final lock = {
      'forge_core': packageVersion(packageRoot),
      'synced_at': DateTime.now().toUtc().toIso8601String(),
      'files': hashes,
    };
    File('${appDir.path}/supabase/$lockFile')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(lock)}\n',
      );
    return paths;
  }

  /// Compares [appDir]/supabase with [packageRoot]'s owned files. Empty when
  /// nothing drifted; otherwise one line per problem: `missing <path>`,
  /// `differs <path>`, or `stale <path>` (a forge file the package no longer
  /// ships) and `lock <reason>`.
  static List<String> drift(Directory packageRoot, Directory appDir) {
    final problems = <String>[];
    final owned = ownedPaths(packageRoot);
    for (final rel in owned) {
      final app = File('${appDir.path}/supabase/$rel');
      if (!app.existsSync()) {
        problems.add('missing $rel');
      } else if (_sha256(app) !=
          _sha256(File('${packageRoot.path}/supabase/$rel'))) {
        problems.add('differs $rel');
      }
    }
    // Forge files in the app that the package does not ship any more.
    final appSupabase = Directory('${appDir.path}/supabase');
    if (appSupabase.existsSync()) {
      final ownedSet = owned.toSet();
      for (final rel in ownedPaths(appDir)) {
        if (!ownedSet.contains(rel)) problems.add('stale $rel');
      }
    }
    final lock = File('${appDir.path}/supabase/$lockFile');
    if (!lock.existsSync()) {
      problems.add(
        'lock $lockFile is missing (run `dart run forge_core:sync_supabase`)',
      );
    } else {
      try {
        final json =
            jsonDecode(lock.readAsStringSync()) as Map<String, dynamic>;
        final version = json['forge_core'];
        final expected = packageVersion(packageRoot);
        if (version != expected) {
          problems.add(
            'lock records forge_core $version, package is $expected',
          );
        }
      } on FormatException {
        problems.add('lock $lockFile is not valid JSON');
      }
    }
    return problems;
  }

  /// The `version:` from [packageRoot]'s pubspec.
  static String packageVersion(Directory packageRoot) {
    final pubspec = File('${packageRoot.path}/pubspec.yaml').readAsLinesSync();
    for (final line in pubspec) {
      if (line.startsWith('version:')) return line.substring(8).trim();
    }
    return 'unknown';
  }

  /// This package's root on disk, wherever pub put it (a git checkout in
  /// the pub cache for an app; the repo itself for forge_core's own tests).
  ///
  /// Under the plain Dart VM (`dart run forge_core:sync_supabase`) the
  /// isolate resolves the package URI. `flutter test` does not support
  /// that, so the fallback reads `.dart_tool/package_config.json`, found by
  /// walking up from [from] (default the current directory, the app root
  /// when tests run).
  static Future<Directory> packageRoot({Directory? from}) async {
    try {
      final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:forge_core/sync_check.dart'),
      );
      if (uri != null) return File.fromUri(uri).parent.parent;
    } on UnsupportedError {
      // flutter_test: fall through to the package config.
    }
    var dir = (from ?? Directory.current).absolute;
    while (true) {
      final config = File('${dir.path}/.dart_tool/package_config.json');
      if (config.existsSync()) {
        final json =
            jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
        for (final pkg in json['packages'] as List) {
          final map = pkg as Map<String, dynamic>;
          if (map['name'] != 'forge_core') continue;
          final root = config.parent.uri.resolve(map['rootUri'] as String);
          return Directory.fromUri(root);
        }
        throw StateError(
          'forge_core is not a dependency of ${dir.path} '
          '(not in .dart_tool/package_config.json)',
        );
      }
      final parent = dir.parent;
      if (parent.path == dir.path) {
        throw StateError(
          'No .dart_tool/package_config.json above ${Directory.current.path}; '
          'run from the app root after `flutter pub get`',
        );
      }
      dir = parent;
    }
  }

  static String _sha256(File file) =>
      sha256.convert(file.readAsBytesSync()).toString();

  static String _relative(String path, String base) {
    final normalizedBase = base.endsWith('/') ? base : '$base/';
    return path.startsWith(normalizedBase)
        ? path.substring(normalizedBase.length)
        : path;
  }
}
