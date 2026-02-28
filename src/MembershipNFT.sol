// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IMembership.sol";

/// @title VaultMates Membership NFT
/// @notice Module 1 – User Onboarding & Membership
/// @dev Each wallet can hold at most one membership NFT. The owner (DAO admin or
///      a trusted onboarding contract) mints tokens. Token transfers are intentionally
///      blocked so that membership is non-transferable (soulbound).
contract MembershipNFT is ERC721URIStorage, Ownable, IMembership {
    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    uint256 private _nextTokenId;

    /// @notice Maps member address → token ID (1-indexed; 0 means no membership)
    mapping(address => uint256) private _memberTokenId;

    /// @notice Tracks whether a token ID has been burned / revoked
    mapping(uint256 => bool) private _revoked;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a new membership NFT is minted
    event MembershipGranted(address indexed member, uint256 indexed tokenId);

    /// @notice Emitted when a membership NFT is revoked
    event MembershipRevoked(address indexed member, uint256 indexed tokenId);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error AlreadyMember(address user);
    error NotMember(address user);
    error SoulboundToken();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address initialOwner)
        ERC721("VaultMates Membership", "VMEM")
        Ownable(initialOwner)
    {}

    // -------------------------------------------------------------------------
    // External – minting / revoking
    // -------------------------------------------------------------------------

    /// @notice Mint a membership NFT to `user`.  Reverts if the user is already a member.
    /// @param user  The address to onboard.
    /// @param uri   Optional metadata URI (IPFS / offchain JSON).
    function mintMembershipNFT(address user, string calldata uri) external onlyOwner {
        if (_memberTokenId[user] != 0) revert AlreadyMember(user);

        unchecked {
            ++_nextTokenId;
        }
        uint256 tokenId = _nextTokenId;

        _memberTokenId[user] = tokenId;
        _safeMint(user, tokenId);

        if (bytes(uri).length > 0) {
            _setTokenURI(tokenId, uri);
        }

        emit MembershipGranted(user, tokenId);
    }

    /// @notice Revoke (burn) a member's NFT.
    /// @param user  The member whose token should be revoked.
    function revokeMembership(address user) external onlyOwner {
        uint256 tokenId = _memberTokenId[user];
        if (tokenId == 0) revert NotMember(user);

        _revoked[tokenId] = true;
        delete _memberTokenId[user];
        _burn(tokenId);

        emit MembershipRevoked(user, tokenId);
    }

    // -------------------------------------------------------------------------
    // IMembership implementation
    // -------------------------------------------------------------------------

    /// @inheritdoc IMembership
    function checkMembership(address user) external view override returns (bool) {
        uint256 tokenId = _memberTokenId[user];
        return tokenId != 0 && !_revoked[tokenId];
    }

    /// @inheritdoc IMembership
    function getMemberTokenId(address user) external view override returns (uint256) {
        return _memberTokenId[user];
    }

    // -------------------------------------------------------------------------
    // Soulbound – block all transfers
    // -------------------------------------------------------------------------

    /// @dev Override to make tokens non-transferable (soulbound).
    function transferFrom(address, address, uint256) public pure override(ERC721, IERC721) {
        revert SoulboundToken();
    }

    // -------------------------------------------------------------------------
    // View helpers
    // -------------------------------------------------------------------------

    function totalMinted() external view returns (uint256) {
        return _nextTokenId;
    }
}
