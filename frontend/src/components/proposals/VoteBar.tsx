import { formatEther } from "viem";

interface Props {
  votesFor: bigint;
  votesAgainst: bigint;
}

export function VoteBar({ votesFor, votesAgainst }: Props) {
  const total = Number(votesFor) + Number(votesAgainst);
  const forPct = total === 0 ? 50 : (Number(votesFor) / total) * 100;

  return (
    <div className="flex flex-col gap-1">
      <div className="flex justify-between text-xs text-[var(--text-muted)]">
        <span>✓ {votesFor.toString()} For</span>
        <span>{votesAgainst.toString()} Against ✗</span>
      </div>
      <div className="h-2 rounded-full bg-[var(--surface-3)] overflow-hidden">
        <div
          className="h-full rounded-full bg-[var(--green)] transition-all"
          style={{ width: `${forPct}%` }}
        />
      </div>
    </div>
  );
}
