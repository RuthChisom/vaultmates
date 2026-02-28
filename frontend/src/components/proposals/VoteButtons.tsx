"use client";

import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { CONTRACTS, DEMO_MODE } from "@/config/contracts";
import { GovernanceABI } from "@/abis/Governance";

interface Props {
  proposalId: bigint;
  options: string[];
  userVote: bigint;
  status: number;
  deadline: bigint;
  onSuccess?: () => void;
}

const NOT_VOTED = BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");

export function VoteButtons({ proposalId, options, userVote, status, deadline, onSuccess }: Props) {
  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const isActive = status === 0;
  const isPast = Number(deadline) < Math.floor(Date.now() / 1000);
  const hasVoted = userVote !== NOT_VOTED;
  const canVote = isActive && !isPast && !hasVoted;

  if (isSuccess && onSuccess) onSuccess();

  if (!isActive) {
    return <p className="text-sm text-[var(--text-muted)]">Voting is closed for this proposal.</p>;
  }

  if (isPast && isActive) {
    return (
      <p className="text-sm text-[var(--yellow)]">
        Voting period ended. Waiting to be finalized.
      </p>
    );
  }

  if (hasVoted && !DEMO_MODE) {
    return (
      <p className="text-sm text-[var(--green)]">
        ✓ You voted for option {Number(userVote)}: <strong>{options[Number(userVote)]}</strong>
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      <p className="text-sm text-[var(--text-muted)]">Cast your vote:</p>
      <div className="flex gap-3 flex-wrap">
        {options.map((opt, i) => (
          <button
            key={i}
            className={`btn ${i === 0 ? "btn-success" : "btn-danger"}`}
            disabled={isPending || isConfirming || DEMO_MODE}
            onClick={() =>
              writeContract({
                address: CONTRACTS.governance,
                abi: GovernanceABI,
                functionName: "vote",
                args: [proposalId, BigInt(i)],
              })
            }
          >
            {i === 0 ? "✓" : "✗"} {opt}
          </button>
        ))}
      </div>
      {isPending && <p className="text-xs text-[var(--text-muted)]">Waiting for wallet…</p>}
      {isConfirming && <p className="text-xs text-[var(--text-muted)]">Confirming…</p>}
      {DEMO_MODE && <p className="text-xs text-[var(--text-muted)]">Connect contracts to vote.</p>}
    </div>
  );
}
