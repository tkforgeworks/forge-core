/// Shared sign-in, account and data plumbing for tkforgeworks Flutter apps.
///
/// v0.1.0 is being built against the spec in
/// `docs/forge-ui_forge-core_Shared_Flutter_Packages_Spec.md`; the public
/// API grows ticket by ticket (Jira project FC). Test doubles live in
/// `package:forge_core/testing.dart`.
library;

export 'src/auth/forge_auth.dart' show ForgeAuth;
export 'src/auth/forge_session.dart';
export 'src/config/forge_supabase_config.dart';
export 'src/forge_core.dart';
