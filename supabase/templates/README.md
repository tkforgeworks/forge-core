# Auth email templates

The four mails Supabase Auth sends for an app on `forge_core`, written in
the tkforgeworks voice and styled inline (email clients ignore stylesheets).
`{{ .ConfirmationURL }}` is the link Supabase builds, including the app's
`redirect_to`; `{{ .SiteURL }}` is the project's Site URL, shown as a
small header. No images, so nothing loads from anywhere.

| File | Supabase template | Sent by |
| --- | --- | --- |
| `confirmation.html` | Confirm signup | `signUpWithEmail`, `resendConfirmation` |
| `recovery.html` | Reset password | `sendPasswordReset` |
| `email_change.html` | Change email address | a later email-change feature |
| `magic_link.html` | Magic link | unused by forge_core; kept branded in case the dashboard sends one |

Install: Supabase dashboard → Authentication → Email Templates → paste each
body and set the subject ("Confirm your email", "Set a new password",
"Confirm your new email", "Your sign-in link"). `supabase/config.toml` can
carry them for CLI-managed projects later; until then the dashboard is the
source of truth and this folder the copy to paste.
