"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { parseEther } from "viem";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { CONTRACTS, DEMO_MODE } from "@/config/contracts";
import { GovernanceABI } from "@/abis/Governance";

export default function NewProposalPage() {
  const router = useRouter();
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [options, setOptions] = useState(["Approve", "Reject"]);
  const [destination, setDestination] = useState("");
  const [fundAmount, setFundAmount] = useState("");

  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  if (isSuccess) router.push("/proposals");

  const addOption = () => setOptions((o) => [...o, ""]);
  const removeOption = (i: number) => setOptions((o) => o.filter((_, idx) => idx !== i));
  const setOption = (i: number, v: string) =>
    setOptions((o) => o.map((opt, idx) => (idx === i ? v : opt)));

  const submit = () => {
    if (!title || !description || options.length < 2 || !destination || !fundAmount || DEMO_MODE) return;
    writeContract({
      address: CONTRACTS.governance,
      abi: GovernanceABI,
      functionName: "createProposal",
      args: [title, description, options, destination as `0x${string}`, parseEther(fundAmount)],
    });
  };

  return (
    <div className="max-w-xl flex flex-col gap-6">
      <div>
        <h1 className="text-2xl font-bold mb-1">New Proposal</h1>
        <p className="text-[var(--text-muted)] text-sm">
          Propose a fund allocation for the DAO treasury.
        </p>
      </div>

      <div className="card flex flex-col gap-5">
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium">Title</label>
          <input
            className="input"
            placeholder="e.g. Invest in ETH Staking Strategy"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
          />
        </div>

        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium">Description</label>
          <textarea
            className="input min-h-[100px] resize-y"
            placeholder="Describe the investment rationale, expected returns, and risks…"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
          />
        </div>

        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium">Voting Options</label>
          {options.map((opt, i) => (
            <div key={i} className="flex gap-2">
              <input
                className="input"
                placeholder={`Option ${i + 1}`}
                value={opt}
                onChange={(e) => setOption(i, e.target.value)}
              />
              {options.length > 2 && (
                <button className="btn btn-danger px-3" onClick={() => removeOption(i)}>✕</button>
              )}
            </div>
          ))}
          <button className="btn btn-secondary self-start text-xs" onClick={addOption}>
            + Add Option
          </button>
        </div>

        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium">Destination Address</label>
          <input
            className="input font-mono text-sm"
            placeholder="0x… address to receive funds if approved"
            value={destination}
            onChange={(e) => setDestination(e.target.value)}
          />
        </div>

        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium">Requested Amount (ETH)</label>
          <input
            className="input"
            type="number"
            step="0.01"
            min="0"
            placeholder="0.0"
            value={fundAmount}
            onChange={(e) => setFundAmount(e.target.value)}
          />
        </div>

        <button
          className="btn btn-primary"
          onClick={submit}
          disabled={isPending || isConfirming || DEMO_MODE}
        >
          {isPending || isConfirming ? "Submitting…" : "Create Proposal"}
        </button>

        {DEMO_MODE && (
          <p className="text-xs text-[var(--text-muted)]">
            Connect contracts to submit proposals on-chain.
          </p>
        )}
      </div>
    </div>
  );
}
