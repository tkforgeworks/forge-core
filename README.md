# forge-core

Shared sign-in, account and data plumbing for tkforgeworks Flutter apps,
built on Supabase. The Dart package is `forge_core`; its sibling
[`forge-ui`](https://github.com/tkforgeworks/forge-ui) carries the brand look.
Apps depend on both, and the two packages never depend on each other.

**Status: pre-release.** The repo holds the spec and an empty package
skeleton. Nothing is usable yet.

## What it will own

- Google and Apple sign-in, session state and identity linking
- In-app account deletion, including the server-side purge
- A typed repository helper over a generic jsonb `entries` table

It never contains Supabase URLs or keys, app schemas, or UI styling: each app
passes in its own Supabase client.

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
