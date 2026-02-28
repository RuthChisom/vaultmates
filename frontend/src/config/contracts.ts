export const CONTRACTS = {
  membershipNFT:    (process.env.NEXT_PUBLIC_MEMBERSHIP_NFT_ADDRESS ?? "") as `0x${string}`,
  vault:            (process.env.NEXT_PUBLIC_VAULT_ADDRESS ?? "") as `0x${string}`,
  governance:       (process.env.NEXT_PUBLIC_GOVERNANCE_ADDRESS ?? "") as `0x${string}`,
  aiRecommendation: (process.env.NEXT_PUBLIC_AI_RECOMMENDATION_ADDRESS ?? "") as `0x${string}`,
  executor:         (process.env.NEXT_PUBLIC_EXECUTOR_ADDRESS ?? "") as `0x${string}`,
};

export const OWNER_ADDRESS = (process.env.NEXT_PUBLIC_OWNER_ADDRESS ?? "").toLowerCase();

// If any address is missing, the app shows mock data
export const DEMO_MODE = Object.values(CONTRACTS).some((a) => !a || a === "0x");
