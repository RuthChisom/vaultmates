export const MembershipNFTABI = [
  "function mintMembershipNFT(address user, string uri)",
  "function revokeMembership(address user)",
  "function checkMembership(address user) view returns (bool)",
  "function getMemberTokenId(address user) view returns (uint256)",
  "function totalMinted() view returns (uint256)",
  "event MembershipGranted(address indexed member, uint256 indexed tokenId)",
  "event MembershipRevoked(address indexed member, uint256 indexed tokenId)",
] as const;
