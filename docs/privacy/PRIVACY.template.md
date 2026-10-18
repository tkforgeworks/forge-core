# {{APP}} data inventory

What {{APP}} collects, why, and how each store form wants it declared. Keep
this file in the app repo as `PRIVACY.md`, update it **before** any new SDK
or field ships, and keep the privacy policy and the Play Data safety form in
step with it. Rows marked *forge_core* come with the shared packages and
are the same in every tkforgeworks app; add your app's own rows below them.

## Accounts and sync (forge_core)

Collected only once the user signs in. Without an account nothing leaves
the device.

| Data | Purpose | Google Play Data safety | Apple privacy label (when iOS ships) | Retained |
| --- | --- | --- | --- | --- |
| Email address | Account identity; sign-in and reset mail | Personal info → Email address | Contact Info → Email Address | Until the account is deleted |
| Username (optional, user-entered) | Display | Personal info → Name | Contact Info → Name | Until the account is deleted |
| Account ID (Supabase user id) | Authentication, linking data to the account | Personal info → User IDs | Identifiers → User ID | Until the account is deleted |
| Google account identity (if linked) | Sign-in | Personal info → User IDs | Identifiers → User ID | Until unlinked or deleted |
| {{USER_DATA}} (the app's entries) | App functionality: backup and sync between the user's devices | App activity → Other user-generated content | User Content → Other User Content | Until deleted in the app or with the account |

Declared for every row: **linked to the user**, **not used for tracking**,
**encrypted in transit**, **deletable on request** (in-app and at
`https://tkforgeworks.com/privacy/{{APP_SLUG}}/delete-account/`). Processors:
[Supabase](https://supabase.com/privacy) (database, authentication, hosted
in {{REGION}}), [Resend](https://resend.com/legal/privacy-policy)
(sign-in and deletion emails). Deleted data is purged within
{{PURGE_WINDOW}}; nothing is kept, anonymised or otherwise.

## Feedback relay (only apps with the in-app form)

| Data | Purpose | Google Play Data safety | Retained |
| --- | --- | --- | --- |
| Feedback topic, rating, comments; reply email if given; app version, Android version, device model | Support | Personal info → Other info (email if given); App info and performance → Other | In the support inbox while useful; deleted on request |

Sent only when the user taps Send; relayed by a Cloudflare Pages Function
at tkforgeworks.com to the support inbox through Resend. Not linked to the
account.

## {{APP}}'s own rows

| Data | Purpose | Google Play Data safety | Retained |
| --- | --- | --- | --- |
| *(add rows here; delete the section if there are none)* | | | |

## Not collected

No analytics, advertising, crash-reporting or tracking SDKs. No location,
contacts, photos (unless listed above), or device identifiers beyond what
Android itself reports to Google Play.

## Store compliance checklist (before any build with sign-in reaches testers)

- [ ] Google and email/password sign-in on Android (Google **and** Apple on iOS when an iOS app exists)
- [ ] In-app account deletion in the same build as sign-in
- [ ] Deletion page and form live at `tkforgeworks.com/privacy/{{APP_SLUG}}/delete-account/`; URL entered in Play Console (App content → Account deletion) and in Data safety
- [ ] Privacy policy live at `tkforgeworks.com/privacy/{{APP_SLUG}}/`, naming Supabase and its region, Resend, the purge window and both deletion paths
- [ ] This inventory current; Data safety form re-submitted
- [ ] Play App access: a reviewer account (email/password test account, or a Google account without 2FA while the consent screen is in Testing)
- [ ] Google Cloud consent screen flipped from Testing to In production
- [ ] Supabase Auth email templates, SMTP and rate limits set; Resend sender verified
- [ ] Server functions never log `data`; Edge Function logs carry ids only
