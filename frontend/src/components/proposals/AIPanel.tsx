"use client";

interface AIRec {
  text: string;
  riskScore: number;
  rewardScore: number;
}

function ScoreRing({ value, label, color }: { value: number; label: string; color: string }) {
  const r = 28;
  const circ = 2 * Math.PI * r;
  const offset = circ - (value / 100) * circ;

  return (
    <div className="flex flex-col items-center gap-1">
      <svg width="72" height="72" viewBox="0 0 72 72">
        <circle cx="36" cy="36" r={r} fill="none" stroke="var(--surface-3)" strokeWidth="6" />
        <circle
          cx="36" cy="36" r={r} fill="none" stroke={color} strokeWidth="6"
          strokeDasharray={circ} strokeDashoffset={offset}
          strokeLinecap="round" transform="rotate(-90 36 36)"
        />
        <text x="36" y="40" textAnchor="middle" fontSize="14" fontWeight="bold" fill={color}>
          {value}
        </text>
      </svg>
      <span className="text-xs text-[var(--text-muted)]">{label}</span>
    </div>
  );
}

export function AIPanel({ rec }: { rec: AIRec | null }) {
  if (!rec) {
    return (
      <div className="card border-dashed flex flex-col items-center gap-2 py-8 text-center">
        <div className="text-3xl">🤖</div>
        <p className="font-medium">No AI analysis yet</p>
        <p className="text-sm text-[var(--text-muted)]">
          The AI oracle can analyse this proposal from the Admin panel.
        </p>
      </div>
    );
  }

  return (
    <div className="card border-[var(--brand)] border-opacity-40" style={{ borderColor: "rgba(108,71,255,0.3)" }}>
      <div className="flex items-center gap-2 mb-4">
        <span className="text-lg">🤖</span>
        <h3 className="font-semibold">Claude AI Analysis</h3>
        <span className="badge badge-owner ml-auto">AI Verified</span>
      </div>

      <div className="flex gap-6 justify-center mb-4">
        <ScoreRing value={rec.riskScore}   label="Risk Score"   color="var(--red)" />
        <ScoreRing value={rec.rewardScore} label="Reward Score" color="var(--green)" />
      </div>

      <p className="text-sm text-[var(--text-muted)] leading-relaxed">{rec.text}</p>
    </div>
  );
}
