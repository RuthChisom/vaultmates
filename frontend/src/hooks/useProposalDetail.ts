"use client";

import { useAccount, useReadContracts } from "wagmi";
import { formatEther } from "viem";
import { CONTRACTS, DEMO_MODE } from "@/config/contracts";
import { GovernanceABI } from "@/abis/Governance";
import { AIRecommendationABI } from "@/abis/AIRecommendation";
import { ExecutorABI } from "@/abis/Executor";
import { MOCK_PROPOSALS, MOCK_AI_RECS } from "@/lib/mockData";

export function useProposalDetail(proposalId: number) {
  const { address } = useAccount();
  const id = BigInt(proposalId);

  const { data, refetch } = useReadContracts({
    contracts: [
      { address: CONTRACTS.governance, abi: GovernanceABI, functionName: "getProposal", args: [id] },
      { address: CONTRACTS.governance, abi: GovernanceABI, functionName: "getVote", args: [id, address ?? "0x0"] },
      { address: CONTRACTS.aiRecommendation, abi: AIRecommendationABI, functionName: "hasRecommendation", args: [id] },
      { address: CONTRACTS.aiRecommendation, abi: AIRecommendationABI, functionName: "getAIRecommendation", args: [id] },
      { address: CONTRACTS.executor, abi: ExecutorABI, functionName: "isExecuted", args: [id] },
    ],
    query: { enabled: !DEMO_MODE },
  });

  if (DEMO_MODE) {
    const p = MOCK_PROPOSALS.find((p) => p.id === id);
    return {
      proposal: p ?? null,
      userVote: BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"),
      hasRec: !!MOCK_AI_RECS[proposalId],
      aiRec: MOCK_AI_RECS[proposalId] ?? null,
      isExecuted: p?.status === 3,
      refetch: () => {},
    };
  }

  const proposal = data?.[0].result as typeof MOCK_PROPOSALS[0] | undefined;
  const userVote = (data?.[1].result as bigint) ?? BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");
  const hasRec = !!(data?.[2].result);
  const rawRec = data?.[3].result as { text: string; riskScore: number; rewardScore: number; timestamp: bigint; postedBy: string; exists: boolean } | undefined;
  const aiRec = rawRec?.exists ? rawRec : null;
  const isExecuted = !!(data?.[4].result);

  return { proposal: proposal ?? null, userVote, hasRec, aiRec, isExecuted, refetch };
}
