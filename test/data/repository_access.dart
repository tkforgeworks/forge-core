import 'package:forge_core/forge_core.dart';
import 'package:forge_core/src/data/forge_entries_repository.dart';

import 'forge_entries_repository_test.dart' show Note;

/// Test-only access to the page and chunk sizes.
abstract final class SupabaseForgeEntriesRepositoryAccess {
  static ForgeEntriesRepository<Note> build(
    ForgeCore core,
    int pageSize,
    int chunkSize,
  ) => SupabaseForgeEntriesRepository<Note>(
    core.client,
    core.auth,
    kind: 'tasting_note',
    fromJson: Note.fromJson,
    toJson: (n) => n.toJson(),
    pageSize: pageSize,
    chunkSize: chunkSize,
  );
}
