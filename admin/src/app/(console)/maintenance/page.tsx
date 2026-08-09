"use client";

import { useEffect, useState } from "react";
import { rpc } from "@/lib/rpc";
import { useSession } from "@/lib/session";
import { fmtDate, isoToLocalInput, localInputToIso } from "@/lib/format";
import { useToast } from "@/components/Toast";
import { useAsk } from "@/components/Dialog";
import { CountedField, ErrorBox, Note, PageHead } from "@/components/ui";
import { IconPower, IconWrench } from "@/components/icons";

const DEFAULT_MESSAGE =
  "Advent Connect is down for scheduled maintenance. We will be back shortly.";

/**
 * The one switch in this console that stops the entire product.
 *
 * Everything about this page is shaped by that: the state is stated in a
 * sentence before any control appears, the message is previewed as a member's
 * phone will actually render it, and turning it ON needs a typed confirmation
 * while turning it OFF is a single click. Recovery must always be easier than
 * the mistake.
 */
export default function MaintenancePage() {
  const { maintenance, refreshMaintenance, role } = useSession();
  const toast = useToast();
  const ask = useAsk();

  const [message, setMessage] = useState(DEFAULT_MESSAGE);
  const [endsAt, setEndsAt] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Fill the form from whatever the server currently holds, so editing the
  // notice while it is live starts from the live text rather than a default
  // that would silently overwrite it.
  useEffect(() => {
    setMessage(maintenance.message || DEFAULT_MESSAGE);
    setEndsAt(isoToLocalInput(maintenance.ends_at));
  }, [maintenance.message, maintenance.ends_at]);

  const isOn = maintenance.active;

  const call = async (on: boolean) => {
    setBusy(true);
    setError(null);
    try {
      await rpc("admin_set_maintenance", {
        p_on: on,
        p_message: message.trim() || DEFAULT_MESSAGE,
        p_ends_at: localInputToIso(endsAt),
      });
      await refreshMaintenance();
      toast.ok(on ? "The app is now offline for members." : "The app is back on.");
    } catch (e) {
      const m = e instanceof Error ? e.message : "Could not change maintenance mode.";
      setError(m);
      toast.err(m);
    } finally {
      setBusy(false);
    }
  };

  const turnOn = async () => {
    const confirmed = await ask({
      title: "Take Advent Connect offline?",
      sub:
        "Every member is locked out within seconds — the ones already inside the " +
        "app too, not just the next person to open it. Nobody can post, message, " +
        "pray or buy until you turn it back on. They will each get a notification.",
      confirmLabel: "Take it offline",
      tone: "red",
      typeToConfirm: "OFFLINE",
    });
    if (confirmed === null) return;
    await call(true);
  };

  const turnOff = async () => {
    await call(false);
  };

  const saveNotice = async () => {
    await call(true);
  };

  if (role !== "owner") {
    return (
      <div>
        <PageHead title="Maintenance" />
        <Note>
          Only an <strong>owner</strong> can take the app offline. Ask whoever
          holds that role.
        </Note>
      </div>
    );
  }

  return (
    <div className="stack">
      <PageHead
        title="Maintenance mode"
        sub="Take the whole app offline while you work on it, then bring it back."
      />

      {/* State first, in a sentence, before any control. */}
      <div className={`maint-hero${isOn ? " on" : ""}`}>
        <div className="maint-state">
          {isOn ? <span className="pulse" /> : <IconPower size={24} />}
        </div>
        <div style={{ minWidth: 0, flex: 1 }}>
          <div className="maint-title">
            {isOn ? "The app is OFF for everyone" : "The app is running normally"}
          </div>
          <p className="meta" style={{ marginTop: 2 }}>
            {isOn ? (
              <>
                Members see the maintenance screen and every write is refused.
                {maintenance.ends_at
                  ? ` You told them it ends around ${fmtDate(maintenance.ends_at)}.`
                  : ""}
              </>
            ) : (
              "Members can use Advent Connect as usual."
            )}
          </p>
        </div>
        {isOn ? (
          <button className="btn primary" onClick={turnOff} disabled={busy}>
            {busy ? <span className="spinner" /> : null}
            Bring the app back
          </button>
        ) : (
          <button className="btn solid-red" onClick={turnOn} disabled={busy}>
            {busy ? <span className="spinner" /> : <IconWrench className="btn-icon" size={15} />}
            Take the app offline
          </button>
        )}
      </div>

      {error ? <ErrorBox message={error} /> : null}

      <div className="card card-pad">
        <div className="section-title">What members will see</div>

        <div className="row" style={{ alignItems: "flex-start", gap: 24, flexWrap: "wrap" }}>
          <div style={{ flex: "1 1 320px", minWidth: 280, display: "grid", gap: 16 }}>
            <CountedField
              label="Message"
              value={message}
              onChange={setMessage}
              max={280}
              textarea
              rows={3}
              placeholder={DEFAULT_MESSAGE}
            />

            <div className="field">
              <label className="label" htmlFor="ends">
                Expected back (optional)
              </label>
              <input
                id="ends"
                className="input"
                type="datetime-local"
                value={endsAt}
                onChange={(e) => setEndsAt(e.target.value)}
              />
              <div className="faint">
                Shown as “Expected back around…”. Leaving it empty is honest when
                you do not know — a time you miss is worse than no time at all.
              </div>
            </div>

            {isOn ? (
              <div className="row">
                <button className="btn" onClick={saveNotice} disabled={busy}>
                  {busy ? <span className="spinner" /> : null}
                  Update the notice
                </button>
                <span className="faint">
                  Editing while it is off does not re-notify anyone.
                </span>
              </div>
            ) : null}
          </div>

          {/* Written blind, a maintenance notice is the one message you cannot
              take back — everyone gets it at once. */}
          <div className="phone-preview" aria-label="Preview of the members' screen">
            <div className="pp-icon">
              <IconWrench size={22} />
            </div>
            <div className="pp-title">Back shortly</div>
            <div className="pp-msg">{message.trim() || DEFAULT_MESSAGE}</div>
            {endsAt ? (
              <div
                className="pp-msg"
                style={{ marginTop: 8, color: "var(--blue)", fontWeight: 600 }}
              >
                Expected back around{" "}
                {new Date(endsAt).toLocaleTimeString("en-GB", {
                  hour: "2-digit",
                  minute: "2-digit",
                })}
                .
              </div>
            ) : null}
            <div className="pp-btn">Check again</div>
          </div>
        </div>
      </div>

      <div className="card card-pad">
        <div className="section-title">What actually happens</div>
        <ul
          className="meta"
          style={{ paddingLeft: 18, margin: 0, display: "grid", gap: 7 }}
        >
          <li>
            <strong>Nobody can bypass it.</strong> The block is a database rule,
            not a screen. Even a modified copy of the app has every post,
            message, prayer, order and comment refused.
          </li>
          <li>
            <strong>People already inside the app are locked out too</strong>,
            within a few seconds — not only the next person to open it.
          </li>
          <li>
            <strong>You are exempt.</strong> Super admins keep working, so
            whatever the maintenance is for can actually be fixed.
          </li>
          <li>
            <strong>Reading still works.</strong> That is deliberate: the app has
            to be able to fetch this notice to show it.
          </li>
          <li>
            <strong>Everyone is notified once</strong> when it goes off, and once
            when it comes back. Re-saving the message does not notify again.
          </li>
          <li>
            <strong>It is recorded</strong> in the audit log, with who flipped it
            and when.
          </li>
        </ul>
      </div>
    </div>
  );
}
