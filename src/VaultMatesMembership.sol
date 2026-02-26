// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721}           from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable}          from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl}    from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable}         from "@openzeppelin/contracts/utils/Pausable.sol";

// -----------------------------------------------------------------------------
// IMembershipChecker — shared interface implemented by this contract
// and consumed by VaultMates (and any future protocol contract).
// -----------------------------------------------------------------------------

/**
 * @title  IMembershipChecker
 * @notice Minimal view interface for on-chain membership gate integration.
 * @dev    VaultMates.setMembershipContract() expects this interface.
 *         Any contract that calls isMember() should use staticcall so that
 *         this contract's view guarantee is enforced at the call site.
 */
interface IMembershipChecker {
    /**
     * @notice Returns true if `account` currently holds a valid membership.
     * @param  account  Address to test.
     * @return          True if the address owns at least one membership token
     *                  AND (when approval mode is on) was approved by the owner.
     */
    function isMember(address account) external view returns (bool);
}

// -----------------------------------------------------------------------------
// VaultMatesMembership
// -----------------------------------------------------------------------------

/**
 * @title  VaultMatesMembership
 * @author VaultMates Protocol
 * @notice ERC-721 NFT membership contract for the VaultMates protocol.
 *         Each address may hold exactly one token. The owner can require
 *         explicit approval before a minted token becomes an active membership.
 *
 * ── DESIGN DECISIONS ─────────────────────────────────────────────────────────
 *
 *  One-per-address invariant
 *    Enforced in _update() — the internal hook called by every mint, burn, and
 *    transfer. This is cheaper than a modifier on every public function and
 *    covers all transfer paths including safeTransferFrom.
 *
 *  Approval mode (optional)
 *    When approvalRequired == true, minting a token does NOT automatically
 *    make the holder a member. The owner (or APPROVER_ROLE) must call
 *    approveMember(). This supports KYC / allowlist workflows.
 *    When approvalRequired == false, holding the token IS membership.
 *
 *  Non-transferable option
 *    The owner can lock tokens as soulbound (non-transferable) at any time.
 *    Existing holders keep their tokens; future transfers are blocked.
 *
 *  isMember(address)
 *    Single view function satisfying IMembershipChecker. VaultMates uses this
 *    via staticcall in its onlyMember modifier. Returns true iff:
 *      (a) address holds a token, AND
 *      (b) if approvalRequired: address has been approved.
 *
 *  Role separation for DAO readiness
 *    DEFAULT_ADMIN_ROLE  — root; can grant/revoke all roles.
 *    APPROVER_ROLE       — can approve/revoke individual members; intended for
 *                          a DAO contract or multisig approval committee.
 *    MINTER_ROLE         — can mint on behalf of an address (airdrop / DAO grant).
 *                          Not needed for self-mint; any address can call mint().
 *
 *  Token IDs
 *    Sequential, starting at 1. tokenId 0 is intentionally skipped so that
 *    a zero tokenId can serve as a sentinel "no token" value in integrations.
 *
 * ── GAS OPTIMISATIONS ────────────────────────────────────────────────────────
 *  - _approved and _tokenOf mappings use uint256 (fits one slot; bool packs
 *    with nothing useful here, so uint256 is idiomatic for ERC-721 contexts).
 *  - isMember() is a two-SLOAD view: balanceOf (via ERC721 _balances) +
 *    _approved lookup. No array iteration.
 *  - _nextTokenId is a single storage slot incremented with unchecked arithmetic.
 *  - ERC721Enumerable is included for DAO snapshot tooling; callers that only
 *    need isMember() pay nothing extra (view functions cost no gas on-chain).
 *
 * ── SECURITY ─────────────────────────────────────────────────────────────────
 *  - One-per-address enforced at the _update() hook level (covers all paths).
 *  - renounceOwnership() blocked — prevents accidental permanent admin loss.
 *  - Pause blocks mint, approve, revoke, and transfer; emergency burn allowed.
 *  - approvalRequired and transferable flags are owner-controlled and emit events.
 */
contract VaultMatesMembership is
    ERC721,
    ERC721Enumerable,
    Ownable,
    AccessControl,
    Pausable,
    IMembershipChecker
{
    // =========================================================================
    // Roles
    // =========================================================================

    /**
     * @notice Approver role.
     * @dev    Holders can call approveMember() and revokeMember().
     *         Intended for a DAO approval committee or multisig.
     *         Assign via grantRole(APPROVER_ROLE, daoContract).
     */
    bytes32 public constant APPROVER_ROLE = keccak256("APPROVER_ROLE");

    /**
     * @notice Minter role.
     * @dev    Holders can call mintTo(address) to mint on behalf of others
     *         (airdrops, DAO membership grants). Not required for self-mint.
     */
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // =========================================================================
    // Storage
    // =========================================================================

    /// @dev Next token ID to mint. Starts at 1; 0 is reserved as "no token".
    uint256 private _nextTokenId;

    /**
     * @notice Whether minting a token requires subsequent owner/approver approval
     *         before isMember() returns true for that address.
     * @dev    When false: holding a token == membership (open mode).
     *         When true:  holding a token requires explicit approval (gated mode).
     */
    bool public approvalRequired;

    /**
     * @notice Whether tokens are non-transferable (soulbound).
     * @dev    When true, all transfers (except mint and burn) revert.
     *         Mint = transfer from address(0). Burn = transfer to address(0).
     */
    bool public transferable;

    /// @dev address => approved membership status. Only meaningful when approvalRequired == true.
    mapping(address => bool) private _approved;

    /// @dev address => tokenId owned. 0 means no token. Used for O(1) "does this address own a token?" checks.
    mapping(address => uint256) private _tokenOf;

    // =========================================================================
    // Events
    // =========================================================================

    /**
     * @notice Emitted when a membership token is minted.
     * @param  to      Recipient address.
     * @param  tokenId Token ID minted.
     */
    event MembershipMinted(address indexed to, uint256 indexed tokenId);

    /**
     * @notice Emitted when a membership token is burned.
     * @param  account Address whose token was burned.
     * @param  tokenId Token ID burned.
     */
    event MembershipBurned(address indexed account, uint256 indexed tokenId);

    /**
     * @notice Emitted when an address is approved as a member.
     * @param  account  Address approved.
     * @param  approver Address that approved (owner or APPROVER_ROLE).
     */
    event MemberApproved(address indexed account, address indexed approver);

    /**
     * @notice Emitted when an address has its membership approval revoked.
     * @param  account Address revoked.
     * @param  revoker Address that revoked.
     */
    event MemberRevoked(address indexed account, address indexed revoker);

    /**
     * @notice Emitted when the approvalRequired flag changes.
     * @param  required New value.
     */
    event ApprovalModeChanged(bool indexed required);

    /**
     * @notice Emitted when the transferable flag changes.
     * @param  transferable New value.
     */
    event TransferabilityChanged(bool indexed transferable);

    // =========================================================================
    // Custom Errors
    // =========================================================================

    /// @dev Caller already owns a membership token.
    error AlreadyMember(address account);

    /// @dev Target address already owns a membership token (for mintTo).
    error TargetAlreadyMember(address account);

    /// @dev Caller does not own a membership token.
    error NotTokenHolder(address account);

    /// @dev Caller is not authorised to perform this action.
    error Unauthorized();

    /// @dev Token transfer is blocked because transferable == false.
    error TransferLocked();

    /// @dev renounceOwnership is permanently disabled.
    error RenounceOwnershipDisabled();

    /// @dev address(0) supplied where a real address is required.
    error ZeroAddress();

    // =========================================================================
    // Constructor
    // =========================================================================

    /**
     * @notice Deploy VaultMatesMembership.
     * @param  initialOwner      Receives Ownable ownership and DEFAULT_ADMIN_ROLE.
     *                           Should be a multisig or Timelock in production.
     * @param  _approvalRequired Initial value for approvalRequired flag.
     * @param  _transferable     Initial value for transferable flag.
     */
    constructor(
        address initialOwner,
        bool    _approvalRequired,
        bool    _transferable
    )
        ERC721("VaultMates Membership", "VMM")
        Ownable(initialOwner)
    {
        if (initialOwner == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(APPROVER_ROLE,      initialOwner);
        _grantRole(MINTER_ROLE,        initialOwner);

        approvalRequired = _approvalRequired;
        transferable     = _transferable;

        // Consume tokenId 0 so the first real token is ID 1.
        // _nextTokenId starts at 0; first mint increments to 1.
        _nextTokenId = 1;
    }

    // =========================================================================
    // External — Minting
    // =========================================================================

    /**
     * @notice Mint a membership token to the caller.
     * @dev    Any address without an existing token can call this (open mint).
     *         If approvalRequired == true, the caller is NOT yet a member until
     *         approveMember() is called by an owner or APPROVER_ROLE holder.
     *         Reverts if the caller already holds a token.
     *         Reverts when paused.
     */
    function mint() external whenNotPaused {
        _mintMembership(msg.sender);
    }

    /**
     * @notice Mint a membership token to an arbitrary address.
     * @dev    Restricted to MINTER_ROLE. Useful for airdrops and DAO grants.
     *         If approvalRequired == true, the recipient is not yet a member
     *         until approveMember() is called.
     * @param  to Recipient address. Must not already hold a token.
     */
    function mintTo(address to) external onlyRole(MINTER_ROLE) whenNotPaused {
        if (to == address(0)) revert ZeroAddress();
        _mintMembership(to);
    }

    // =========================================================================
    // External — Burning
    // =========================================================================

    /**
     * @notice Burn the caller's own membership token.
     * @dev    Clears approval status for the caller. Does not require
     *         whenNotPaused — users must always be able to exit.
     *         Reverts if the caller holds no token.
     */
    function burn() external {
        uint256 tokenId = _tokenOf[msg.sender];
        if (tokenId == 0) revert NotTokenHolder(msg.sender);
        _burnMembership(msg.sender, tokenId);
    }

    /**
     * @notice Burn any address's membership token.
     * @dev    Restricted to owner. Used for enforcement / compliance.
     *         Clears the address's approval status.
     *         Does not require whenNotPaused — admin revocation must always work.
     * @param  account Address whose token to burn.
     */
    function burnFrom(address account) external onlyOwner {
        uint256 tokenId = _tokenOf[account];
        if (tokenId == 0) revert NotTokenHolder(account);
        _burnMembership(account, tokenId);
    }

    // =========================================================================
    // External — Approval Management
    // =========================================================================

    /**
     * @notice Approve an address as an active member.
     * @dev    Only meaningful when approvalRequired == true.
     *         Can be called by owner or any APPROVER_ROLE holder.
     *         The address must already hold a token before it can be approved.
     *         Reverts when paused.
     * @param  account Address to approve.
     */
    function approveMember(address account)
        external
        whenNotPaused
        onlyApprover
    {
        if (_tokenOf[account] == 0) revert NotTokenHolder(account);
        _approved[account] = true;
        emit MemberApproved(account, msg.sender);
    }

    /**
     * @notice Approve multiple addresses in a single transaction.
     * @dev    Restricted to owner or APPROVER_ROLE. Gas-efficient batch path.
     *         Silently skips addresses with no token (no revert) to allow
     *         partial lists without halting.
     * @param  accounts Array of addresses to approve.
     */
    function approveMemberBatch(address[] calldata accounts)
        external
        whenNotPaused
        onlyApprover
    {
        uint256 len = accounts.length;
        for (uint256 i; i < len; ) {
            address account = accounts[i];
            if (_tokenOf[account] != 0) {
                _approved[account] = true;
                emit MemberApproved(account, msg.sender);
            }
            unchecked { ++i; }
        }
    }

    /**
     * @notice Revoke an address's active membership approval.
     * @dev    Does NOT burn the token. The address keeps its NFT but
     *         isMember() returns false until re-approved.
     *         Only meaningful when approvalRequired == true.
     *         Restricted to owner or APPROVER_ROLE.
     * @param  account Address to revoke.
     */
    function revokeMember(address account)
        external
        whenNotPaused
        onlyApprover
    {
        _approved[account] = false;
        emit MemberRevoked(account, msg.sender);
    }

    /**
     * @notice Revoke membership approval for multiple addresses.
     * @dev    Restricted to owner or APPROVER_ROLE.
     * @param  accounts Array of addresses to revoke.
     */
    function revokeMemberBatch(address[] calldata accounts)
        external
        whenNotPaused
        onlyApprover
    {
        uint256 len = accounts.length;
        for (uint256 i; i < len; ) {
            _approved[accounts[i]] = false;
            emit MemberRevoked(accounts[i], msg.sender);
            unchecked { ++i; }
        }
    }

    // =========================================================================
    // External — Owner Configuration
    // =========================================================================

    /**
     * @notice Toggle whether minting requires subsequent owner approval.
     * @dev    Changing from true -> false immediately makes all token holders
     *         active members (approval state is ignored when flag is off).
     *         Changing from false -> true does NOT retroactively revoke anyone;
     *         existing holders remain members unless explicitly revoked.
     * @param  required New value for approvalRequired.
     */
    function setApprovalRequired(bool required) external onlyOwner {
        approvalRequired = required;
        emit ApprovalModeChanged(required);
    }

    /**
     * @notice Toggle whether tokens can be transferred between addresses.
     * @dev    Setting to false makes all tokens soulbound from that point on.
     *         Existing holders keep their tokens; only future transfers are blocked.
     *         Mint (from address(0)) and burn (to address(0)) are always allowed.
     * @param  _transferable New value for transferable.
     */
    function setTransferable(bool _transferable) external onlyOwner {
        transferable = _transferable;
        emit TransferabilityChanged(_transferable);
    }

    /**
     * @notice Pause mint, approve, revoke, and transfer operations.
     * @dev    burn() and burnFrom() intentionally remain available when paused.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract and resume normal operations.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Disabled — prevents accidental permanent loss of admin access.
     * @dev    Use transferOwnership() to migrate to a Timelock or DAO.
     */
    function renounceOwnership() public view override onlyOwner {
        revert RenounceOwnershipDisabled();
    }

    // =========================================================================
    // External — IMembershipChecker (VaultMates integration)
    // =========================================================================

    /**
     * @notice Returns true if `account` is an active member.
     * @dev    Called by VaultMates.onlyMember via staticcall.
     *         Logic:
     *           1. Account must hold a token (_tokenOf[account] != 0).
     *           2. If approvalRequired == true, account must also be approved.
     *         Two SLOADs in the worst case; one if the token check fails early.
     * @param  account Address to query.
     * @return         True if account is an active member.
     */
    function isMember(address account) external view override returns (bool) {
        if (_tokenOf[account] == 0) return false;           // SLOAD 1: no token
        if (!approvalRequired)      return true;            // SLOAD 2: flag check
        return _approved[account];                          // SLOAD 3: approval
    }

    // =========================================================================
    // External — View / Enumeration
    // =========================================================================

    /**
     * @notice Returns the token ID owned by `account`, or 0 if none.
     * @param  account Address to query.
     * @return         Token ID, or 0.
     */
    function tokenOf(address account) external view returns (uint256) {
        return _tokenOf[account];
    }

    /**
     * @notice Returns whether `account` has been explicitly approved.
     * @dev    Always check approvalRequired first — this value is only
     *         meaningful when approvalRequired == true.
     * @param  account Address to query.
     * @return         True if account has been approved.
     */
    function isApproved(address account) external view returns (bool) {
        return _approved[account];
    }

    /**
     * @notice Returns the next token ID that will be minted.
     * @dev    Useful for off-chain indexers predicting the upcoming token ID.
     */
    function nextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    /**
     * @notice Returns the total number of active (non-burned) tokens.
     * @dev    Delegates to ERC721Enumerable.totalSupply().
     */
    function totalMembers() external view returns (uint256) {
        return totalSupply();
    }

    // =========================================================================
    // Internal — Core Mint / Burn Logic
    // =========================================================================

    /**
     * @dev Internal mint: increments _nextTokenId, calls _safeMint.
     *      _update() (below) handles the one-per-address check and _tokenOf.
     */
    function _mintMembership(address to) internal {
        uint256 tokenId;
        unchecked { tokenId = _nextTokenId++; }
        _safeMint(to, tokenId);
        emit MembershipMinted(to, tokenId);
    }

    /**
     * @dev Internal burn: calls _burn, clears approval state.
     *      _update() (below) handles clearing _tokenOf.
     */
    function _burnMembership(address account, uint256 tokenId) internal {
        _burn(tokenId);
        delete _approved[account];
        emit MembershipBurned(account, tokenId);
    }

    // =========================================================================
    // Internal — ERC721 Hooks
    // =========================================================================

    /**
     * @dev Override _update — the single internal hook that all ERC-721
     *      state transitions (mint, burn, transfer) flow through in OZ v5.
     *
     *      Responsibilities:
     *        1. One-per-address: reject if `to` already holds a token (mint/transfer).
     *        2. Transferability: reject non-mint, non-burn transfers when locked.
     *        3. Pause: reject all state changes when paused (except burn).
     *        4. _tokenOf bookkeeping: update forward mapping on every transition.
     *
     *      Why here and not in separate before/after hooks?
     *        OZ v5 consolidates into _update(). A single override is cleaner,
     *        avoids hook ordering bugs, and is cheaper (one call frame).
     *
     * @param  to      Recipient (address(0) for burns).
     * @param  tokenId Token being moved.
     * @param  auth    Authorisation address (checked by OZ internals).
     * @return         Previous owner (returned by super._update).
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    )
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        address from = _ownerOf(tokenId); // address(0) on mint

        bool isMint = (from == address(0));
        bool isBurn = (to   == address(0));

        // ── Pause check ───────────────────────────────────────────────────────
        // Burns bypass pause so users can always exit and admins can enforce.
        if (paused() && !isBurn) revert EnforcedPause();

        // ── Transferability check ─────────────────────────────────────────────
        // Mints and burns are always allowed regardless of the transferable flag.
        if (!transferable && !isMint && !isBurn) revert TransferLocked();

        // ── One-per-address check ─────────────────────────────────────────────
        // `to` must not already own a token (applies to mints and transfers).
        if (!isBurn && _tokenOf[to] != 0) {
            if (isMint) revert AlreadyMember(to);
            revert TargetAlreadyMember(to);
        }

        // ── _tokenOf bookkeeping ──────────────────────────────────────────────
        if (!isMint) delete _tokenOf[from]; // clear sender on transfer or burn
        if (!isBurn) _tokenOf[to] = tokenId; // set recipient on mint or transfer

        // ── Delegate to OZ chain (handles ERC721 + ERC721Enumerable state) ────
        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Required override: ERC721 and ERC721Enumerable both implement this.
     */
    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    // =========================================================================
    // Internal — Modifiers
    // =========================================================================

    /**
     * @dev Restricts to owner or any APPROVER_ROLE holder.
     *      Cheaper than writing onlyRole(APPROVER_ROLE) when owner-equivalence
     *      is also needed, and avoids granting the owner APPROVER_ROLE explicitly
     *      (though the constructor does grant it for convenience).
     */
    modifier onlyApprover() {
        if (msg.sender != owner() && !hasRole(APPROVER_ROLE, msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    // =========================================================================
    // Internal — EIP-165
    // =========================================================================

    /**
     * @dev EIP-165: advertise ERC721, ERC721Enumerable, AccessControl,
     *      and IMembershipChecker interfaces.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return
            interfaceId == type(IMembershipChecker).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
