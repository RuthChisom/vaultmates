"use client";

import { useState } from "react";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { parseEther } from "viem";
import { CONTRACTS, DEMO_MODE } from "@/config/contracts";
import { VaultABI } from "@/abis/Vault";

export function WithdrawForm({ onSuccess }: { onSuccess?: () => void }) {
  const [amount, setAmount] = useState("");
  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const submit = () => {
    if (!amount || DEMO_MODE) return;
    writeContract({
      address: CONTRACTS.vault,
      abi: VaultABI,
      functionName: "withdrawFunds",
      args: [parseEther(amount)],
    });
  };

  if (isSuccess && onSuccess) onSuccess();

  return (
    <div className="flex flex-col gap-3">
      <label className="text-sm font-medium text-[var(--text-muted)]">Amount (ETH)</label>
      <div className="flex gap-2">
        <input
          type="number"
          step="0.01"
          min="0"
          placeholder="0.0"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          className="input"
        />
        <button
          className="btn btn-secondary whitespace-nowrap"
          onClick={submit}
          disabled={!amount || isPending || isConfirming || DEMO_MODE}
        >
          {isPending || isConfirming ? "Withdrawing…" : "Withdraw"}
        </button>
      </div>
      {isSuccess && <p className="text-xs text-[var(--green)]">✓ Withdrawal confirmed!</p>}
    </div>
  );
}
