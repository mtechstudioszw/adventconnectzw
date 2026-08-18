"use client";

import { useCallback } from "react";
import { rpcList } from "@/lib/rpc";
import { useAsync } from "@/lib/useAsync";
import { ShareBars } from "@/components/Charts";
import { Empty, ErrorBox, Note, PageHead } from "@/components/ui";
import { IconRefresh } from "@/components/icons";
import { fmtNum } from "@/lib/format";

type SurveyRow = { source: string; total: number };
type DeletionRow = { reason: string; total: number; share: number };

/**
 * The two ends of the same question, deliberately on one page: what brought
 * people in, and what made them leave. Read separately they are trivia; side
 * by side they are the only churn signal the product has.
 */
export default function InsightsPage() {
  const load = useCallback(
    () =>
      Promise.all([
        rpcList<SurveyRow>("admin_survey_summary").catch(() => []),
        rpcList<DeletionRow>("admin_deletion_reasons", { p_days: 90 }).catch(() => []),
      ]),
    [],
  );

  const { data, error, loading, reload } = useAsync(load, []);
  const [survey, deletions] = data ?? [[], []];

  const joined = survey.reduce((s, r) => s + Number(r.total ?? 0), 0);
  const left = deletions.reduce((s, r) => s + Number(r.total ?? 0), 0);

  return (
    <div className="stack">
      <PageHead
        title="Why they join & leave"
        sub="From the first-run signup survey and the account-deletion exit survey."
        actions={
          <button className="btn ghost" onClick={reload} disabled={loading}>
            <IconRefresh className="btn-icon" size={15} />
            Refresh
          </button>
        }
      />

      {error ? <ErrorBox message={error} /> : null}

      <div
        style={{
          display: "grid",
          gap: 20,
          gridTemplateColumns: "repeat(auto-fit, minmax(320px, 1fr))",
        }}
      >
        <div className="card card-pad">
          <div className="section-title">
            How they found Adventist Super App
            {joined > 0 ? <span className="count">{fmtNum(joined)} answers</span> : null}
          </div>
          {loading && !data ? (
            <div className="skeleton" style={{ height: 140 }} />
          ) : survey.length === 0 ? (
            <Empty title="No survey answers yet" />
          ) : (
            <ShareBars
              rows={survey.map((r) => ({
                name: r.source || "Not specified",
                total: Number(r.total ?? 0),
              }))}
            />
          )}
        </div>

        <div className="card card-pad">
          <div className="section-title">
            Why accounts were deleted
            {left > 0 ? <span className="count">last 90 days</span> : null}
          </div>
          {loading && !data ? (
            <div className="skeleton" style={{ height: 140 }} />
          ) : deletions.length === 0 ? (
            <Empty
              title="Nobody has deleted an account"
              sub="Nothing in the last 90 days — which is the good outcome."
            />
          ) : (
            <ShareBars
              rows={deletions.map((r) => ({
                name: r.reason || "Not given",
                total: Number(r.total ?? 0),
              }))}
            />
          )}
        </div>
      </div>

      <Note>
        Both surveys are optional, so these are the answers of people who chose
        to reply — not of everyone who joined or left. Treat the ordering as
        real and the totals as a floor.
      </Note>
    </div>
  );
}
