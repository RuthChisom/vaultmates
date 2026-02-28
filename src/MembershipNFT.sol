// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IMembership.sol";

contract MembershipNFT is ERC721URIStorage, Ownable, IMembership {
    uint256 private _nextTokenId;
    mapping(address => uint256) private _memberTokenId;
    mapping(uint256 => bool) private _revoked;

    event MembershipGranted(address indexed member, uint256 indexed tokenId);
    event MembershipRevoked(address indexed member, uint256 indexed tokenId);

    error AlreadyMember(address user);
    error NotMember(address user);
    error SoulboundToken();

    constructor(address initialOwner)
        ERC721("VaultMates Membership", "VMEM")
        Ownable(initialOwner)
    {}

    function mintMembershipNFT(address user, string calldata uri) external onlyOwner {
        if (_memberTokenId[user] != 0) revert AlreadyMember(user);

        unchecked { ++_nextTokenId; }
        uint256 tokenId = _nextTokenId;

        _memberTokenId[user] = tokenId;
        _safeMint(user, tokenId);

        if (bytes(uri).length > 0) {
            _setTokenURI(tokenId, uri);
        }

        emit MembershipGranted(user, tokenId);
    }

    function revokeMembership(address user) external onlyOwner {
        uint256 tokenId = _memberTokenId[user];
        if (tokenId == 0) revert NotMember(user);

        _revoked[tokenId] = true;
        delete _memberTokenId[user];
        _burn(tokenId);

        emit MembershipRevoked(user, tokenId);
    }

    function checkMembership(address user) external view override returns (bool) {
        uint256 tokenId = _memberTokenId[user];
        return tokenId != 0 && !_revoked[tokenId];
    }

    function getMemberTokenId(address user) external view override returns (uint256) {
        return _memberTokenId[user];
    }

    function transferFrom(address, address, uint256) public pure override(ERC721, IERC721) {
        revert SoulboundToken();
    }

    function totalMinted() external view returns (uint256) {
        return _nextTokenId;
    }
}
