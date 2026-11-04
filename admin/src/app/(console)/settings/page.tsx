"use client";

import { useCallback, useEffect, useState } from "react";
import { rpc } from "@/lib/rpc";
import { useAsync } from "@/lib/useAsync";
import { useSession } from "@/lib/session";
import { useToast } from "@/components/Toast";
import { useAsk } from "@/components/Dialog";
import { ErrorBox, Note, PageHead } from "@/components/ui";

/**
 * App settings (patch_314) — the handful of switches that used to need the
 * SQL editor. The database accepts only these keys, checks each value, and
 * logs every change with the old and new value. Owner only.
 */
type Settings = Record<string, string>;

type Field = {
  key: string;
  label: string;
  help: string;
  kind: "number" | "bool" | "text" | "ai";
  danger?: string;
};

const FIELDS: { group: string; fields: Field[] }[] = [
  {
    group: "App versions",
    fields: [
      {
        key: "min_build_android",
        label: "Minimum Android build",
        help: "Phones below this build must update before they can use the app. Raise it only after the new version is live on Google Play.",
        kind: "number",
        danger: "Every Android member on an older build is locked out until they update.",
      },
      {
        key: "latest_build_android",
        label: "Latest Android build",
        help: "Phones below this see a gentle “update available” prompt.",
        kind: "number",
      },
      {
        key: "min_build_ios",
        label: "Minimum iPhone build",
        help: "Same as Android, for iPhones. Raise it only after Apple has released the version.",
        kind: "number",
        danger: "Every iPhone member on an older build is locked out until they update.",
      },
      {
        key: "latest_build_ios",
        label: "Latest iPhone build",
        help: "iPhones below this see the update prompt.",
        kind: "number",
      },
      {
        key: "update_grace_days",
        label: "Update grace days",
        help: "How many days the update prompt can be dismissed before it insists.",
        kind: "number",
      },
    ],
  },
  {
    group: "Security",
    fields: [
      {
        key: "captcha_site_key",
        label: "CAPTCHA site key (Cloudflare Turnstile)",
        help: "Empty = no security check before sign-in. The SECRET key never goes here — it belongs only in Supabase.",
        kind: "text",
      },
      {
        key: "require_phone_verification",
        label: "Require a verified phone number",
        help: "Only switch on after SMS (Twilio) is set up in Supabase and tested — see docs/SECURITY_HANDOVER.md.",
        kind: "bool",
        danger:
          "Every account without a verified phone is blocked — no app, no notifications — until it verifies by SMS. If SMS is not set up, NOBODY can get back in.",
      },
    ],
  },
  {
    group: "Features",
    fields: [
      {
        key: "ai_service_state",
        label: "Advent AI",
        help: "Suspended shows members a calm “resting” message instead of errors. Only set Live once the AI key works.",
        kind: "ai",
      },
    ],
  },
];

export default function SettingsPage() {
  const { can } = useSession();
  const isOwner = can("owner");
  const toast = useToast();
  const ask = useAsk();

  const load = useCallback(() => rpc<Settings>("admin_get_app_settings"), []);
  const { data, error, reload } = useAsync<Settings>(load, []);
  const [draft, setDraft] = useState<Settings>({});
  const [busyKey, setBusyKey] = useState<string | null>(null);

  useEffect(() => {
    if (data) setDraft(data);
  }, [data]);

  const save = async (f: Field) => {
    const value = (draft[f.key] ?? "").trim();
    const before = (data?.[f.key] ?? "").trim();
    if (value === before) return;
    if (f.danger) {
      const raising =
        f.kind === "bool" ? value === "true" : f.kind === "number" ? Number(value) > Number(before || 0) : true;
      if (raising) {
        const ok = await ask({
          title: `Change “${f.label}”?`,
          sub: f.danger,
          confirmLabel: "Change it",
          tone: "red",
          typeToConfirm: "CONFIRM",
        });
        if (ok === null) return;
      }
    }
    setBusyKey(f.key);
    try {
      await rpc("admin_set_app_setting", { p_key: f.key, p_value: value });
      toast.ok(`${f.label} saved. Phones pick it up within a few minutes.`);
      reload();
    } catch (e) {
      toast.err(e instanceof Error ? e.message : "Could not save.");
    } finally {
      setBusyKey(null);
    }
  };

  return (
    <div>
      <PageHead title="App settings" sub="Switches that change the app for every member. Every change is logged." />
      {!isOwner ? <Note>Only an owner can change these. You can see the current values.</Note> : null}
      {error ? <ErrorBox message={error} /> : null}

      {FIELDS.map((g) => (
        <section key={g.group} className="card" style={{ marginBottom: 16, padding: 18 }}>
          <h3 style={{ fontSize: 15, fontWeight: 700, marginBottom: 12 }}>{g.group}</h3>
          {g.fields.map((f) => {
            const value = draft[f.key] ?? "";
            const changed = value.trim() !== (data?.[f.key] ?? "").trim();
            return (
              <div key={f.key} style={{ marginBottom: 16 }}>
                <label style={{ fontWeight: 600, display: "block" }}>{f.label}</label>
                <div className="meta" style={{ margin: "2px 0 6px", maxWidth: 640 }}>
                  {f.help}
                </div>
                <div className="row" style={{ gap: 8 }}>
                  {f.kind === "bool" || f.kind === "ai" ? (
                    <select
                      className="input"
                      style={{ maxWidth: 220 }}
                      disabled={!isOwner}
                      value={value}
                      onChange={(e) => setDraft({ ...draft, [f.key]: e.target.value })}
                    >
                      {f.kind === "bool" ? (
                        <>
                          <option value="false">Off</option>
                          <option value="true">On</option>
                        </>
                      ) : (
                        <>
                          <option value="suspended">Suspended</option>
                          <option value="live">Live</option>
                        </>
                      )}
                    </select>
                  ) : (
                    <input
                      className="input"
                      style={{ maxWidth: f.kind === "number" ? 140 : 360 }}
                      inputMode={f.kind === "number" ? "numeric" : undefined}
                      disabled={!isOwner}
                      value={value}
                      placeholder={f.kind === "text" ? "Empty = off" : ""}
                      onChange={(e) =>
                        setDraft({
                          ...draft,
                          [f.key]: f.kind === "number" ? e.target.value.replace(/\D/g, "") : e.target.value,
                        })
                      }
                    />
                  )}
                  {isOwner ? (
                    <button
                      className={`btn sm ${f.danger ? "red" : "primary"}`}
                      disabled={!changed || busyKey === f.key}
                      onClick={() => save(f)}
                    >
                      {busyKey === f.key ? "Saving…" : "Save"}
                    </button>
                  ) : null}
                </div>
              </div>
            );
          })}
        </section>
      ))}
    </div>
  );
}
