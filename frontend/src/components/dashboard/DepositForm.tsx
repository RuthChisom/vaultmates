"use client";

import { useState } from "react";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { parseEther } from "viem";
import { CONTRACTS, DEMO_MODE } from "@/config/contracts";
import { VaultABI } from "@/abis/Vault";

export function DepositForm({ onSuccess }: { onSuccess?: () => void }) {
  const [amount, setAmount] = useState("");
  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const submit = async () => {
    if (!amount || DEMO_MODE) return;
    writeContract({
      address: CONTRACTS.vault,
      abi: VaultABI,
      functionName: "depositFunds",
      value: parseEther(amount),
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
          className="btn btn-primary whitespace-nowrap"
          onClick={submit}
          disabled={!amount || isPending || isConfirming || DEMO_MODE}
        >
          {isPending || isConfirming ? "Depositing…" : "Deposit"}
        </button>
      </div>
      {DEMO_MODE && <p className="text-xs text-[var(--text-muted)]">Connect contracts to enable deposits.</p>}
      {isSuccess && <p className="text-xs text-[var(--green)]">✓ Deposit confirmed!</p>}
    </div>
  );
}
