// Adventist Super App — transactional auth email templates.
//
// One layout, four emails (confirm signup, reset password, sign-in code,
// email change). Run `node docs/email-templates/build.js` to regenerate the
// .html files next to this script; pass a Supabase access token as
// SUPABASE_ACCESS_TOKEN to also PATCH them into the live project.
//
// ## Why the HTML looks like it's from 2004
//
// Email clients are not browsers. Gmail strips <style> blocks in some
// contexts, Outlook renders through Word's engine, and flexbox/grid do not
// exist in either. So: nested tables, inline styles, no external CSS and no
// web fonts.
//
// ## The logo
//
// A real <img>, served from Supabase Storage. It has to be remote: `data:`
// URIs are stripped by Gmail outright, and SMTP templates cannot carry a CID
// attachment.
//
// The first version of these templates used a drawn "AC" tile instead, on the
// reasoning that blocked images make a code email look like phishing. The
// founder's answer was simply "there is no logo, it says AC" — and they are
// right: Gmail has proxied and shown images BY DEFAULT since 2013, so the
// blocked-image case is now the exception, not the rule.
//
// It is built to survive being blocked anyway. The <img> sits on a navy
// header with the brand name in text beside it, so a client that refuses the
// image still shows a branded, readable email rather than a broken icon in a
// white void — and the alt text carries the name.
//
// 240×240 and 26 KB, resized from the 3264×3264 source: the original is 2 MB,
// which is a rude thing to attach to every verification email on Zimbabwean
// mobile data.
//
// ## Supabase template variables
//   {{ .Token }}            the 6-digit code (what the app asks for)
//   {{ .ConfirmationURL }}  magic link (unused — the app is code-based)
//   {{ .Email }} {{ .SiteURL }}
//
// The app verifies OTP CODES, not links. Every template leads with the code.

const fs = require("fs");
const path = require("path");

const BLUE = "#1565C0";
const NAVY = "#0D1B3E";
const GOLD = "#C8A951";
const BG = "#F5F7FA";
const TEXT = "#1A1A2E";
const MUTED = "#5B6472";
const BORDER = "#E4E9F0";

const FONT =
  "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif";

/// The app icon, resized to 240px and uploaded to the public `library`
/// bucket. Re-upload with the same path to change it — the templates do not
/// need rebuilding, because email clients fetch it fresh each time.
const LOGO_URL =
  "https://eqbyvasteolqyktbqbem.supabase.co/storage/v1/object/public/library/branding/logo-240.png";

/**
 * @param {object} o
 * @param {string} o.preheader  Inbox preview line. Without it clients show
 *                              the first visible text, which is the logo alt.
 * @param {string} o.heading
 * @param {string} o.intro
 * @param {string} o.codeLabel
 * @param {string} o.outro
 * @param {string} o.footnote
 */
function layout(o) {
  return `<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<meta name="x-apple-disable-message-reformatting" />
<title>Adventist Super App</title>
</head>
<body style="margin:0;padding:0;background:${BG};">

<!-- Preheader: shown in the inbox list, hidden in the body. -->
<div style="display:none;font-size:1px;color:${BG};line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;">${o.preheader}</div>

<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${BG};">
<tr><td align="center" style="padding:28px 12px;">

  <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:600px;background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid ${BORDER};">

    <!-- Header. A dark band is the one place navy still belongs (CLAUDE.md
         retires it for in-APP headers, not for dark sections like this). -->
    <tr>
      <td style="background:${NAVY};padding:24px 28px;">
        <table role="presentation" cellpadding="0" cellspacing="0" border="0">
          <tr>
            <td style="width:48px;vertical-align:middle;">
              <img src="${LOGO_URL}" width="48" height="48" alt="Adventist Super App"
                   style="display:block;width:48px;height:48px;border:0;outline:none;text-decoration:none;border-radius:12px;" />
            </td>
            <td style="padding-left:14px;font-family:${FONT};">
              <div style="font-size:17px;font-weight:bold;color:#ffffff;line-height:1.3;">Adventist Super App</div>
              <div style="font-size:11px;color:${GOLD};letter-spacing:1.4px;text-transform:uppercase;padding-top:2px;">Faith &bull; Community &bull; Worldwide</div>
            </td>
          </tr>
        </table>
      </td>
    </tr>
    <tr><td style="height:3px;background:${GOLD};font-size:0;line-height:0;">&nbsp;</td></tr>

    <!-- Body -->
    <tr>
      <td style="padding:32px 28px 8px 28px;font-family:${FONT};">
        <h1 style="margin:0 0 10px 0;font-size:22px;line-height:1.3;font-weight:bold;color:${TEXT};">${o.heading}</h1>
        <p style="margin:0 0 22px 0;font-size:15px;line-height:1.6;color:${MUTED};">${o.intro}</p>
      </td>
    </tr>

    <!-- The code. The whole reason the email exists, so it gets the weight. -->
    <tr>
      <td style="padding:0 28px;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:${BG};border:1px solid ${BORDER};border-radius:14px;">
          <tr>
            <td align="center" style="padding:22px 16px;font-family:${FONT};">
              <div style="font-size:11px;font-weight:bold;letter-spacing:1.6px;text-transform:uppercase;color:${MUTED};padding-bottom:10px;">${o.codeLabel}</div>
              <div style="font-size:34px;font-weight:bold;letter-spacing:9px;color:${BLUE};line-height:1.2;">{{ .Token }}</div>
              <div style="font-size:12px;color:${MUTED};padding-top:10px;">Expires in 1 hour</div>
            </td>
          </tr>
        </table>
      </td>
    </tr>

    <tr>
      <td style="padding:22px 28px 0 28px;font-family:${FONT};">
        <p style="margin:0 0 20px 0;font-size:14px;line-height:1.6;color:${MUTED};">${o.outro}</p>
      </td>
    </tr>

    <!-- Security note -->
    <tr>
      <td style="padding:0 28px 28px 28px;font-family:${FONT};">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-top:1px solid ${BORDER};">
          <tr>
            <td style="padding-top:18px;font-size:13px;line-height:1.6;color:${MUTED};">
              ${o.footnote}
            </td>
          </tr>
        </table>
      </td>
    </tr>

    <!-- Footer -->
    <tr>
      <td style="background:${BG};padding:20px 28px;font-family:${FONT};border-top:1px solid ${BORDER};">
        <div style="font-size:12px;line-height:1.6;color:${MUTED};">
          Adventist Super App &mdash; a home for Seventh-day Adventists worldwide.
        </div>
        <div style="font-size:11px;line-height:1.6;color:#8A93A2;padding-top:6px;">
          This is an automated message, so replies are not monitored. Never share this code with anyone &mdash; not even someone claiming to be from Adventist Super App.
        </div>
      </td>
    </tr>

  </table>

</td></tr>
</table>
</body>
</html>`;
}

const TEMPLATES = {
  confirmation: {
    subject: "Your Adventist Super App verification code",
    html: layout({
      preheader: "Your 6-digit code to finish creating your account.",
      heading: "Welcome to Adventist Super App",
      intro:
        "You're one step from joining the community. Enter this code in the app to verify your email address.",
      codeLabel: "Verification code",
      outro:
        "Once you're in you can follow your church, join the conversation, read the Bible and Sabbath School lessons offline, and connect with Adventists around the globe.",
      footnote:
        "If you didn't create an Adventist Super App account, you can safely ignore this email &mdash; nothing has been set up.",
    }),
  },
  recovery: {
    subject: "Your Adventist Super App password reset code",
    html: layout({
      preheader: "Your 6-digit code to reset your password.",
      heading: "Reset your password",
      intro:
        "We received a request to reset the password for your Adventist Super App account. Enter this code in the app to choose a new one.",
      codeLabel: "Password reset code",
      outro:
        "For your security this code can only be used once, and only on the device that asked for it.",
      footnote:
        "If you didn't ask to reset your password, ignore this email &mdash; your password has not been changed and your account is safe.",
    }),
  },
  magic_link: {
    subject: "Your Adventist Super App sign-in code",
    html: layout({
      preheader: "Your 6-digit code to sign in.",
      heading: "Sign in to Adventist Super App",
      intro: "Enter this code in the app to sign in to your account.",
      codeLabel: "Sign-in code",
      outro:
        "For your security this code can only be used once and expires shortly.",
      footnote:
        "If you didn't try to sign in, ignore this email and consider changing your password &mdash; someone may know your email address.",
    }),
  },
  email_change: {
    subject: "Confirm your new Adventist Super App email",
    html: layout({
      preheader: "Your 6-digit code to confirm your new email address.",
      heading: "Confirm your new email",
      intro:
        "Enter this code in the app to confirm {{ .Email }} as the email address for your Adventist Super App account.",
      codeLabel: "Confirmation code",
      outro:
        "Until you confirm, your account keeps using its previous email address.",
      footnote:
        "If you didn't ask to change your email, ignore this message and change your password &mdash; someone else may have access to your account.",
    }),
  },
};

// ---- write files -----------------------------------------------------------

for (const [name, t] of Object.entries(TEMPLATES)) {
  fs.writeFileSync(path.join(__dirname, `${name}.html`), t.html, "utf8");
}
console.log(`Wrote ${Object.keys(TEMPLATES).length} templates.`);

// ---- optionally push to Supabase -------------------------------------------

const token = process.env.SUPABASE_ACCESS_TOKEN;
const ref = process.env.SUPABASE_PROJECT_REF || "eqbyvasteolqyktbqbem";
if (!token) {
  console.log("No SUPABASE_ACCESS_TOKEN set — files written, nothing pushed.");
  process.exit(0);
}

const body = {};
for (const [name, t] of Object.entries(TEMPLATES)) {
  body[`mailer_templates_${name}_content`] = t.html;
  body[`mailer_subjects_${name}`] = t.subject;
}

fetch(`https://api.supabase.com/v1/projects/${ref}/config/auth`, {
  method: "PATCH",
  headers: {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify(body),
})
  .then(async (res) => {
    const text = await res.text();
    if (!res.ok) {
      console.error(`FAILED ${res.status}: ${text.slice(0, 400)}`);
      process.exit(1);
    }
    console.log("Pushed templates + subjects to Supabase.");
  })
  .catch((e) => {
    console.error("Request failed:", e.message);
    process.exit(1);
  });
