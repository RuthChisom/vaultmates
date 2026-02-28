"use client";

import { useReadContracts, useReadContract } from "wagmi";
import { parseAbi } from "viem";
import { CONTRACTS, DEMO_MODE } from "@/config/contracts";
import { MOCK_PROPOSALS } from "@/lib/mockData";

const countAbi = parseAbi(["function proposalCount() view returns (uint256)"]);

const getProposalAbi = [
  {
    name: "getProposal",
    type: "function" as const,
    stateMutability: "view" as const,
    inputs: [{ name: "proposalId", type: "uint256" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "id", type: "uint256" },
          { name: "proposer", type: "address" },
          { name: "title", type: "string" },
          { name: "description", type: "string" },
          { name: "destination", type: "address" },
          { name: "fundAmount", type: "uint256" },
          { name: "votesFor", type: "uint256" },
          { name: "votesAgainst", type: "uint256" },
          { name: "deadline", type: "uint256" },
          { name: "status", type: "uint8" },
          { name: "options", type: "string[]" },
        ],
      },
    ],
  },
] as const;

export function useProposals() {
  const { data: rawCount } = useReadContract({
    address: CONTRACTS.governance,
    abi: countAbi,
    functionName: "proposalCount",
    query: { enabled: !DEMO_MODE },
  });

  const count = rawCount ? Number(rawCount) : 0;
  const ids = Array.from({ length: count }, (_, i) => BigInt(i + 1));

  const { data, refetch } = useReadContracts({
    contracts: ids.map((id) => ({
      address: CONTRACTS.governance,
      abi: getProposalAbi,
      functionName: "getProposal" as const,
      args: [id] as const,
    })),
    query: { enabled: !DEMO_MODE && count > 0 },
  });

  if (DEMO_MODE) return { proposals: MOCK_PROPOSALS, refetch: () => {} };

  const proposals = (data ?? [])
    .map((r) => r.result)
    .filter(Boolean) as typeof MOCK_PROPOSALS;

  return { proposals, refetch };
}
