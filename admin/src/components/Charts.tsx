"use client";

import { useId } from "react";
import { fmtDay, fmtNum, pct } from "@/lib/format";

/**
 * Two charts, drawn as inline SVG.
 *
 * No charting library: the console shows one line and one bar list, on a
 * dataset of 190 members and thirty days. Recharts would be a larger
 * download than the entire rest of this app for two shapes that are forty
 * lines of SVG each — and it would still need the same amount of styling to
 * stop looking like a demo.
 *
 * Both are labelled in text as well as drawn, because a chart that a colour
 * blind reader or a screen reader cannot use is decoration.
 */

/* ---- horizontal bar list ----------------------------------------------- */

export type BarDatum = { name: string; value: number; sub?: string };

export function BarList({
  data,
  unit,
  showZeroNote,
}: {
  data: BarDatum[];
  unit?: string;
  /** Explains a zero rather than drawing an empty bar with no comment. */
  showZeroNote?: boolean;
}) {
  const max = Math.max(1, ...data.map((d) => d.value));
  const anyZero = data.some((d) => d.value === 0);

  return (
    <div>
      {data.map((d) => {
        const width = d.value === 0 ? 2 : Math.max(3, (d.value / max) * 100);
        return (
          <div className="bar-row" key={d.name}>
            <div className="bar-name" title={d.name}>
              {d.name}
            </div>
            <div className="bar-track">
              <div
                className={`bar-fill${d.value === 0 ? " zero" : ""}`}
                style={{ width: `${width}%` }}
              />
            </div>
            <div className="bar-value">
              {fmtNum(d.value)}
              {unit ? ` ${unit}` : ""}
              {d.sub ? <span className="faint"> · {d.sub}</span> : null}
            </div>
          </div>
        );
      })}
      {showZeroNote && anyZero ? (
        <div className="faint" style={{ marginTop: 10 }}>
          A zero means nobody opened it in this window — which is an answer, not
          a gap in the data.
        </div>
      ) : null}
    </div>
  );
}

/* ---- time series ------------------------------------------------------- */

export type SeriesPoint = { day: string; value: number };

export function LineChart({
  series,
  label,
  height = 190,
}: {
  series: SeriesPoint[];
  label: string;
  height?: number;
}) {
  const gradientId = useId().replace(/:/g, "");

  if (series.length < 2) {
    return (
      <div className="meta" style={{ padding: "24px 0" }}>
        Not enough days of data to draw a trend yet.
      </div>
    );
  }

  const w = 720;
  const h = height;
  const padX = 8;
  const padTop = 14;
  const padBottom = 26;

  const values = series.map((p) => p.value);
  const max = Math.max(1, ...values);
  const innerW = w - padX * 2;
  const innerH = h - padTop - padBottom;

  const x = (i: number) => padX + (i / (series.length - 1)) * innerW;
  const y = (v: number) => padTop + innerH - (v / max) * innerH;

  const line = series.map((p, i) => `${i === 0 ? "M" : "L"}${x(i)},${y(p.value)}`).join(" ");
  const area = `${line} L${x(series.length - 1)},${padTop + innerH} L${padX},${
    padTop + innerH
  } Z`;

  // Four gridlines is enough to read a value off; more turns into a net.
  const ticks = [0, 0.25, 0.5, 0.75, 1].map((f) => Math.round(max * f));

  const peak = series.reduce((a, b) => (b.value > a.value ? b : a), series[0]);

  return (
    <div>
      <svg
        className="chart"
        viewBox={`0 0 ${w} ${h}`}
        preserveAspectRatio="none"
        role="img"
        aria-label={`${label}. Peak ${peak.value} on ${fmtDay(peak.day)}.`}
        style={{ height }}
      >
        <defs>
          <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="var(--blue)" stopOpacity="0.26" />
            <stop offset="100%" stopColor="var(--blue)" stopOpacity="0" />
          </linearGradient>
        </defs>

        {ticks.map((t, i) => {
          const gy = y(t);
          return (
            <line
              key={i}
              x1={padX}
              x2={w - padX}
              y1={gy}
              y2={gy}
              stroke="var(--border)"
              strokeWidth="1"
              vectorEffect="non-scaling-stroke"
            />
          );
        })}

        <path d={area} fill={`url(#${gradientId})`} />
        <path
          d={line}
          fill="none"
          stroke="var(--blue)"
          strokeWidth="2"
          strokeLinejoin="round"
          strokeLinecap="round"
          vectorEffect="non-scaling-stroke"
        />
        <circle cx={x(series.length - 1)} cy={y(series[series.length - 1].value)} r="3.5" fill="var(--blue)" />
      </svg>

      <div className="row" style={{ justifyContent: "space-between", marginTop: 4 }}>
        <span className="faint">{fmtDay(series[0].day)}</span>
        <span className="faint">
          peak {fmtNum(peak.value)} · {fmtDay(peak.day)}
        </span>
        <span className="faint">{fmtDay(series[series.length - 1].day)}</span>
      </div>
    </div>
  );
}

/* ---- share breakdown --------------------------------------------------- */

export function ShareBars({
  rows,
}: {
  rows: { name: string; total: number }[];
}) {
  const total = rows.reduce((s, r) => s + r.total, 0);
  return (
    <div>
      {rows.map((r) => (
        <div key={r.name} style={{ marginBottom: 12 }}>
          <div className="row" style={{ justifyContent: "space-between", marginBottom: 4 }}>
            <b style={{ fontSize: 13 }}>{r.name}</b>
            <span className="meta">
              {fmtNum(r.total)} · {pct(r.total, total)}%
            </span>
          </div>
          <div className="bar-track">
            <div
              className="bar-fill"
              style={{ width: `${Math.max(pct(r.total, total), 2)}%` }}
            />
          </div>
        </div>
      ))}
    </div>
  );
}
