// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IMembership.sol";

contract AIRecommendation is Ownable {
    struct Recommendation {
        string text;
        uint8 riskScore;
        uint8 rewardScore;
        uint256 timestamp;
        address postedBy;
        bool exists;
    }

    IMembership public immutable membership;
    address public aiOracle;

    mapping(uint256 => Recommendation) private _recommendations;

    event RecommendationAdded(uint256 indexed proposalId, uint8 riskScore, uint8 rewardScore, address indexed postedBy);
    event OracleUpdated(address indexed newOracle);

    error NotOracle(address caller);
    error RecommendationExists(uint256 proposalId);
    error RecommendationNotFound(uint256 proposalId);
    error InvalidScore();
    error InvalidAddress();
    error EmptyText();

    modifier onlyOracle() {
        if (msg.sender != aiOracle && msg.sender != owner()) revert NotOracle(msg.sender);
        _;
    }

    constructor(address initialOwner, address membershipContract, address oracle) Ownable(initialOwner) {
        if (membershipContract == address(0)) revert InvalidAddress();
        membership = IMembership(membershipContract);
        aiOracle = oracle;
    }

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

    function getAIRecommendation(uint256 proposalId) external view returns (Recommendation memory) {
        if (!_recommendations[proposalId].exists) revert RecommendationNotFound(proposalId);
        return _recommendations[proposalId];
    }

    function getRecommendationText(uint256 proposalId) external view returns (string memory) {
        if (!_recommendations[proposalId].exists) revert RecommendationNotFound(proposalId);
        return _recommendations[proposalId].text;
    }

    function getScores(uint256 proposalId) external view returns (uint8 riskScore, uint8 rewardScore) {
        if (!_recommendations[proposalId].exists) revert RecommendationNotFound(proposalId);
        Recommendation storage r = _recommendations[proposalId];
        return (r.riskScore, r.rewardScore);
    }

    function hasRecommendation(uint256 proposalId) external view returns (bool) {
        return _recommendations[proposalId].exists;
    }

    function setAIOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert InvalidAddress();
        aiOracle = newOracle;
        emit OracleUpdated(newOracle);
    }
}
