"use client";

import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { CONTRACTS, DEMO_MODE } from "@/config/contracts";
import { ExecutorABI } from "@/abis/Executor";
import { GovernanceABI } from "@/abis/Governance";

interface Props {
  proposalId: bigint;
  status: number;
  isExecuted: boolean;
  onSuccess?: () => void;
}

export function ExecuteButton({ proposalId, status, isExecuted, onSuccess }: Props) {
  const { writeContract: execWrite, data: execHash, isPending: execPending } = useWriteContract();
  const { writeContract: finalWrite, data: finalHash, isPending: finalPending } = useWriteContract();
  const { isLoading: execConfirming, isSuccess: execDone } = useWaitForTransactionReceipt({ hash: execHash });
  const { isLoading: finalConfirming, isSuccess: finalDone } = useWaitForTransactionReceipt({ hash: finalHash });

  if (execDone && onSuccess) onSuccess();
  if (finalDone && onSuccess) onSuccess();

  const isPast = true; // simplified — parent should only render this when deadline passed

  if (status === 0) {
    return (
      <button
        className="btn btn-secondary"
        disabled={finalPending || finalConfirming || DEMO_MODE}
        onClick={() =>
          finalWrite({
            address: CONTRACTS.governance,
            abi: GovernanceABI,
            functionName: "finalizeProposal",
            args: [proposalId],
          })
        }
      >
        {finalPending || finalConfirming ? "Finalizing…" : "Finalize Proposal"}
      </button>
    );
  }

  if (status === 1 && !isExecuted) {
    return (
      <button
        className="btn btn-primary"
        disabled={execPending || execConfirming || DEMO_MODE}
        onClick={() =>
          execWrite({
            address: CONTRACTS.executor,
            abi: ExecutorABI,
            functionName: "executeProposal",
            args: [proposalId],
          })
        }
      >
        {execPending || execConfirming ? "Executing…" : "⚡ Execute Proposal"}
      </button>
    );
  }

  if (status === 3 || isExecuted) {
    return <p className="text-sm text-[var(--purple)]">✓ Proposal has been executed.</p>;
  }

  return null;
}
