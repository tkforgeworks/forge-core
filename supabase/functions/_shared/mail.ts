// forge_core: the branded transactional mail the Edge Functions send through
// Resend. Inline styles only; no images.
export interface MailOptions {
  to: string;
  subject: string;
  heading: string;
  body: string;
  buttonLabel: string;
  buttonUrl: string;
  footnote: string;
  siteLabel: string;
}

export function renderMail(o: MailOptions): { html: string; text: string } {
  const esc = (s: string) =>
    s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const html = `<!doctype html>
<html lang="en">
  <body style="margin:0;padding:32px 16px;background:#faf6ee;font-family:Helvetica,Arial,sans-serif;color:#35291a;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;margin:0 auto;background:#fffdf8;border:1px solid #e6d9bf;border-radius:12px;">
      <tr><td style="padding:28px 28px 8px;font-size:12px;letter-spacing:.14em;text-transform:uppercase;color:#8a7a5f;">${esc(o.siteLabel)}</td></tr>
      <tr><td style="padding:0 28px;font-size:22px;font-weight:600;">${esc(o.heading)}</td></tr>
      <tr><td style="padding:12px 28px 0;font-size:15px;line-height:1.55;">${esc(o.body)}</td></tr>
      <tr><td style="padding:24px 28px;">
        <a href="${o.buttonUrl}" style="display:inline-block;padding:12px 22px;border-radius:8px;background:#b3641b;color:#ffffff;text-decoration:none;font-weight:600;">${esc(o.buttonLabel)}</a>
      </td></tr>
      <tr><td style="padding:0 28px 28px;font-size:13px;line-height:1.5;color:#8a7a5f;">${esc(o.footnote)}</td></tr>
    </table>
  </body>
</html>`;
  const text = `${o.heading}\n\n${o.body}\n\n${o.buttonLabel}: ${o.buttonUrl}\n\n${o.footnote}\n`;
  return { html, text };
}

/// Sends through Resend. Throws on a non-2xx so the caller can log it; the
/// caller never reveals the outcome to the requester.
export async function sendMail(
  apiKey: string,
  from: string,
  o: MailOptions,
): Promise<void> {
  const { html, text } = renderMail(o);
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      authorization: `Bearer ${apiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ from, to: [o.to], subject: o.subject, html, text }),
  });
  if (!res.ok) {
    throw new Error(`Resend ${res.status}: ${(await res.text()).slice(0, 200)}`);
  }
}

export function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
