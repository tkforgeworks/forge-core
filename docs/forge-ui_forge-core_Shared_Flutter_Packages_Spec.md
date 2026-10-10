# forge-ui & forge-core: Shared Flutter Packages Spec

Oct 8, 2026 · @Tim Klimpel · Status: Approved, ready to start

## Purpose and goals

All tkforgeworks client apps move to Flutter, so two shared packages carry the parts every app repeats: `forge-ui` for the brand look, `forge-core` for sign-in, account and data plumbing. Each app supplies only its colors, icon, Supabase config and domain screens.

Goals:

- **One brand, many apps.** Typography, shapes, spacing and shared screens are identical across apps; each app changes its seed color and icon.
- **Write auth and account deletion once.** Google + Apple sign-in, identity linking and deletion live in `forge-core`, not in each app.
- **Store-ready by default.** Any app built on the packages starts compliant with Apple guideline 4.8, in-app account deletion on both stores, and a short, honest privacy disclosure.
- **Stay in free tiers during development.** Supabase free plan for dev; paid only once an app has real users.

Non-goals for v1: analytics, crash reporting, push notifications, file/photo storage helpers, and a lint/CLAUDE.md org standard.

## Scope and package boundaries

Apps depend on both packages; the two packages never depend on each other. Shared screens in `forge-ui` (sign-in, account settings) take callbacks, and each app wires those callbacks to `forge-core`. This keeps `forge-ui` free of Supabase and `forge-core` free of styling.

| Layer | Owns | Examples | Never contains |
| --- | --- | --- | --- |
| `forge-ui` | Brand look and generic screens | Theme builder, tokens, buttons, cards, form fields, empty/error/loading states, dialogs, settings + about scaffolds | Supabase calls, app-specific widgets, hardcoded colors |
| `forge-core` | Account and data plumbing | Sign-in (Google, Apple), identity linking, account deletion, session state, jsonb repository helper, dirty-flag sync helper | Supabase URL/keys, app schemas, UI styling |
| Each app | Its identity and domain | Seed color, icon, Supabase config, tables, domain screens (e.g. cheese tasting forms) | Copies of shared widgets or auth code |

**Rule of three for promotion.** Code moves into a package only when a second app needs it, ideally after a third confirms its shape. Until then it lives in the app that uses it.

&#91;embedded content: package layering · app, two packages, Supabase\]

Only `forge-core` talks to Supabase, and only the app knows which Supabase project it talks to.

## forge-ui design

`forge-ui` exports one theme builder: an app passes its seed color (and optional accent), and everything else about the brand is fixed inside the package.

```dart
ThemeData forgeTheme({
  required Color seed,
  Color? accent,
  Brightness brightness = Brightness.light,
}) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    textTheme: ForgeType.textTheme,
    filledButtonTheme: ForgeButtons.filled,
    cardTheme: ForgeCards.theme,
    extensions: [ForgeTokens.standard(scheme, accent: accent)],
  );
}
```

| Fixed in forge-ui (the brand) | Set per app |
| --- | --- |
| Typography and type scale | Seed color, optional accent |
| Corner radii, spacing scale, elevation | App icon and name |
| Button, card, input and dialog shapes | At most one signature component |
| Motion durations and curves |  |
| Icon style |  |
| "Made by tkforgeworks" about screen |  |

**Hard rule: shared widgets never hardcode a color.** Every color comes from `Theme.of(context).colorScheme` or the `ForgeTokens` theme extension. One hardcoded color breaks theme swapping for every app.

**Fonts are fixed and bundled in forge-ui.** Apps don't override them.

- The .ttf/.otf files live in `forge-ui/assets/fonts/` and are declared under `fonts:` in forge-ui's `pubspec.yaml`. Apps get them through the dependency, with no copying.
- No runtime font download through `google_fonts`. A download is an undisclosed network call to Google and fails offline.
- Only SIL Open Font License (OFL) fonts. `OFL.txt` ships beside the files, is listed in `NOTICE`, and is registered with `LicenseRegistry` so it shows on each app's licenses page.
- No commercial fonts unless their license explicitly covers app embedding. Modified OFL fonts get a new name.

v1 widget set:

- Sign-in screen with Google and Apple buttons (callbacks in, no auth logic)
- Account settings page: linked sign-in methods, sign out, delete account
- Confirmation dialog, including the destructive delete confirmation
- Empty, error and loading states
- Form field styling
- About screen with privacy policy and deletion links

Material 3 is the base. If iOS later needs a more native feel, the platform adjustments go inside `forge-ui`, not in each app.

## forge-core design

`forge-core` wraps Supabase Auth and a small jsonb data layer. Every app offers the same two sign-in buttons on every platform, and one Apple or Google identity always reaches the same account.

### Sign-in flows

| Platform | Google | Apple |
| --- | --- | --- |
| iOS | Native `google_sign_in` → `signInWithIdToken` | Native `sign_in_with_apple` → `signInWithIdToken` |
| Android | Native `google_sign_in` → `signInWithIdToken` | Later: browser tab via `signInWithOAuth(OAuthProvider.apple)` |
| Web (future) | `signInWithOAuth(OAuthProvider.google)` | `signInWithOAuth(OAuthProvider.apple)` |

Apple setup, once per app:

- **Now (iOS native only):** an App ID with Sign in with Apple enabled, and the iOS bundle ID in the Supabase Apple provider's Client IDs.
- **Now, for deletion:** a signing key (.p8) in the Edge Function secrets. On a user's first Apple sign-in, an Edge Function exchanges the authorization code for an Apple refresh token and stores it server-side, so the purge can revoke it later.
- **Later, with Android and web:** a Services ID linked to the same App ID (same developer team) with Supabase's callback URL registered, an OAuth client secret generated from the .p8, and the Services ID listed **first** in Client IDs.

Behaviors the package must handle:

- **Name:** Apple returns it only on the first native sign-in and never through the OAuth flow. Save it when present; otherwise the app asks for an optional display name.
- **Same account across platforms:** Apple's user identifier is stable per developer team across native and web flows, including Hide My Email relay addresses. No extra work beyond the shared team setup.
- **Cross-provider linking:** Apple (hidden email) and Google never match by email. Account settings expose "Link another sign-in method" using Supabase `linkIdentity`.

### Account deletion

One `deleteAccount()` call does all of it:

1. Set `accounts.deletion_requested_at`, sign out every session, and stop serving the account's data.
2. A purge Edge Function (service role key, retried until it succeeds) revokes the Apple token, then deletes the Supabase auth user.
3. The `accounts` row and all `entries` rows go with it through `on delete cascade`.
4. The app clears local storage on the device.

No anonymized copies are kept. Entries are private and their free text can itself hold personal details, so deletion removes them. If usage stats are ever wanted, keep an aggregate counter with no content and no user link. The privacy policy states the purge window.

**Web deletion requests.** Each app has its own page at `tkforgeworks.com/policy/<app>/delete-account` (the Google Play deletion URL), linked from that app's privacy policy at `policy/<app>`. The page names the app as it appears on the store listing, lists what gets deleted and the purge window, and hosts a request form that feeds the same purge pipeline:

1. The form takes the account email, protected by a bot check and rate limiting.
2. A request Edge Function emails a single-use confirmation link (Resend) if that email matches an account. The response is identical either way, so the form can't be used to discover accounts.
3. Clicking the link sets `accounts.deletion_requested_at`, and the standard purge runs from there.

Apple sign-in users may only know their relay address, so the page explains that, and the sending domain is registered with Apple's private email relay so confirmation emails get through.

The purge Edge Function and the `accounts` migration live in `forge-core` under `supabase/`. A sync script in `forge-core` copies them into an app's `supabase/` folder at the app's pinned tag, and the app deploys them with the Supabase CLI. App CI fails if the copies drift from the pinned version, so no app can quietly change the deletion policy.

### Data model

One generic table shape per app, scoped by row-level security:

```sql
create table entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  kind text not null,
  data jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table entries enable row level security;
create policy "own rows" on entries
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

Every app also gets an `accounts` table, one row per user:

```sql
create table accounts (
  id uuid primary key references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  deletion_requested_at timestamptz
);
```

`deletion_requested_at` marks an account as pending deletion so a failed purge can be retried; it never keeps a deleted account around.

**Cascade rule.** Every table holding user-owned rows declares `user_id uuid not null references auth.users on delete cascade`. Postgres's default (no action) would block the purge instead of deleting the rows. Files in Supabase Storage are not rows, so the purge function deletes them explicitly before removing the auth user.

- `forge-core` ships a typed repository helper over this shape (`kind` + a `fromJson`/`toJson` pair per type).
- Fields move from `data` into real columns only when an app needs to query or index them.
- Optional sync helper for local-first apps: mark rows dirty locally, push on demand, verify by per-user key lookup (the pattern the cheese app uses with Drift).
- Each app owns its Supabase project, migrations and table names; `forge-core` takes the client as a parameter.

## Privacy and store compliance

Apps built on the packages collect only what sign-in and the app's own data need, so every app starts from the same four-row data inventory and adds rows only for what it adds.

| Data | Purpose | Apple privacy label | Google Play Data safety |
| --- | --- | --- | --- |
| Email (may be an Apple relay address) | Account | Contact Info → Email Address | Personal info → Email address |
| Name (optional) | Display | Contact Info → Name | Personal info → Name |
| Account ID | Authentication | Identifiers → User ID | Personal info → User IDs |
| User entries | App functionality | User Content → Other User Content | App activity → Other user-generated content |

Declared for every row: linked to the user, not used for tracking, encrypted in transit, deletable on request.

Requirements every app meets before release:

- [ ] Google and Apple sign-in both offered on iOS (Apple guideline 4.8)
- [ ] In-app account deletion via `forge-core`
- [ ] Deletion page and request form at tkforgeworks.com/policy/\<app>/delete-account (Google Play)
- [ ] Privacy policy at tkforgeworks.com/policy/\<app>, naming Supabase as the data processor and its hosting region
- [ ] Data inventory kept in the app repo (for example `PRIVACY.md`) and updated before any new SDK or field ships
- [ ] No analytics or crash-reporting SDKs unless added to the inventory first
- [ ] Server functions never log the contents of `data`

`forge-core` ships a privacy policy template and the base inventory so each app only fills in its own rows.

## Repos, versioning and distribution

Each package lives in its own repo (`tkforgeworks/forge-ui`, `tkforgeworks/forge-core`) and apps consume it as a git dependency pinned to a release tag.

```yaml
dependencies:
  forge_ui:
    git:
      url: https://github.com/tkforgeworks/forge-ui.git
      ref: v0.1.0
```

- **Semantic version tags.** Bumping an app's tag is the only way it picks up brand changes.
- **Additive changes.** New parameters get defaults, so an app can move to a newer tag without touching its screens. Breaking changes bump the major version and come with a migration note.
- **Showcase app in the `forge-ui` repo.** It renders every component in light and dark with two or three seed colors. Run it before tagging; it also serves as reference for Claude Code when building new screens.
- **Tests.** Widget golden tests for the showcase; unit tests for `forge-core` with a mocked Supabase client.

**Visibility: public.** Both repos are public so open-source apps and outside contributors can build against them. Neither package holds secrets; keys live in each app's config.

Licensing follows the tkforgeworks org standards:

- A `LICENSE` and `NOTICE` in each repo, with the license field set in `pubspec.yaml`.
- `NOTICE` lists bundled third-party assets, starting with the fonts (SIL OFL, with `OFL.txt` shipped beside the files and registered in `LicenseRegistry`).
- Third-party dependencies stay on licenses compatible with the package license; check before adding one.
- Contributions are accepted under the repo's license via the org's contributing guidelines.

## Operational concerns

The Supabase free-tier pause is the one item that can quietly break a released app today. The Apple client secret joins it once Apple sign-in reaches Android or web.

**Apple client secret.** Not needed while Apple sign-in is iOS-native only: the purge function signs a short-lived client secret from the .p8 for each revocation, so nothing expires. The Android and web OAuth flow needs a stored secret that Apple caps at about 6 months. If it lapses, Apple sign-in fails on Android and web while iOS keeps working.

- Ship a rotation job (GitHub Action or homelab CI, every 5 months) together with Android Apple sign-in.
- Keep the .p8 only in CI and Edge Function secret stores; revoke and replace it if it is ever exposed.

**Supabase free tier.** As of September 2026 the free plan allows 2 active projects per organization, and free projects pause after 7 days of inactivity.

- The cheese app already uses one of the two slots.
- Fine for development; a pause in production blocks sign-in and sync until reactivated.
- Local-first apps (Drift as the working store) degrade gracefully: the app works, sync waits.
- Move to Pro ($25 per organization per month, no inactivity pause) when the first app has real users. One Pro organization covers all apps.

Sources: [Supabase: Login with Apple](https://supabase.com/docs/guides/auth/social-login/auth-apple) · [Supabase pricing review, Sept 2026](https://www.jetadmin.io/blog/supabase-review/) · [Google Play: account deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111)

## Milestones

Work runs in five steps, with the cheese app as the first real consumer before any new app starts.

1. **Repo setup.** Create both repos, run the org standards check, add CI and the empty showcase app.
2. **forge-ui v0.1.** Theme builder, tokens, base components, showcase in light and dark with three seeds.
3. **forge-core v0.1.** Native Google and Apple sign-in on iOS, Google native on Android (Apple on Android comes later), session state, jsonb repository helper.
4. **Account and privacy v0.2.** Identity linking, deletion Edge Function with Apple revocation, privacy policy template, base data inventory, web deletion page and request form.
5. **Adopt.** Move the cheese app onto both packages before its first store release (its photo storage stays app-side for now), fix what that exposes, tag v1.0, then start the new app on v1.0.

Later, outside these milestones: Apple sign-in on Android and web, shipped together with the client secret rotation job.

## Decisions

All review decisions are settled and reflected in the sections above.

| Topic | Decision | Applies in |
| --- | --- | --- |
| Repo visibility | Public, relying on open-source licenses and future contributors | Repos, versioning and distribution |
| Naming | Repos hyphenated (`forge-ui`, `forge-core`); Dart packages underscored (`forge_ui`, `forge_core`) | Repos, versioning and distribution |
| Fonts | Fixed and bundled in `forge-ui` (OFL only); apps don't override | forge-ui design |
| Apple sign-in on Android | Deferred; iOS native first | forge-core design |
| Deletion logic | Lives in `forge-core`, synced into each app at its pinned tag | Account deletion |
| Deleted data | Fully removed; no anonymized retention | Account deletion |
| Policy pages | `tkforgeworks.com/policy/<app>` for the privacy policy; `policy/<app>/delete-account` as its own page with a request form | Account deletion, Privacy |
| Cheese app | Adopts both packages before its first store release | Milestones |

Still open: the seed color for each existing app. It doesn't block forge-ui v0.1, since the showcase uses sample seeds.
