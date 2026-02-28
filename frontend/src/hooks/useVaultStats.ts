"use client";

import { useAccount, useReadContracts } from "wagmi";
import { formatEther } from "viem";
import { CONTRACTS, DEMO_MODE } from "@/config/contracts";
import { VaultABI } from "@/abis/Vault";
import { GovernanceABI } from "@/abis/Governance";
import { MOCK_STATS } from "@/lib/mockData";

export function useVaultStats() {
  const { address } = useAccount();

  const { data, refetch } = useReadContracts({
    contracts: [
      { address: CONTRACTS.vault, abi: VaultABI, functionName: "totalAssets" },
      { address: CONTRACTS.vault, abi: VaultABI, functionName: "getUserBalance", args: [address ?? "0x0"] },
      { address: CONTRACTS.governance, abi: GovernanceABI, functionName: "memberCount" },
      { address: CONTRACTS.governance, abi: GovernanceABI, functionName: "proposalCount" },
      { address: CONTRACTS.governance, abi: GovernanceABI, functionName: "quorumBps" },
    ],
    query: { enabled: !DEMO_MODE },
  });

  if (DEMO_MODE) return { ...MOCK_STATS, refetch: () => {} };

  return {
    totalAssets: data?.[0].result ? formatEther(data[0].result as bigint) : "0",
    userBalance: data?.[1].result ? formatEther(data[1].result as bigint) : "0",
    memberCount: (data?.[2].result as bigint) ?? 0n,
    proposalCount: (data?.[3].result as bigint) ?? 0n,
    quorumBps: (data?.[4].result as bigint) ?? 0n,
    refetch,
  };
}
