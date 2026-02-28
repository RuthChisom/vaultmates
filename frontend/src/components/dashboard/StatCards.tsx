"use client";

interface Props {
  totalAssets: string;
  userBalance: string;
  memberCount: bigint;
  proposalCount: bigint;
  quorumBps: bigint;
}

export function StatCards({ totalAssets, userBalance, memberCount, proposalCount, quorumBps }: Props) {
  const quorumPct = Number(quorumBps) / 100;

  const stats = [
    { label: "Total Vault Assets", value: `${Number(totalAssets).toFixed(4)} ETH`, accent: "var(--brand)" },
    { label: "Your Balance", value: `${Number(userBalance).toFixed(4)} ETH`, accent: "var(--green)" },
    { label: "Members", value: memberCount.toString(), accent: "var(--blue)" },
    { label: "Proposals", value: proposalCount.toString(), accent: "var(--yellow)" },
    { label: "Quorum Required", value: `${quorumPct}%`, accent: "var(--purple)" },
  ];

  return (
    <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
      {stats.map(({ label, value, accent }) => (
        <div key={label} className="card flex flex-col gap-1">
          <div className="text-xs text-[var(--text-muted)]">{label}</div>
          <div className="text-2xl font-bold" style={{ color: accent }}>{value}</div>
        </div>
      ))}
    </div>
  );
}
