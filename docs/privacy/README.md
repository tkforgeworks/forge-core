# Privacy templates

Two files an app on forge_core starts from, so every tkforgeworks app
discloses the shared account and sync data the same way:

- `PRIVACY.template.md` → the app repo's `PRIVACY.md`: the data inventory
  with the Play Data safety and Apple label mappings, processors, retention,
  and the store compliance checklist to tick before a build with sign-in
  reaches testers.
- `policy.template.md` → the website page at `/privacy/<app>/`: the policy
  in the tkforgeworks voice (short version first, plain statements, no
  legalese), with the account, sign-out, deletion and feedback sections
  already written.

Placeholders: `{{APP}}`, `{{APP_SLUG}}` (the URL segment),
`{{ONE_LINE_DESCRIPTION}}`, `{{USER_DATA}}` / `{{USER_DATA_SINGULAR}}`
("tasting notes" / "note"), `{{DEVICE_DATA_BULLETS}}`, `{{SETTINGS_LIST}}`,
`{{REGION}}` ("the United States (us-east-1)"), `{{PURGE_WINDOW}}` ("a few
minutes, and in any case within 24 hours": the purge runs at once and
retries every 15 minutes), `{{DATE}}`. Delete the feedback section when the
app has no form.

The Play deletion URL is `https://tkforgeworks.com/privacy/<app>/delete-account/`;
the policy and the inventory both name it. Supabase is the data processor
(database and auth), Resend the mail processor; the feedback relay adds
Cloudflare.
