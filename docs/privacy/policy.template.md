---
title: "{{APP}} Privacy Policy"
app: "{{APP}}"
description: "How the {{APP}} app handles your data: everything stays on your device unless you sign in, and then only what you choose to back up."
lastUpdated: "{{DATE}}"
---

<!--
forge_core privacy policy template. Written in the tkforgeworks voice: plain
statements, the short version first, no legalese. Replace every {{…}},
delete sections that don't apply, keep the structure so every app's policy
reads the same. Lives on the website at /privacy/{{APP_SLUG}}/.
-->

{{APP}} is {{ONE_LINE_DESCRIPTION}} for Android made by TK ForgeWorks LLC
("we", "us"). This policy explains what happens to the information you put
into the app.

The short version: **everything stays on your phone unless you sign in.**
Signing in is optional. If you do, the {{USER_DATA}} you create are backed
up to your account so they follow you to your next phone, and you can delete
the account, and everything in it, whenever you like. We don't sell or share
any of your data, and the app contains no advertising or tracking.

## What the app stores on your device

Everything you enter is saved on your device, in the app's private storage:

- {{DEVICE_DATA_BULLETS}}
- your settings ({{SETTINGS_LIST}})

None of this leaves the device unless you sign in and turn on backup, or
you send us feedback (both below).

## If you sign in

You can sign in with a Google account or with an email address and
password. Either way an account is created for you with
[Supabase](https://supabase.com/privacy), the service that runs our sign-in
and database, hosted in {{REGION}}. The account holds:

- your email address (from Google, or the one you typed)
- a username, if you choose to set one in the app
- a random account ID that links your data to you
- the {{USER_DATA}} you create, which are copied to the account and kept
  in sync between your devices

With an email/password account we send you a confirmation email, and a
reset email if you forget your password. Those go out through
[Resend](https://resend.com/legal/privacy-policy), an email delivery
service, from an @tkforgeworks.com address. If you sign in with Google,
Google's own policy applies to that step
([Google's Privacy Policy](https://policies.google.com/privacy)); we
receive your email address and a Google account identifier, nothing else
from your Google account.

Your data in the account is encrypted in transit, visible only to you (the
database enforces that per row), and used for nothing but showing it back
to you on your devices. We don't read it, analyse it, or share it.

### Signing out and deleting your account

Signing out keeps your {{USER_DATA}} on the phone unless you tick "also
erase this phone". Deleting your account removes everything stored in it on
our side, including every {{USER_DATA_SINGULAR}}, within {{PURGE_WINDOW}}.
Nothing is kept, in anonymised form or otherwise. You can delete from the
app (Account → Delete account) or, if you no longer have the app, at
[tkforgeworks.com/privacy/{{APP_SLUG}}/delete-account](https://tkforgeworks.com/privacy/{{APP_SLUG}}/delete-account/):
enter your address and confirm from the email we send.

## Feedback you send

<!-- Delete this section if the app has no feedback form. -->

The About screen has a **Send feedback** form. Nothing is sent unless you
fill it in and tap **Send**. When you do, the app sends:

- what the feedback is about
- the rating you pick, if you pick one
- the comments you write
- your email address, only if you enter one so we can reply
- the app's version, your Android version and your phone's model, shown on
  the form before you send

It does not send your {{USER_DATA}} or anything from your account. The
form goes over an encrypted (HTTPS) connection to our server at
tkforgeworks.com, which runs on
[Cloudflare](https://www.cloudflare.com/privacypolicy/), and is emailed to
our support inbox through Resend. Both process it only to deliver it to us.
As part of handling any web request, Cloudflare also sees your IP address,
which we don't store. We keep feedback in our support inbox for as long as
it's useful and never sell or share it.

## Things outside the app

- **Google Play.** When you install the app from Google Play, Google handles
  the download under [Google's Privacy Policy](https://policies.google.com/privacy).
  Google gives developers anonymous, aggregated statistics such as install
  counts and crash rates. We can't use those to identify you.
- **Device backup.** If Android backup is turned on for your Google account,
  Android may include the app's data in your device backup. That backup is
  stored and managed by Google in your account; we can't access it.
- **Links.** The About screen links to [tkforgeworks.com](https://tkforgeworks.com)
  and this policy. Tapping a link opens it in your browser, outside the app.

## Deleting your data

Without an account: delete {{USER_DATA}} in the app, or remove everything
by clearing the app's storage in Android settings or uninstalling. Nothing
of it exists on our side.

With an account: delete your account as described above; that removes
everything we hold for you within {{PURGE_WINDOW}}.

Feedback: email [support@tkforgeworks.com](mailto:support@tkforgeworks.com)
and tell us roughly when you sent it (and the address, if you gave one).

## Children

{{APP}} isn't directed at children under 13 and doesn't knowingly collect
personal information from them. If we learn that an account or feedback
belongs to a child under 13 we'll delete it.

## Changes to this policy

If the app starts handling data differently, we'll update this page and the
"Last updated" date before that version is released.

## Contact

Questions about this policy: [info@tkforgeworks.com](mailto:info@tkforgeworks.com).

By mail:

TK ForgeWorks LLC
971 US Highway 202 N, Ste N #4605
Branchburg, NJ 08876
