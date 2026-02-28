export const MOCK_STATS = {
  totalAssets: "4.75",
  userBalance: "1.20",
  memberCount: 6n,
  proposalCount: 3n,
  quorumBps: 5000n,
};

export const MOCK_PROPOSALS = [
  {
    id: 1n,
    proposer: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" as `0x${string}`,
    title: "Invest in ETH Staking Strategy",
    description: "Allocate 2 ETH to a liquid staking protocol to earn ~4% APY on our treasury.",
    destination: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" as `0x${string}`,
    fundAmount: 2000000000000000000n,
    votesFor: 4n,
    votesAgainst: 1n,
    deadline: BigInt(Math.floor(Date.now() / 1000) + 86400 * 2),
    status: 0,
    options: ["Approve", "Reject"],
  },
  {
    id: 2n,
    proposer: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" as `0x${string}`,
    title: "Stablecoin Yield Allocation",
    description: "Move 1.5 ETH into a USDC yield vault for stable 8% returns with minimal risk.",
    destination: "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC" as `0x${string}`,
    fundAmount: 1500000000000000000n,
    votesFor: 5n,
    votesAgainst: 0n,
    deadline: BigInt(Math.floor(Date.now() / 1000) - 3600),
    status: 1,
    options: ["Approve", "Reject"],
  },
  {
    id: 3n,
    proposer: "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC" as `0x${string}`,
    title: "NFT Portfolio Diversification",
    description: "Invest 3 ETH in blue-chip NFT collections as an alternative asset class.",
    destination: "0x90F79bf6EB2c4f870365E785982E1f101E93b906" as `0x${string}`,
    fundAmount: 3000000000000000000n,
    votesFor: 1n,
    votesAgainst: 4n,
    deadline: BigInt(Math.floor(Date.now() / 1000) - 7200),
    status: 2,
    options: ["Approve", "Reject"],
  },
];

export const MOCK_AI_RECS: Record<number, { text: string; riskScore: number; rewardScore: number }> = {
  1: {
    text: "ETH liquid staking is a well-established strategy with strong risk/reward balance. The protocol selected has a proven security track record and ~4% APY is realistic. Recommend approval with a moderate position size. Monitor validator performance and slashing risk.",
    riskScore: 28,
    rewardScore: 72,
  },
  2: {
    text: "Stablecoin yield strategies offer the best risk-adjusted returns for a conservative DAO treasury. 8% APY on USDC is achievable through reputable DeFi protocols. Smart contract risk is the primary concern. Strongly recommend approval.",
    riskScore: 18,
    rewardScore: 65,
  },
};

export const MOCK_MEMBERSHIP = { isMember: true, tokenId: 1n };
