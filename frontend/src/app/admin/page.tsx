"use client";

import { useState } from "react";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { formatEther } from "viem";
import { CONTRACTS, OWNER_ADDRESS, DEMO_MODE } from "@/config/contracts";
import { MembershipNFTABI } from "@/abis/MembershipNFT";
import { GovernanceABI } from "@/abis/Governance";
import { AIRecommendationABI } from "@/abis/AIRecommendation";

function useTx() {
  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading, isSuccess } = useWaitForTransactionReceipt({ hash });
  return { writeContract, isPending: isPending || isLoading, isSuccess };
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="card flex flex-col gap-4">
      <h2 className="font-semibold text-base border-b border-[var(--border)] pb-3">{title}</h2>
      {children}
    </div>
  );
}

function AnalyzeAndPost() {
  const [proposalId, setProposalId] = useState("");
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [fundAmount, setFundAmount] = useState("");
  const [destination, setDestination] = useState("");
  const [status, setStatus] = useState<"idle" | "analyzing" | "posting" | "done" | "error">("idle");
  const [result, setResult] = useState<{ riskScore: number; rewardScore: number; recommendation: string } | null>(null);
  const [errorMsg, setErrorMsg] = useState("");

  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const analyze = async () => {
    setStatus("analyzing");
    setErrorMsg("");
    try {
      const res = await fetch("/api/analyze-proposal", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ title, description, fundAmount, destination }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setResult(data);
      setStatus("idle");
    } catch (e: unknown) {
      setErrorMsg(e instanceof Error ? e.message : "Unknown error");
      setStatus("error");
    }
  };

  const postOnChain = () => {
    if (!result || !proposalId || DEMO_MODE) return;
    setStatus("posting");
    writeContract({
      address: CONTRACTS.aiRecommendation,
      abi: AIRecommendationABI,
      functionName: "addAIRecommendation",
      args: [BigInt(proposalId), result.recommendation, result.riskScore, result.rewardScore],
    });
  };

  if (isSuccess && status === "posting") setStatus("done");

  return (
    <div className="flex flex-col gap-4">
      <div className="grid grid-cols-2 gap-3">
        <div className="flex flex-col gap-1.5 col-span-2">
          <label className="text-sm font-medium">Proposal ID</label>
          <input className="input" placeholder="1" value={proposalId} onChange={(e) => setProposalId(e.target.value)} />
        </div>
        <div className="flex flex-col gap-1.5 col-span-2">
          <label className="text-sm font-medium">Proposal Title</label>
          <input className="input" placeholder="Title" value={title} onChange={(e) => setTitle(e.target.value)} />
        </div>
        <div className="flex flex-col gap-1.5 col-span-2">
          <label className="text-sm font-medium">Description</label>
          <textarea className="input min-h-[80px] resize-y" placeholder="Description" value={description} onChange={(e) => setDescription(e.target.value)} />
        </div>
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium">Fund Amount (ETH)</label>
          <input className="input" placeholder="1.5" value={fundAmount} onChange={(e) => setFundAmount(e.target.value)} />
        </div>
        <div className="flex flex-col gap-1.5">
          <label className="text-sm font-medium">Destination</label>
          <input className="input font-mono text-xs" placeholder="0x…" value={destination} onChange={(e) => setDestination(e.target.value)} />
        </div>
      </div>

      <button
        className="btn btn-primary self-start"
        onClick={analyze}
        disabled={!title || !description || status === "analyzing"}
      >
        {status === "analyzing" ? "Asking Claude…" : "🤖 Analyze with Claude"}
      </button>

      {result && (
        <div className="bg-[var(--surface-3)] rounded-lg p-4 flex flex-col gap-3">
          <div className="flex gap-6 text-sm">
            <div><span className="text-[var(--text-muted)]">Risk: </span><strong className="text-[var(--red)]">{result.riskScore}/100</strong></div>
            <div><span className="text-[var(--text-muted)]">Reward: </span><strong className="text-[var(--green)]">{result.rewardScore}/100</strong></div>
          </div>
          <p className="text-sm text-[var(--text-muted)] leading-relaxed">{result.recommendation}</p>
          <button
            className="btn btn-success self-start"
            onClick={postOnChain}
            disabled={isPending || isConfirming || DEMO_MODE || !proposalId}
          >
            {isPending || isConfirming ? "Posting…" : "Post to Chain"}
          </button>
          {DEMO_MODE && <p className="text-xs text-[var(--text-muted)]">Connect contracts to post on-chain.</p>}
          {status === "done" && <p className="text-xs text-[var(--green)]">✓ Recommendation posted on-chain!</p>}
        </div>
      )}

      {status === "error" && <p className="text-xs text-[var(--red)]">{errorMsg}</p>}
    </div>
  );
}

export default function AdminPage() {
  const { address } = useAccount();
  const isOwner = DEMO_MODE || address?.toLowerCase() === OWNER_ADDRESS;

  const mintTx = useTx();
  const revokeTx = useTx();
  const syncTx = useTx();
  const oracleTx = useTx();

  const [mintAddr, setMintAddr] = useState("");
  const [mintUri, setMintUri] = useState("");
  const [revokeAddr, setRevokeAddr] = useState("");
  const [syncCount, setSyncCount] = useState("");
  const [oracleAddr, setOracleAddr] = useState("");

  if (!isOwner) {
    return (
      <div className="card text-center py-16">
        <p className="text-4xl mb-3">🔒</p>
        <p className="font-semibold">Owner access only</p>
        <p className="text-sm text-[var(--text-muted)] mt-1">
          Set <code className="text-[var(--brand)]">NEXT_PUBLIC_OWNER_ADDRESS</code> in{" "}
          <code>.env.local</code> to unlock this page.
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6 max-w-2xl">
      <div>
        <h1 className="text-2xl font-bold mb-1">Admin Panel</h1>
        <p className="text-[var(--text-muted)] text-sm">Owner-only controls for managing the DAO.</p>
      </div>

      <Section title="🤖 AI Analysis — Claude AI">
        <p className="text-sm text-[var(--text-muted)]">
          Call Claude AI to analyse a proposal, then post the result on-chain.
        </p>
        <AnalyzeAndPost />
      </Section>

      <Section title="🪙 Membership NFTs">
        <div className="flex flex-col gap-3">
          <label className="text-sm font-medium">Mint membership to address</label>
          <input className="input font-mono text-sm" placeholder="0x…" value={mintAddr} onChange={(e) => setMintAddr(e.target.value)} />
          <input className="input text-sm" placeholder="Metadata URI (optional)" value={mintUri} onChange={(e) => setMintUri(e.target.value)} />
          <button
            className="btn btn-primary self-start"
            disabled={!mintAddr || mintTx.isPending || DEMO_MODE}
            onClick={() =>
              mintTx.writeContract({
                address: CONTRACTS.membershipNFT,
                abi: MembershipNFTABI,
                functionName: "mintMembershipNFT",
                args: [mintAddr as `0x${string}`, mintUri],
              })
            }
          >
            {mintTx.isPending ? "Minting…" : "Mint Membership NFT"}
          </button>
          {mintTx.isSuccess && <p className="text-xs text-[var(--green)]">✓ Membership minted!</p>}
        </div>

        <div className="flex flex-col gap-3 border-t border-[var(--border)] pt-4">
          <label className="text-sm font-medium">Revoke membership from address</label>
          <input className="input font-mono text-sm" placeholder="0x…" value={revokeAddr} onChange={(e) => setRevokeAddr(e.target.value)} />
          <button
            className="btn btn-danger self-start"
            disabled={!revokeAddr || revokeTx.isPending || DEMO_MODE}
            onClick={() =>
              revokeTx.writeContract({
                address: CONTRACTS.membershipNFT,
                abi: MembershipNFTABI,
                functionName: "revokeMembership",
                args: [revokeAddr as `0x${string}`],
              })
            }
          >
            {revokeTx.isPending ? "Revoking…" : "Revoke Membership"}
          </button>
          {revokeTx.isSuccess && <p className="text-xs text-[var(--green)]">✓ Membership revoked.</p>}
        </div>
      </Section>

      <Section title="⚙️ Governance Settings">
        <div className="flex flex-col gap-3">
          <label className="text-sm font-medium">Sync member count</label>
          <div className="flex gap-2">
            <input className="input" type="number" min="0" placeholder="6" value={syncCount} onChange={(e) => setSyncCount(e.target.value)} />
            <button
              className="btn btn-secondary whitespace-nowrap"
              disabled={!syncCount || syncTx.isPending || DEMO_MODE}
              onClick={() =>
                syncTx.writeContract({
                  address: CONTRACTS.governance,
                  abi: GovernanceABI,
                  functionName: "syncMemberCount",
                  args: [BigInt(syncCount)],
                })
              }
            >
              {syncTx.isPending ? "Syncing…" : "Sync"}
            </button>
          </div>
          {syncTx.isSuccess && <p className="text-xs text-[var(--green)]">✓ Member count updated.</p>}
        </div>
      </Section>

      <Section title="🔮 AI Oracle">
        <div className="flex flex-col gap-3">
          <label className="text-sm font-medium">Set AI oracle address</label>
          <input className="input font-mono text-sm" placeholder="0x…" value={oracleAddr} onChange={(e) => setOracleAddr(e.target.value)} />
          <button
            className="btn btn-secondary self-start"
            disabled={!oracleAddr || oracleTx.isPending || DEMO_MODE}
            onClick={() =>
              oracleTx.writeContract({
                address: CONTRACTS.aiRecommendation,
                abi: AIRecommendationABI,
                functionName: "setAIOracle",
                args: [oracleAddr as `0x${string}`],
              })
            }
          >
            {oracleTx.isPending ? "Setting…" : "Set Oracle"}
          </button>
          {oracleTx.isSuccess && <p className="text-xs text-[var(--green)]">✓ Oracle updated.</p>}
        </div>
      </Section>
    </div>
  );
}
