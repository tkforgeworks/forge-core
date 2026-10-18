# forge-core

Shared sign-in, account and data plumbing for tkforgeworks Flutter apps,
built on Supabase. The Dart package is `forge_core`; its sibling
[`forge-ui`](https://github.com/tkforgeworks/forge-ui) carries the brand look.
Apps depend on both, and the two packages never depend on each other.

**Status: pre-release, v0.1.0 in progress.** Configuration, client
initialisation and session state exist; sign-in, accounts, deletion and the
data helper arrive ticket by ticket (Jira project `FC`).

## What it owns

- Google and email/password sign-in, session state and identity linking
  (Apple when an iOS app exists)
- In-app account deletion, including the server-side purge
- A typed repository helper over a generic jsonb `entries` table

It never contains Supabase URLs or keys, app schemas, or UI styling: each app
passes in its own configuration.

## Configuration

An app's Supabase URL, publishable key and Google web client ID are public
by design but never committed. They reach the app as `--dart-define`s:

| Define | Value |
| --- | --- |
| `FORGE_SUPABASE_URL` | `https://<ref>.supabase.co` |
| `FORGE_SUPABASE_PUBLISHABLE_KEY` | the project's `sb_publishable_…` key |
| `FORGE_GOOGLE_WEB_CLIENT_ID` | the Google Cloud **Web** OAuth client ID (empty if no Google sign-in) |

Locally, keep them in a gitignored JSON file and build with
`flutter run --dart-define-from-file=config/dev.json`:

```json
{
  "FORGE_SUPABASE_URL": "https://abc.supabase.co",
  "FORGE_SUPABASE_PUBLISHABLE_KEY": "sb_publishable_…",
  "FORGE_GOOGLE_WEB_CLIENT_ID": "123.apps.googleusercontent.com"
}
```

Release builds get them from the org release pipeline. In code:

```dart
const config = ForgeSupabaseConfig.fromEnvironment();
final core = config.isConfigured ? await ForgeCore.initialize(config) : null;
// core == null: a build with no backend; the app keeps working locally.
core?.auth.changes.listen((state) => /* signed in? */ state.isSignedIn);
```

Widget tests use `FakeForgeAuth` from `package:forge_core/testing.dart`
instead of a client, so nothing touches the network.

## Signing in

```dart
switch (await core.auth.signInWithGoogle()) {
  case ForgeAuthSuccess(:final session): // signed in; `changes` emits too
  case ForgeAuthCancelled(): // the user backed out; say nothing
  case ForgeAuthFailure(:final error, :final message): // show copy for `error`
}
```

Google sign-in is native (Credential Manager on Android) and needs the
Google Cloud and Supabase setup in
[`docs/google-cloud-setup.md`](docs/google-cloud-setup.md). It is offered
only when `FORGE_GOOGLE_WEB_CLIENT_ID` is set; otherwise the call returns
`ForgeAuthError.misconfigured` without showing any UI.

Email and password go through the same result type, plus
`ForgeAuthEmailSent` for the steps that wait on an inbox:

```dart
// Create an account; confirmation is required, so a mail goes out and the
// session arrives through `changes` when the link is opened on this device.
await core.auth.signUpWithEmail(email, password); // ForgeAuthEmailSent
await core.auth.signInWithEmail(email, password); // ForgeAuthSuccess | Failure
await core.auth.resendConfirmation(email);
await core.auth.sendPasswordReset(email);         // opening the link → passwordRecovery
await core.auth.updatePassword(newPassword);      // while signed in
```

Pass the app's custom scheme as `authRedirectUrl` so the links open the
app (a valid URL scheme: an application id with an underscore drops it,
`com.example.myapp://auth-callback`); the Supabase side (Resend as SMTP, confirmation on, templates,
redirect allow list) and the Android intent filter are in
[`docs/email-setup.md`](docs/email-setup.md).

## Account and data

```dart
final account = await core.accounts.getAccount();   // ForgeResult<ForgeAccount?>
await core.accounts.setUsername('Tim');
await core.accounts.deleteAccount();                // flags, signs out everywhere; see docs/deletion.md

final notes = core.entries<TastingNote>(
  kind: 'tasting_note',
  fromJson: TastingNote.fromJson,
  toJson: (n) => n.toJson(),
);
await notes.upsertAll(dirty);                      // push local edits
final keys = await notes.listKeys(since: lastSync); // what changed remotely
final newer = await notes.fetchByIds(ids);          // pull those rows
await notes.markDeleted(deletedIds, now);           // push deletions
```

Data calls return `ForgeResult<T>`: `ForgeOk(value)` or
`ForgeFailed(ForgeDataError, message)`. The SQL behind them (the `accounts`
migration and the `entries` template an app copies into its own
migrations) is under `supabase/`, with the rules every app table follows in
[`docs/data-model.md`](docs/data-model.md).

## Supabase files in your app

```sh
dart run forge_core:sync_supabase   # copy migrations, functions, templates; write supabase/forge_core.lock
```

and one test, `expect(await forgeSupabaseDrift(), isEmpty)` from
`package:forge_core/sync_check.dart`, so the copies cannot quietly diverge
from the pinned version. Deploying them is
[`docs/supabase-deploy.md`](docs/supabase-deploy.md); deletion end to end is
[`docs/deletion.md`](docs/deletion.md).

## Privacy

Every app on the packages collects the same account data, so the data
inventory and the privacy policy are written once:
[`docs/privacy/`](docs/privacy/) has the `PRIVACY.md` template (with the
Play Data safety mapping and the store checklist) and the policy page
template in the tkforgeworks voice. Fill in the placeholders and add only
what your app adds.

The full design is in
[`docs/forge-ui_forge-core_Shared_Flutter_Packages_Spec.md`](docs/forge-ui_forge-core_Shared_Flutter_Packages_Spec.md).

## Development

```sh
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Work lands by pull request into the current release branch (`vX.Y.Z/main`),
never directly into `main`. See the org
[contributing guide](https://github.com/tkforgeworks/.github/blob/main/CONTRIBUTING.md).

## License

Apache-2.0 — see [`LICENSE`](LICENSE). Image assets (logos, icons,
illustrations, screenshots) are **not** covered and are all rights reserved;
see [`NOTICE`](NOTICE).
