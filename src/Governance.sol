// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IMembership.sol";
import "./interfaces/IGovernance.sol";

/// @title VaultMates Governance – Proposal Creation & Voting
/// @notice Module 3 – Let members propose investment decisions and vote collaboratively.
/// @dev Voting weight = 1 vote per membership NFT (one member, one vote).
///      Upgrade to token-weighted or reputation-weighted by modifying _votingWeight().
contract Governance is Ownable, IGovernance {
    // -------------------------------------------------------------------------
    // Types
    // -------------------------------------------------------------------------

    struct Proposal {
        uint256 id;
        address proposer;
        string title;
        string description;
        /// @notice Destination address for fund allocation if proposal passes
        address destination;
        /// @notice Amount of ETH (wei) to allocate
        uint256 fundAmount;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 deadline;        // block.timestamp
        ProposalStatus status;
        string[] options;        // e.g. ["Approve", "Reject", "Abstain"]
    }

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    IMembership public immutable membership;

    uint256 public proposalCount;

    /// @notice Quorum: minimum % of total members that must vote (in basis points, e.g. 5000 = 50%)
    uint256 public quorumBps;

    /// @notice Voting duration in seconds (default 3 days)
    uint256 public votingDuration;

    mapping(uint256 => Proposal) private _proposals;

    /// @notice proposalId → voter → optionIndex+1 (0 = has not voted)
    mapping(uint256 => mapping(address => uint256)) private _votes;

    /// @notice proposalId → optionIndex → vote count
    mapping(uint256 => mapping(uint256 => uint256)) private _optionVotes;

    /// @notice Tracks total number of members (incremented on each membership grant event
    ///         via the membership contract owner calling syncMemberCount)
    uint256 public memberCount;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string title,
        uint256 deadline
    );
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        uint256 optionIndex,
        uint256 weight
    );
    event ProposalFinalized(uint256 indexed proposalId, ProposalStatus status);
    event MemberCountUpdated(uint256 newCount);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error NotMember(address user);
    error ProposalNotFound(uint256 proposalId);
    error VotingClosed(uint256 proposalId);
    error AlreadyVoted(address voter, uint256 proposalId);
    error InvalidOption(uint256 optionIndex, uint256 maxOptions);
    error ProposalNotActive(uint256 proposalId);
    error InvalidAddress();
    error InvalidParams();

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyMember() {
        if (!membership.checkMembership(msg.sender)) revert NotMember(msg.sender);
        _;
    }

    modifier proposalExists(uint256 proposalId) {
        if (proposalId == 0 || proposalId > proposalCount) revert ProposalNotFound(proposalId);
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

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

    // -------------------------------------------------------------------------
    // External – proposal lifecycle
    // -------------------------------------------------------------------------

    /// @notice Create a new proposal.
    /// @param title        Short human-readable title.
    /// @param description  Full proposal text / IPFS CID.
    /// @param options      Voting options (e.g. ["Approve", "Reject"]).
    /// @param destination  Where funds go if proposal passes.
    /// @param fundAmount   How much ETH (wei) to allocate.
    function createProposal(
        string calldata title,
        string calldata description,
        string[] calldata options,
        address destination,
        uint256 fundAmount
    ) external onlyMember returns (uint256 proposalId) {
        if (bytes(title).length == 0) revert InvalidParams();
        if (options.length < 2) revert InvalidParams();

        unchecked {
            proposalId = ++proposalCount;
        }

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

    /// @notice Cast a vote on an active proposal.
    /// @param proposalId   The proposal to vote on.
    /// @param optionIndex  The index into the proposal's options array.
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

        // Record vote (store optionIndex+1 so 0 == "not voted")
        _votes[proposalId][msg.sender] = optionIndex + 1;
        _optionVotes[proposalId][optionIndex] += weight;

        // For simple approve/reject tally (option 0 = approve by convention)
        if (optionIndex == 0) {
            p.votesFor += weight;
        } else {
            p.votesAgainst += weight;
        }

        emit VoteCast(proposalId, msg.sender, optionIndex, weight);
    }

    /// @notice Finalize a proposal after its deadline.
    ///         Anyone can call this once the deadline has passed.
    function finalizeProposal(uint256 proposalId) external proposalExists(proposalId) {
        Proposal storage p = _proposals[proposalId];

        if (p.status != ProposalStatus.Active) revert ProposalNotActive(proposalId);
        if (block.timestamp <= p.deadline) revert VotingClosed(proposalId); // still open

        uint256 totalVotes = p.votesFor + p.votesAgainst;
        uint256 quorumNeeded = (memberCount * quorumBps) / 10_000;

        ProposalStatus result;
        if (totalVotes < quorumNeeded) {
            result = ProposalStatus.Rejected; // failed quorum
        } else if (p.votesFor > p.votesAgainst) {
            result = ProposalStatus.Passed;
        } else {
            result = ProposalStatus.Rejected;
        }

        p.status = result;
        emit ProposalFinalized(proposalId, result);
    }

    /// @notice Cancel an active proposal (proposer or owner only).
    function cancelProposal(uint256 proposalId) external proposalExists(proposalId) {
        Proposal storage p = _proposals[proposalId];
        if (msg.sender != p.proposer && msg.sender != owner()) revert Unauthorized();
        if (p.status != ProposalStatus.Active) revert ProposalNotActive(proposalId);

        p.status = ProposalStatus.Cancelled;
        emit ProposalFinalized(proposalId, ProposalStatus.Cancelled);
    }

    // -------------------------------------------------------------------------
    // IGovernance implementation
    // -------------------------------------------------------------------------

    /// @inheritdoc IGovernance
    function getProposalStatus(uint256 proposalId)
        external
        view
        override
        proposalExists(proposalId)
        returns (ProposalStatus)
    {
        return _proposals[proposalId].status;
    }

    /// @inheritdoc IGovernance
    function getProposalFundAmount(uint256 proposalId)
        external
        view
        override
        proposalExists(proposalId)
        returns (uint256)
    {
        return _proposals[proposalId].fundAmount;
    }

    /// @inheritdoc IGovernance
    function getProposalDestination(uint256 proposalId)
        external
        view
        override
        proposalExists(proposalId)
        returns (address)
    {
        return _proposals[proposalId].destination;
    }

    /// @inheritdoc IGovernance
    /// @dev Called by the Executor after it has moved funds.
    function markExecuted(uint256 proposalId) external override proposalExists(proposalId) {
        // Only Executor (set by owner) should call this; for simplicity we
        // allow the owner to call it directly as well.
        Proposal storage p = _proposals[proposalId];
        require(p.status == ProposalStatus.Passed, "Proposal not passed");
        p.status = ProposalStatus.Executed;
        emit ProposalFinalized(proposalId, ProposalStatus.Executed);
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    function getProposal(uint256 proposalId)
        external
        view
        proposalExists(proposalId)
        returns (Proposal memory)
    {
        return _proposals[proposalId];
    }

    function getVote(uint256 proposalId, address voter) external view returns (uint256) {
        uint256 stored = _votes[proposalId][voter];
        return stored == 0 ? type(uint256).max : stored - 1; // max = not voted
    }

    function getOptionVotes(uint256 proposalId, uint256 optionIndex)
        external
        view
        returns (uint256)
    {
        return _optionVotes[proposalId][optionIndex];
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    /// @notice Update the member count (called by owner when membership changes).
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

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    /// @dev Returns the voting weight for `voter`. Currently 1 per member.
    ///      Override here to introduce token-weighted or reputation-weighted voting.
    function _votingWeight(address /*voter*/) internal pure returns (uint256) {
        return 1;
    }

    error Unauthorized();
}
