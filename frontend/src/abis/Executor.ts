export const ExecutorABI = [
  "function executeProposal(uint256 proposalId)",
  "function isExecuted(uint256 proposalId) view returns (bool)",
  "function getProposalLog(uint256 proposalId) view returns (tuple(uint256 proposalId, address destination, uint256 executedAmount, uint256 timestamp, address executedBy))",
  "function executionCount() view returns (uint256)",
  "event ProposalExecuted(uint256 indexed proposalId, address indexed destination, uint256 executedAmount, uint256 indexed logId, address executedBy)",
] as const;
