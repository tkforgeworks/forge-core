# Auth email templates

The four mails Supabase Auth sends for an app on `forge_core`, written in
the tkforgeworks voice and styled inline (email clients ignore stylesheets).
Each button links to `{{ .RedirectTo }}?token_hash={{ .TokenHash }}&type=…`
(FC-13): the app's redirect URL (what it sent as `redirect_to`, which must
be an `https` App Link on the allow list) with the verification token, so
the tap opens the app directly and `forge_core` verifies the token;
nothing goes through GoTrue's `/verify` redirect, whose browser tab stayed
behind in mail clients. `type` is Supabase's verification type for the
template (`signup`, `recovery`, `email_change`, `magiclink`).
`{{ .SiteURL }}` is the project's Site URL, shown as a small header. No
images, so nothing loads from anywhere.

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
