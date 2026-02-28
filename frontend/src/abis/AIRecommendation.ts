export const AIRecommendationABI = [
  "function addAIRecommendation(uint256 proposalId, string text, uint8 riskScore, uint8 rewardScore)",
  "function updateAIRecommendation(uint256 proposalId, string text, uint8 riskScore, uint8 rewardScore)",
  "function getAIRecommendation(uint256 proposalId) view returns (tuple(string text, uint8 riskScore, uint8 rewardScore, uint256 timestamp, address postedBy, bool exists))",
  "function hasRecommendation(uint256 proposalId) view returns (bool)",
  "function setAIOracle(address newOracle)",
  "function aiOracle() view returns (address)",
  "event RecommendationAdded(uint256 indexed proposalId, uint8 riskScore, uint8 rewardScore, address indexed postedBy)",
] as const;
