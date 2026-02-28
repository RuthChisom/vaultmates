// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IMembership.sol";

/// @title VaultMates AI Recommendation Module
/// @notice Module 4 – Store and retrieve Claude AI analysis for proposals on-chain.
/// @dev The off-chain Claude pipeline posts recommendation text + a numeric risk score
///      through a trusted AI oracle address set by the owner. Members can read the
///      recommendation before casting their votes.
contract AIRecommendation is Ownable {
    // -------------------------------------------------------------------------
    // Types
    // -------------------------------------------------------------------------

    struct Recommendation {
        string text;          // Full recommendation text from Claude AI
        uint8 riskScore;      // 0–100: 0 = low risk, 100 = extremely high risk
        uint8 rewardScore;    // 0–100: 0 = low reward potential, 100 = max
        uint256 timestamp;    // When the recommendation was posted
        address postedBy;     // AI oracle address
        bool exists;
    }

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    IMembership public immutable membership;

    /// @notice Trusted address that may post AI recommendations (the off-chain oracle)
    address public aiOracle;

    /// @notice proposalId → recommendation
    mapping(uint256 => Recommendation) private _recommendations;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event RecommendationAdded(
        uint256 indexed proposalId,
        uint8 riskScore,
        uint8 rewardScore,
        address indexed postedBy
    );
    event OracleUpdated(address indexed newOracle);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error NotOracle(address caller);
    error RecommendationExists(uint256 proposalId);
    error RecommendationNotFound(uint256 proposalId);
    error InvalidScore();
    error InvalidAddress();
    error EmptyText();

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyOracle() {
        if (msg.sender != aiOracle && msg.sender != owner()) revert NotOracle(msg.sender);
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address initialOwner, address membershipContract, address oracle)
        Ownable(initialOwner)
    {
        if (membershipContract == address(0)) revert InvalidAddress();
        membership = IMembership(membershipContract);
        aiOracle = oracle; // oracle may be address(0) initially
    }

    // -------------------------------------------------------------------------
    // External – write
    // -------------------------------------------------------------------------

    /// @notice Post an AI recommendation for a proposal.
    /// @param proposalId   The proposal being analysed.
    /// @param text         Full natural-language recommendation from Claude AI.
    /// @param riskScore    Risk score 0–100.
    /// @param rewardScore  Expected reward score 0–100.
    function addAIRecommendation(
        uint256 proposalId,
        string calldata text,
        uint8 riskScore,
        uint8 rewardScore
    ) external onlyOracle {
        if (bytes(text).length == 0) revert EmptyText();
        if (riskScore > 100 || rewardScore > 100) revert InvalidScore();
        if (_recommendations[proposalId].exists) revert RecommendationExists(proposalId);

        _recommendations[proposalId] = Recommendation({
            text: text,
            riskScore: riskScore,
            rewardScore: rewardScore,
            timestamp: block.timestamp,
            postedBy: msg.sender,
            exists: true
        });

        emit RecommendationAdded(proposalId, riskScore, rewardScore, msg.sender);
    }

    /// @notice Update (overwrite) an existing recommendation.
    ///         Useful when Claude provides a revised analysis.
    function updateAIRecommendation(
        uint256 proposalId,
        string calldata text,
        uint8 riskScore,
        uint8 rewardScore
    ) external onlyOracle {
        if (bytes(text).length == 0) revert EmptyText();
        if (riskScore > 100 || rewardScore > 100) revert InvalidScore();
        if (!_recommendations[proposalId].exists) revert RecommendationNotFound(proposalId);

        Recommendation storage r = _recommendations[proposalId];
        r.text = text;
        r.riskScore = riskScore;
        r.rewardScore = rewardScore;
        r.timestamp = block.timestamp;
        r.postedBy = msg.sender;

        emit RecommendationAdded(proposalId, riskScore, rewardScore, msg.sender);
    }

    // -------------------------------------------------------------------------
    // External – read
    // -------------------------------------------------------------------------

    /// @notice Retrieve the full recommendation for a proposal.
    function getAIRecommendation(uint256 proposalId)
        external
        view
        returns (Recommendation memory)
    {
        if (!_recommendations[proposalId].exists) revert RecommendationNotFound(proposalId);
        return _recommendations[proposalId];
    }

    /// @notice Quick accessor for just the recommendation text.
    function getRecommendationText(uint256 proposalId) external view returns (string memory) {
        if (!_recommendations[proposalId].exists) revert RecommendationNotFound(proposalId);
        return _recommendations[proposalId].text;
    }

    /// @notice Quick accessor for risk + reward scores.
    function getScores(uint256 proposalId)
        external
        view
        returns (uint8 riskScore, uint8 rewardScore)
    {
        if (!_recommendations[proposalId].exists) revert RecommendationNotFound(proposalId);
        Recommendation storage r = _recommendations[proposalId];
        return (r.riskScore, r.rewardScore);
    }

    /// @notice Returns true if a recommendation exists for the given proposal.
    function hasRecommendation(uint256 proposalId) external view returns (bool) {
        return _recommendations[proposalId].exists;
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    /// @notice Update the trusted AI oracle address.
    function setAIOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert InvalidAddress();
        aiOracle = newOracle;
        emit OracleUpdated(newOracle);
    }
}
