// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IGovernance.sol";
import "./interfaces/IVault.sol";

/// @title VaultMates Automated Execution Module
/// @notice Module 5 – Automatically execute passed proposals and reallocate funds.
/// @dev Anyone may call executeProposal() once a proposal has status == Passed.
///      The contract calls Vault.allocateFunds() and then marks the proposal Executed
///      on the Governance contract. All executions are logged on-chain.
contract Executor is Ownable, ReentrancyGuard {
    // -------------------------------------------------------------------------
    // Types
    // -------------------------------------------------------------------------

    struct ExecutionLog {
        uint256 proposalId;
        address destination;
        uint256 executedAmount;
        uint256 timestamp;
        address executedBy;
    }

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    IGovernance public governance;
    IVault public vault;

    uint256 public executionCount;

    /// @notice logId → ExecutionLog
    mapping(uint256 => ExecutionLog) private _logs;

    /// @notice proposalId → logId (0 = not executed)
    mapping(uint256 => uint256) private _proposalLog;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event ProposalExecuted(
        uint256 indexed proposalId,
        address indexed destination,
        uint256 executedAmount,
        uint256 indexed logId,
        address executedBy
    );
    event ContractsUpdated(address governance, address vault);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error ProposalNotPassed(uint256 proposalId);
    error AlreadyExecuted(uint256 proposalId);
    error InvalidAddress();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(
        address initialOwner,
        address governanceContract,
        address vaultContract
    ) Ownable(initialOwner) {
        if (governanceContract == address(0) || vaultContract == address(0)) {
            revert InvalidAddress();
        }
        governance = IGovernance(governanceContract);
        vault = IVault(vaultContract);
    }

    // -------------------------------------------------------------------------
    // External – execution
    // -------------------------------------------------------------------------

    /// @notice Execute a passed proposal: move funds and log the action on-chain.
    /// @param proposalId  The ID of the proposal to execute.
    function executeProposal(uint256 proposalId) external nonReentrant {
        // Guard: must be Passed, not already Executed
        IGovernance.ProposalStatus status = governance.getProposalStatus(proposalId);
        if (status != IGovernance.ProposalStatus.Passed) {
            revert ProposalNotPassed(proposalId);
        }
        if (_proposalLog[proposalId] != 0) revert AlreadyExecuted(proposalId);

        address destination = governance.getProposalDestination(proposalId);
        uint256 amount = governance.getProposalFundAmount(proposalId);

        // Allocate funds through the vault
        vault.allocateFunds(destination, amount);

        // Mark executed on the governance contract
        governance.markExecuted(proposalId);

        // Log the execution
        unchecked {
            ++executionCount;
        }
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

    // -------------------------------------------------------------------------
    // External – log retrieval
    // -------------------------------------------------------------------------

    /// @notice Retrieve an execution log by its ID.
    function getExecutionLog(uint256 logId) external view returns (ExecutionLog memory) {
        return _logs[logId];
    }

    /// @notice Retrieve the execution log for a specific proposal.
    function getProposalLog(uint256 proposalId) external view returns (ExecutionLog memory) {
        uint256 logId = _proposalLog[proposalId];
        require(logId != 0, "Proposal not yet executed");
        return _logs[logId];
    }

    /// @notice Returns true if a proposal has already been executed.
    function isExecuted(uint256 proposalId) external view returns (bool) {
        return _proposalLog[proposalId] != 0;
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    /// @notice Update the Governance and Vault contract addresses.
    function setContracts(address governanceContract, address vaultContract) external onlyOwner {
        if (governanceContract == address(0) || vaultContract == address(0)) {
            revert InvalidAddress();
        }
        governance = IGovernance(governanceContract);
        vault = IVault(vaultContract);
        emit ContractsUpdated(governanceContract, vaultContract);
    }
}
