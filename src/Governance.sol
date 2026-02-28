// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IMembership.sol";
import "./interfaces/IGovernance.sol";

contract Governance is Ownable, IGovernance {
    struct Proposal {
        uint256 id;
        address proposer;
        string title;
        string description;
        address destination;
        uint256 fundAmount;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 deadline;
        ProposalStatus status;
        string[] options;
    }

    IMembership public immutable membership;
    uint256 public proposalCount;
    uint256 public quorumBps;
    uint256 public votingDuration;
    uint256 public memberCount;

    mapping(uint256 => Proposal) private _proposals;
    // stored as optionIndex+1; 0 means not voted
    mapping(uint256 => mapping(address => uint256)) private _votes;
    mapping(uint256 => mapping(uint256 => uint256)) private _optionVotes;

    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string title, uint256 deadline);
    event VoteCast(uint256 indexed proposalId, address indexed voter, uint256 optionIndex, uint256 weight);
    event ProposalFinalized(uint256 indexed proposalId, ProposalStatus status);
    event MemberCountUpdated(uint256 newCount);

    error NotMember(address user);
    error ProposalNotFound(uint256 proposalId);
    error VotingClosed(uint256 proposalId);
    error AlreadyVoted(address voter, uint256 proposalId);
    error InvalidOption(uint256 optionIndex, uint256 maxOptions);
    error ProposalNotActive(uint256 proposalId);
    error InvalidAddress();
    error InvalidParams();
    error Unauthorized();

    modifier onlyMember() {
        if (!membership.checkMembership(msg.sender)) revert NotMember(msg.sender);
        _;
    }

    modifier proposalExists(uint256 proposalId) {
        if (proposalId == 0 || proposalId > proposalCount) revert ProposalNotFound(proposalId);
        _;
    }

    constructor(
        address initialOwner,
        address membershipContract,
        uint256 _quorumBps,
        uint256 _votingDuration
    ) Ownable(initialOwner) {
        if (membershipContract == address(0)) revert InvalidAddress();
        if (_quorumBps > 10_000) revert InvalidParams();
        membership = IMembership(membershipContract);
        quorumBps = _quorumBps;
        votingDuration = _votingDuration > 0 ? _votingDuration : 3 days;
    }

    function createProposal(
        string calldata title,
        string calldata description,
        string[] calldata options,
        address destination,
        uint256 fundAmount
    ) external onlyMember returns (uint256 proposalId) {
        if (bytes(title).length == 0) revert InvalidParams();
        if (options.length < 2) revert InvalidParams();

        unchecked { proposalId = ++proposalCount; }

        Proposal storage p = _proposals[proposalId];
        p.id = proposalId;
        p.proposer = msg.sender;
        p.title = title;
        p.description = description;
        p.destination = destination;
        p.fundAmount = fundAmount;
        p.deadline = block.timestamp + votingDuration;
        p.status = ProposalStatus.Active;
        p.options = options;

        emit ProposalCreated(proposalId, msg.sender, title, p.deadline);
    }

    function vote(uint256 proposalId, uint256 optionIndex)
        external
        onlyMember
        proposalExists(proposalId)
    {
        Proposal storage p = _proposals[proposalId];

        if (p.status != ProposalStatus.Active) revert ProposalNotActive(proposalId);
        if (block.timestamp > p.deadline) revert VotingClosed(proposalId);
        if (_votes[proposalId][msg.sender] != 0) revert AlreadyVoted(msg.sender, proposalId);
        if (optionIndex >= p.options.length) revert InvalidOption(optionIndex, p.options.length);

        uint256 weight = _votingWeight(msg.sender);

        _votes[proposalId][msg.sender] = optionIndex + 1;
        _optionVotes[proposalId][optionIndex] += weight;

        // option 0 = approve by convention
        if (optionIndex == 0) {
            p.votesFor += weight;
        } else {
            p.votesAgainst += weight;
        }

        emit VoteCast(proposalId, msg.sender, optionIndex, weight);
    }

    function finalizeProposal(uint256 proposalId) external proposalExists(proposalId) {
        Proposal storage p = _proposals[proposalId];

        if (p.status != ProposalStatus.Active) revert ProposalNotActive(proposalId);
        if (block.timestamp <= p.deadline) revert VotingClosed(proposalId);

        uint256 totalVotes = p.votesFor + p.votesAgainst;
        uint256 quorumNeeded = (memberCount * quorumBps) / 10_000;

        ProposalStatus result;
        if (totalVotes < quorumNeeded || p.votesFor <= p.votesAgainst) {
            result = ProposalStatus.Rejected;
        } else {
            result = ProposalStatus.Passed;
        }

        p.status = result;
        emit ProposalFinalized(proposalId, result);
    }

    function cancelProposal(uint256 proposalId) external proposalExists(proposalId) {
        Proposal storage p = _proposals[proposalId];
        if (msg.sender != p.proposer && msg.sender != owner()) revert Unauthorized();
        if (p.status != ProposalStatus.Active) revert ProposalNotActive(proposalId);

        p.status = ProposalStatus.Cancelled;
        emit ProposalFinalized(proposalId, ProposalStatus.Cancelled);
    }

    function getProposalStatus(uint256 proposalId)
        external view override proposalExists(proposalId) returns (ProposalStatus)
    {
        return _proposals[proposalId].status;
    }

    function getProposalFundAmount(uint256 proposalId)
        external view override proposalExists(proposalId) returns (uint256)
    {
        return _proposals[proposalId].fundAmount;
    }

    function getProposalDestination(uint256 proposalId)
        external view override proposalExists(proposalId) returns (address)
    {
        return _proposals[proposalId].destination;
    }

    function markExecuted(uint256 proposalId) external override proposalExists(proposalId) {
        Proposal storage p = _proposals[proposalId];
        require(p.status == ProposalStatus.Passed, "Proposal not passed");
        p.status = ProposalStatus.Executed;
        emit ProposalFinalized(proposalId, ProposalStatus.Executed);
    }

    function getProposal(uint256 proposalId)
        external view proposalExists(proposalId) returns (Proposal memory)
    {
        return _proposals[proposalId];
    }

    function getVote(uint256 proposalId, address voter) external view returns (uint256) {
        uint256 stored = _votes[proposalId][voter];
        return stored == 0 ? type(uint256).max : stored - 1; // type(uint256).max = not voted
    }

    function getOptionVotes(uint256 proposalId, uint256 optionIndex) external view returns (uint256) {
        return _optionVotes[proposalId][optionIndex];
    }

    function syncMemberCount(uint256 count) external onlyOwner {
        memberCount = count;
        emit MemberCountUpdated(count);
    }

    function setQuorum(uint256 newQuorumBps) external onlyOwner {
        if (newQuorumBps > 10_000) revert InvalidParams();
        quorumBps = newQuorumBps;
    }

    function setVotingDuration(uint256 newDuration) external onlyOwner {
        if (newDuration == 0) revert InvalidParams();
        votingDuration = newDuration;
    }

    function _votingWeight(address) internal pure returns (uint256) {
        return 1;
    }
}
