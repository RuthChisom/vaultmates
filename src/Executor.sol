// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IGovernance.sol";
import "./interfaces/IVault.sol";

contract Executor is Ownable, ReentrancyGuard {
    struct ExecutionLog {
        uint256 proposalId;
        address destination;
        uint256 executedAmount;
        uint256 timestamp;
        address executedBy;
    }

    IGovernance public governance;
    IVault public vault;
    uint256 public executionCount;

    mapping(uint256 => ExecutionLog) private _logs;
    mapping(uint256 => uint256) private _proposalLog;

    event ProposalExecuted(
        uint256 indexed proposalId,
        address indexed destination,
        uint256 executedAmount,
        uint256 indexed logId,
        address executedBy
    );
    event ContractsUpdated(address governance, address vault);

    error ProposalNotPassed(uint256 proposalId);
    error AlreadyExecuted(uint256 proposalId);
    error InvalidAddress();

    constructor(address initialOwner, address governanceContract, address vaultContract) Ownable(initialOwner) {
        if (governanceContract == address(0) || vaultContract == address(0)) revert InvalidAddress();
        governance = IGovernance(governanceContract);
        vault = IVault(vaultContract);
    }

    function executeProposal(uint256 proposalId) external nonReentrant {
        IGovernance.ProposalStatus status = governance.getProposalStatus(proposalId);
        if (status != IGovernance.ProposalStatus.Passed) revert ProposalNotPassed(proposalId);
        if (_proposalLog[proposalId] != 0) revert AlreadyExecuted(proposalId);

        address destination = governance.getProposalDestination(proposalId);
        uint256 amount = governance.getProposalFundAmount(proposalId);

        vault.allocateFunds(destination, amount);
        governance.markExecuted(proposalId);

        unchecked { ++executionCount; }
        uint256 logId = executionCount;
        _logs[logId] = ExecutionLog({
            proposalId: proposalId,
            destination: destination,
            executedAmount: amount,
            timestamp: block.timestamp,
            executedBy: msg.sender
        });
        _proposalLog[proposalId] = logId;

        emit ProposalExecuted(proposalId, destination, amount, logId, msg.sender);
    }

    function getExecutionLog(uint256 logId) external view returns (ExecutionLog memory) {
        return _logs[logId];
    }

    function getProposalLog(uint256 proposalId) external view returns (ExecutionLog memory) {
        uint256 logId = _proposalLog[proposalId];
        require(logId != 0, "Proposal not yet executed");
        return _logs[logId];
    }

    function isExecuted(uint256 proposalId) external view returns (bool) {
        return _proposalLog[proposalId] != 0;
    }

    function setContracts(address governanceContract, address vaultContract) external onlyOwner {
        if (governanceContract == address(0) || vaultContract == address(0)) revert InvalidAddress();
        governance = IGovernance(governanceContract);
        vault = IVault(vaultContract);
        emit ContractsUpdated(governanceContract, vaultContract);
    }
}
