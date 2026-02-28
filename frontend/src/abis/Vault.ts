export const VaultABI = [
  "function depositFunds() payable",
  "function withdrawFunds(uint256 amount)",
  "function getUserBalance(address user) view returns (uint256)",
  "function totalAssets() view returns (uint256)",
  "function setExecutor(address newExecutor)",
  "event FundsDeposited(address indexed user, uint256 amount)",
  "event FundsWithdrawn(address indexed user, uint256 amount)",
  "event FundsAllocated(address indexed destination, uint256 amount, uint256 indexed proposalId)",
] as const;
