// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IGovernance {
    enum ProposalStatus {
        Active,
        Passed,
        Rejected,
        Executed,
        Cancelled
    }

    function getProposalStatus(uint256 proposalId) external view returns (ProposalStatus);
    function getProposalFundAmount(uint256 proposalId) external view returns (uint256);
    function getProposalDestination(uint256 proposalId) external view returns (address);
    function markExecuted(uint256 proposalId) external;
}
