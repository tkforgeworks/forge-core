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
   custom scheme `<applicationId>://auth-callback` in the redirect allow
   list.
4. **Templates**: paste `supabase/templates/*.html` into Authentication →
   Email Templates (see that folder's README for subjects).

## App

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
