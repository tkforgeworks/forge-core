# Email sign-in: Supabase and app setup

What an app on `forge_core` needs before `signUpWithEmail`,
`signInWithEmail`, `sendPasswordReset` and `updatePassword` work end to end.

## Supabase

1. **Custom SMTP through Resend** (Authentication → SMTP Settings). The
   built-in mailer is capped at a few messages an hour and sends from a
   shared domain. Host `smtp.resend.com`, port 465, username `resend`,
   password a Resend API key with sending permission, sender on the org
   domain (for example `accounts@tkforgeworks.com`, name the app). Then
   Authentication → Rate Limits: raise emails per hour (30 is plenty for a
   closed test).
2. **Email provider** (Authentication → Providers → Email): on, **Confirm
   email** on, minimum password length 8, leaked-password protection on
   (Pro).
3. **URL configuration**: Site URL = the app's privacy policy page (what a
   template link falls back to when no `redirect_to` is sent); the app's
   redirect URL in the redirect allow list, exactly as the app sends it
   (an App Link such as `https://<site>/apps/<app>/auth/`, trailing slash
   included, or the custom scheme `<applicationId>://auth-callback`; see
   "App" below).
4. **Templates**: paste `supabase/templates/*.html` into Authentication →
   Email Templates (see that folder's README for subjects).

## App

Two kinds of redirect work. **Prefer an HTTPS Android App Link** on a site
you control (cheesy-scribe moved to one in its 0.3.0 RCs): GoTrue answers
the mail link with a 303 to it, Android hands that straight to the app
with nothing left behind in the mail client's browser, and anyone without
the app lands on a real page. A custom scheme also works, but GoTrue's 303
body (a bare "See Other" line) stays on screen in the mail client after the
app opens, and a phone without the app shows an error.

### App Link (preferred)

- The site serves `/.well-known/assetlinks.json` (plain JSON, no redirect)
  naming the application id and the SHA-256 fingerprints of every
  certificate that signs shipped builds: the Play app-signing key *and* the
  upload key (Play Console → Test and release → App integrity; public
  values). A landing page at the callback path explains the link and points
  to the store, tolerating whatever GoTrue appends (`?code=…` or
  `#error=…`). The TKForgeWorks website README ("App Links") has the
  template.
- Pass the URL to the config, trailing slash included if the page has one:
  `ForgeSupabaseConfig.fromEnvironment(authRedirectUrl:
  'https://<site>/apps/<app>/auth/')`, and put the same string in the
  allow list.
- Declare it in `android/app/src/main/AndroidManifest.xml`, inside the main
  `<activity>`, with `autoVerify` so Android checks the statement file at
  install:

  ```xml
  <intent-filter android:autoVerify="true">
      <action android:name="android.intent.action.VIEW"/>
      <category android:name="android.intent.category.DEFAULT"/>
      <category android:name="android.intent.category.BROWSABLE"/>
      <data android:scheme="https" android:host="<site>"
            android:pathPrefix="/apps/<app>/auth"/>
  </intent-filter>
  ```

- Builds signed with a key that is not in `assetlinks.json` (CI's
  debug-signed fallbacks, local debug builds) do not verify, so there the
  link opens the landing page instead. Expected; the page's `intent:` link
  still reaches the app by package name.
- A go_router app receives the link as a platform route carrying the whole
  URI, with the trailing slash dropped; a top-level `redirect` that matches
  scheme, host and path prefix sends it to the account screen.
  `supabase_flutter` reads the code from the same link on its own.

### Custom scheme

- Pass the scheme to the config:
  `ForgeSupabaseConfig.fromEnvironment(authRedirectUrl:
  'com.example.app://auth-callback')`. `forge_core` sends it as
  `redirect_to` on sign-up, resend and reset, so the links in those mails
  open the app.
- **The scheme must be a valid URL scheme**: letters, digits, `+`, `-` and
  `.` only. An application id with an underscore (`com.example.my_app`)
  cannot be used as is; drop the underscore
  (`com.example.myapp://auth-callback`) and use that same string in the
  manifest and the allow list. GoTrue validates `redirect_to` with Go's URL
  parser before it consults the allow list, so an unparsable scheme is
  silently replaced by the Site URL in every mail, and Dart's `Uri.parse`
  rejects the incoming link as well. `SupabaseForgeAuth` asserts on an
  invalid value (cheesy-scribe hit this on its first RC).
- Declare the scheme in `android/app/src/main/AndroidManifest.xml`, inside
  the main `<activity>`:

  ```xml
  <intent-filter android:autoVerify="false">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="com.example.app" android:host="auth-callback" />
  </intent-filter>
  ```

- `supabase_flutter` handles the incoming link itself (`detectSessionInUri`
  is on by default): a confirmation link signs the user in and `changes`
  emits `signedIn`; a reset link emits `passwordRecovery`, which is the
  app's cue to show its set-password screen and call `updatePassword`.
  Nothing in the app parses the URL.

## Behaviour notes

- **Confirmation required** means `signUpWithEmail` returns
  `ForgeAuthEmailSent` and no session; the session arrives through the
  stream when the link is opened on the same device. Opening it on another
  device signs in there instead, which is fine.
- **Sign-in before confirming** is `ForgeAuthError.emailNotConfirmed`:
  offer "Send again" (`resendConfirmation`), which Supabase rate-limits
  (`rateLimited` if pressed too often).
- **Reset links expire** (an hour by default) and work once:
  `linkExpired` when a stale one is opened; a reset with no session behind
  it is `sessionMissing`.
- **Weak passwords**: the server's reasons are appended to the failure
  message (`"Password is too weak (length, pwned)"`), so the app can show
  them.
- `invalid_credentials` deliberately does not say whether the address or
  the password was wrong; the app's copy should not either.

## Linking sign-in methods

One account, both methods. Supabase links a Google sign-in whose verified
email matches an existing email account by itself. Beyond that:

- `linkGoogle()` attaches the picked Google account to the signed-in user
  (native, `linkIdentityWithIdToken`). It needs **Allow manual linking** on
  under Authentication → Providers; otherwise `misconfigured`. A Google
  account that already belongs to another user is `identityAlreadyLinked`:
  tell the user to sign in with that account instead.
- `setPassword(password)` adds email/password to a Google-only account
  (`updatePassword` under the account page's name).
- `unlinkIdentity(identity)` removes a method; the package refuses the last
  one (`lastSignInMethod`) before any request, and the server refuses when
  removing it would leave the email in conflict.
- After any of these, `changes` emits `userUpdated` with the new identity
  list; the account page re-renders from that.
