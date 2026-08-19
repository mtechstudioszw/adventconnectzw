<#
.SYNOPSIS
  Sends a one-off HTML announcement to Adventist Super App members.

.DESCRIPTION
  Built for the rebrand announcement, but it will send any HTML file.

  DEFAULTS TO A DRY RUN. Nothing leaves the machine until you pass -Send.
  That is deliberate: this talks to every member you have, once, and there
  is no recall. A script whose default action is "email 213 people" is one
  fat-fingered Enter away from a mistake you cannot undo.

  Credentials are PROMPTED, never stored and never passed as plain
  arguments — arguments land in your shell history, and both of these are
  live keys.

.PARAMETER Send
  Actually send. Without it you get a dry run: the real recipient list,
  the real count, and nothing delivered.

.PARAMETER TemplatePath
  HTML file to send. Defaults to the rebrand announcement.

.PARAMETER TestTo
  Send one copy to this address and stop. ALWAYS do this first — see
  yourself what 213 people are about to see.

.PARAMETER DelaySeconds
  Pause between messages. Default 2s. Gmail tolerates roughly 500/day for
  a normal account; the pause is about not looking like a burst of spam,
  not about the daily cap.

.EXAMPLE
  # 1. Look at the list without sending anything
  .\send_announcement_email.ps1

.EXAMPLE
  # 2. Send yourself one copy and inspect it on a real phone
  .\send_announcement_email.ps1 -Send -TestTo you@gmail.com

.EXAMPLE
  # 3. Send for real
  .\send_announcement_email.ps1 -Send

.NOTES
  Gmail needs an APP PASSWORD, not your account password: Google Account →
  Security → 2-Step Verification → App passwords. A normal password is
  rejected by SMTP.

  Resumable. Every successful send is appended to a log beside this
  script; re-running skips anyone already in it. So if this dies at
  recipient 140, run it again and it picks up at 141 rather than mailing
  the first 140 a second time.
#>

[CmdletBinding()]
param(
  [switch]$Send,
  [string]$TemplatePath = "$PSScriptRoot\..\docs\email-templates\announcement-rebrand.html",
  [string]$Subject = "We are now Adventist Super App",
  [string]$TestTo,
  [int]$DelaySeconds = 2,
  [string]$ProjectRef = "eqbyvasteolqyktbqbem",
  [string]$SentLog = "$PSScriptRoot\.announcement-sent.log"
)

$ErrorActionPreference = 'Stop'

# ── Template ──────────────────────────────────────────────────────────
if (-not (Test-Path $TemplatePath)) { throw "Template not found: $TemplatePath" }
$html = [System.IO.File]::ReadAllText($TemplatePath, [System.Text.Encoding]::UTF8)
Write-Host "Template : $TemplatePath ($($html.Length) bytes)" -ForegroundColor Cyan
Write-Host "Subject  : $Subject" -ForegroundColor Cyan

# ── Recipients ────────────────────────────────────────────────────────
# CONFIRMED accounts only. Unconfirmed users never finished signing up:
# they cannot use the app, and mailing addresses that never proved they
# wanted to hear from you is the quickest route to a spam complaint —
# which costs the deliverability of every future email, including the
# password resets people actually need.
Write-Host "`nPaste the Supabase SERVICE ROLE key (input hidden):" -ForegroundColor Yellow
$svcSecure = Read-Host -AsSecureString
$svc = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
         [Runtime.InteropServices.Marshal]::SecureStringToBSTR($svcSecure))

$sql = @"
SELECT email
  FROM auth.users
 WHERE email IS NOT NULL AND email <> ''
   AND email_confirmed_at IS NOT NULL
   AND deleted_at IS NULL
 ORDER BY email;
"@

$resp = Invoke-RestMethod `
  -Uri "https://$ProjectRef.supabase.co/rest/v1/rpc/exec_sql" `
  -Headers @{ apikey = $svc; Authorization = "Bearer $svc" } `
  -Method Post -ContentType 'application/json' `
  -Body (@{ query = $sql } | ConvertTo-Json -Compress) `
  -ErrorAction SilentlyContinue

if (-not $resp) {
  # No exec_sql RPC on this project — fall back to the Auth admin API,
  # which every project has.
  Write-Host "Falling back to the Auth admin API..." -ForegroundColor DarkGray
  $recipients = @()
  $page = 1
  while ($true) {
    $u = Invoke-RestMethod `
      -Uri "https://$ProjectRef.supabase.co/auth/v1/admin/users?page=$page&per_page=200" `
      -Headers @{ apikey = $svc; Authorization = "Bearer $svc" } -Method Get
    if (-not $u.users -or $u.users.Count -eq 0) { break }
    $recipients += $u.users |
      Where-Object { $_.email -and $_.email_confirmed_at } |
      ForEach-Object { $_.email }
    $page++
  }
} else {
  $recipients = $resp | ForEach-Object { $_.email }
}

$recipients = $recipients | Sort-Object -Unique

# Skip anyone already mailed by a previous run.
$already = @()
if (Test-Path $SentLog) { $already = Get-Content $SentLog | Where-Object { $_ } }
$pending = $recipients | Where-Object { $already -notcontains $_ }

Write-Host "`nConfirmed recipients : $($recipients.Count)" -ForegroundColor Green
Write-Host "Already sent         : $($already.Count)" -ForegroundColor DarkGray
Write-Host "Pending this run     : $($pending.Count)" -ForegroundColor Green

if ($TestTo) {
  $pending = @($TestTo)
  Write-Host "`nTEST MODE — sending ONE copy to $TestTo only." -ForegroundColor Yellow
}

if (-not $Send) {
  Write-Host "`nDRY RUN — nothing sent. Re-run with -Send to deliver." -ForegroundColor Yellow
  Write-Host "First 5 recipients:" -ForegroundColor DarkGray
  $pending | Select-Object -First 5 | ForEach-Object { "  $_" }
  return
}

if ($pending.Count -eq 0) { Write-Host "`nNothing to send." -ForegroundColor Green; return }

# ── SMTP ──────────────────────────────────────────────────────────────
Write-Host "`nGmail APP PASSWORD for adventconnectzw@gmail.com (input hidden):" -ForegroundColor Yellow
$pwSecure = Read-Host -AsSecureString
$cred = New-Object System.Net.NetworkCredential("adventconnectzw@gmail.com", $pwSecure)

$smtp = New-Object System.Net.Mail.SmtpClient("smtp.gmail.com", 587)
$smtp.EnableSsl = $true
$smtp.Credentials = $cred

$from = New-Object System.Net.Mail.MailAddress(
  "adventconnectzw@gmail.com", "Adventist Super App")

$ok = 0; $fail = 0
foreach ($to in $pending) {
  try {
    $msg = New-Object System.Net.Mail.MailMessage
    $msg.From = $from
    # One message PER RECIPIENT, never a shared To/CC. Bulk-CC would show
    # every member's address to every other member — a data breach dressed
    # up as a mailing list.
    $msg.To.Add($to)
    $msg.Subject = $Subject
    $msg.Body = $html
    $msg.IsBodyHtml = $true
    $smtp.Send($msg)
    $msg.Dispose()

    Add-Content -Path $SentLog -Value $to
    $ok++
    Write-Host ("  [{0}/{1}] {2}" -f ($ok + $fail), $pending.Count, $to) -ForegroundColor DarkGray
  } catch {
    $fail++
    Write-Warning ("FAILED {0}: {1}" -f $to, $_.Exception.Message)
  }
  if ($DelaySeconds -gt 0) { Start-Sleep -Seconds $DelaySeconds }
}

$smtp.Dispose()
Write-Host "`nSent: $ok   Failed: $fail" -ForegroundColor Green
Write-Host "Log: $SentLog  (delete it to allow a full re-send)" -ForegroundColor DarkGray
