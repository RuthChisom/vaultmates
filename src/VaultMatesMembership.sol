// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721}        from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable}       from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable}      from "@openzeppelin/contracts/utils/Pausable.sol";

// =============================================================================
// IMembershipChecker
// =============================================================================

/**
 * @title  IMembershipChecker
 * @notice Minimal view interface consumed by VaultMates (and any future
 *         protocol contract) to gate access on active membership status.
 * @dev    VaultMates.setMembershipContract() expects exactly this interface.
 *         Callers invoke isMember() via staticcall so that the view guarantee
 *         is enforced at the call site regardless of future overrides.
 */
interface IMembershipChecker {
    /**
     * @notice Returns true when `account` is an active member.
     * @param  account  Address to test.
     * @return          True if `account` holds a token AND (when
     *                  approvalRequired == true) has been explicitly approved.
     */
    function isMember(address account) external view returns (bool);
}

// =============================================================================
// VaultMatesMembership
// =============================================================================

/**
 * @title  VaultMatesMembership
 * @author VaultMates Protocol
 * @notice ERC-721 NFT membership contract for the VaultMates protocol.
 *         Each address may hold exactly one token. The owner may optionally
 *         require explicit approval before a minted token grants active
 *         membership. Exposes isMember(address) to satisfy IMembershipChecker
 *         so VaultMates can gate deposits without knowing implementation details.
 *
 * ---- MODES ------------------------------------------------------------------
 *
 *   Open mode   (approvalRequired == false, default)
 *     Minting is self-service. Holding a token immediately means isMember()
 *     returns true. No further action required.
 *
 *   Gated mode  (approvalRequired == true)
 *     Minting issues the NFT but the holder is NOT yet a member. An address
 *     with APPROVER_ROLE must call approveMember() before isMember() returns
 *     true. Supports KYC / allowlist / DAO-vote workflows.
 *
 * ---- OWNABLE ACCESS CONTROL -------------------------------------------------
 *
 *   Single privileged owner governs all administrative functions:
 *     pause() / unpause()        Emergency halt and resume.
 *     setApprovalRequired(bool)  Toggle gated vs. open membership mode.
 *     setTransferable(bool)      Toggle soulbound vs. transferable tokens.
 *     burnFrom(address)          Force-remove any member.
 *     transferOwnership(address) Migrate to a Safe or Timelock.
 *
 *   renounceOwnership() is permanently blocked to prevent accidental
 *   admin loss. Always use transferOwnership() to migrate.
 *
 * ---- ACCESSCONTROL (DAO READINESS) ------------------------------------------
 *
 *   DEFAULT_ADMIN_ROLE  Root of the role hierarchy; can grant/revoke roles.
 *   APPROVER_ROLE       approve / revoke individual members. Assign to a
 *                       DAO committee, multisig, or on-chain governance.
 *   MINTER_ROLE         Call mintTo(address) on behalf of other addresses.
 *                       Assign to airdrop contracts or DAO grant proposals.
 *
 * ---- PAUSABLE FUNCTIONALITY -------------------------------------------------
 *
 *   Owner calls pause() to freeze the contract in an emergency.
 *   When paused the following REVERT:
 *     mint(), mintTo()
 *     approveMember(), approveMemberBatch()
 *     revokeMember(), revokeMemberBatch()
 *     ERC-721 transfers (safeTransferFrom, transferFrom)
 *   The following REMAIN AVAILABLE while paused:
 *     burn()      -- users must always be able to exit voluntarily.
 *     burnFrom()  -- owner must always be able to enforce removal.
 *
 * ---- MEMBERSHIP ID COUNTER --------------------------------------------------
 *
 *   _nextTokenId  (monotonic, never decrements)
 *     Sequential IDs starting at 1. Token ID 0 is reserved as the
 *     unambiguous "no membership" sentinel. Never reused after a burn.
 *
 *   _memberCount  (live, inc on mint / dec on burn)
 *     Current number of addresses holding a token. totalMembers() reads
 *     this in O(1) with a single SLOAD. No ERC721Enumerable required.
 *
 * ---- STORAGE LAYOUT ---------------------------------------------------------
 *
 *   Slot   Variable            Type       Notes
 *   -----  ------------------  ---------  ------------------------------------
 *   +0     _nextTokenId        uint256    Monotonic; ID 0 is sentinel
 *   +1     _memberCount        uint256    Live holder count
 *   +2     approvalRequired    bool       Packed together -- one SLOAD for both
 *   +2     transferable        bool       Packed together -- one SLOAD for both
 *   +3     _approved           mapping    address -> bool; gated-mode state
 *   +4     _memberToken        mapping    address -> tokenId (0 = no token)
 *
 * ---- GAS OPTIMISATIONS ------------------------------------------------------
 *
 *   - approvalRequired + transferable share one 32-byte slot (one SLOAD).
 *   - _memberCount uses unchecked inc/dec (invariants proven in NatSpec).
 *   - _nextTokenId uses unchecked post-increment (2^256 overflow impossible).
 *   - isMember() and onlyMember short-circuit on first false condition.
 *   - Single _memberToken mapping replaces two (was _tokenOf + _memberId).
 *   - No ERC721Enumerable: saves ~3 SSTOREs per mint, ~3 SSTOREs per burn.
 *   - Batch functions use calldata arrays (zero memory copy) + unchecked ++i.
 *   - burn() / burnFrom() pre-read tokenId from _memberToken (avoids 2nd SLOAD).
 *   - Custom errors replace revert strings (~200 gas saved per revert path).
 *   - _update() handles all protocol checks in one internal hook.
 *
 * ---- SECURITY ---------------------------------------------------------------
 *
 *   - One-per-address invariant enforced in _update() -- covers every ERC-721
 *     transition path including safeTransferFrom and transferFrom. No bypass.
 *   - renounceOwnership() permanently disabled.
 *   - Burns bypass pause -- users cannot be permanently trapped.
 *   - Typed custom errors on all privileged and invariant-failure paths.
 */
contract VaultMatesMembership is
    ERC721,
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
     * @dev    Holders may call approveMember(), approveMemberBatch(),
     *         revokeMember(), and revokeMemberBatch(). Intended for a DAO
     *         approval committee, multisig, or on-chain governance contract.
     *         Grant via: grantRole(APPROVER_ROLE, daoContract)
     */
    bytes32 public constant APPROVER_ROLE = keccak256("APPROVER_ROLE");

    /**
     * @notice Minter role.
     * @dev    Holders may call mintTo(address) on behalf of other addresses.
     *         Not required for self-mint via mint(). Intended for airdrop
     *         contracts and DAO grant proposals.
     */
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // =========================================================================
    // Storage
    // =========================================================================

    /**
     * @notice Monotonically increasing counter used to assign token IDs.
     * @dev    Starts at 1. Token ID 0 is the "no membership" sentinel returned
     *         by getMemberId() and tokenOf() for addresses with no token.
     *         Incremented with unchecked arithmetic; 2^256 overflow is physically
     *         impossible.
     */
    uint256 private _nextTokenId;

    /**
     * @notice Live count of addresses currently holding a membership token.
     * @dev    Incremented in _mintMembership(); decremented in _burnMembership().
     *         Underflow is impossible: decrement only occurs when a token exists
     *         (_memberCount >= 1). Exposed via totalMembers().
     */
    uint256 private _memberCount;

    /**
     * @notice When true, minting issues the NFT but does NOT grant active
     *         membership until an APPROVER_ROLE holder calls approveMember().
     * @dev    Packed with `transferable` into the same 32-byte storage slot.
     */
    bool public approvalRequired;

    /**
     * @notice When false, wallet-to-wallet transfers revert (soulbound mode).
     * @dev    Mint and burn always permitted regardless of this flag.
     *         Packed with approvalRequired.
     */
    bool public transferable;

    /// @dev address -> explicit approval state. Only meaningful when approvalRequired == true.
    mapping(address => bool) private _approved;

    /**
     * @dev address -> ERC-721 token ID currently held. 0 = no token.
     *      Serves dual purpose: tokenOf() and getMemberId() both read this slot.
     *      Updated in _update() on every mint, transfer, and burn.
     */
    mapping(address => uint256) private _memberToken;

    // =========================================================================
    // Events
    // =========================================================================

    /**
     * @notice Emitted when a new membership token is minted.
     * @param  to        Address that received the membership token.
     * @param  tokenId   ERC-721 token ID minted.
     * @param  memberId  Membership ID assigned (equals tokenId in v1).
     * @param  totalNow  totalMembers() value immediately after this mint.
     */
    event MembershipMinted(
        address indexed to,
        uint256 indexed tokenId,
        uint256         memberId,
        uint256         totalNow
    );

    /**
     * @notice Emitted when a membership token is burned (voluntary or forced).
     * @dev    Fired by both burn() and burnFrom(). After this event,
     *         getMemberId(account) returns 0 and isMember(account) returns false.
     * @param  account   Address whose membership was revoked.
     * @param  tokenId   ERC-721 token ID burned.
     * @param  memberId  Membership ID cleared.
     * @param  totalNow  totalMembers() value immediately after this burn.
     */
    event MembershipRevoked(
        address indexed account,
        uint256 indexed tokenId,
        uint256         memberId,
        uint256         totalNow
    );

    /**
     * @notice Emitted when an address receives explicit membership approval.
     * @param  account   Address approved.
     * @param  approver  Address that granted the approval.
     */
    event MemberApproved(address indexed account, address indexed approver);

    /**
     * @notice Emitted when an address has its approval cleared without burning.
     * @param  account  Address whose approval was cleared.
     * @param  revoker  Address that performed the revocation.
     */
    event MemberApprovalRevoked(address indexed account, address indexed revoker);

    /// @notice Emitted when the approvalRequired flag changes.
    event ApprovalModeChanged(bool indexed required);

    /// @notice Emitted when the transferable flag changes.
    event TransferabilityChanged(bool indexed isTransferable);

    // =========================================================================
    // Custom Errors
    // =========================================================================

    /// @dev Caller already holds a membership token.
    error AlreadyMember(address account);

    /// @dev mintTo() destination or transfer target already holds a token.
    error TargetAlreadyMember(address account);

    /// @dev Address holds no membership token.
    error NotTokenHolder(address account);

    /// @dev onlyMember: caller is not an active member.
    error CallerNotMember(address caller);

    /// @dev onlyApprover: caller lacks owner or APPROVER_ROLE.
    error Unauthorized();

    /// @dev Transfer blocked because transferable == false.
    error TransferLocked();

    /// @dev renounceOwnership() is permanently disabled.
    error RenounceOwnershipDisabled();

    /// @dev address(0) supplied where a real address is required.
    error ZeroAddress();

    // =========================================================================
    // Modifiers
    // =========================================================================

    /**
     * @notice Restricts a function to active members only.
     * @dev    Inline check -- avoids ~700 gas cross-contract staticcall overhead.
     *
     *         Short-circuit (1-3 SLOADs):
     *           SLOAD 1  _memberToken[msg.sender] == 0  -> revert (no token)
     *           SLOAD 2  approvalRequired == false       -> pass  (open mode)
     *           SLOAD 3  _approved[msg.sender] == false  -> revert (gated)
     */
    modifier onlyMember() {
        if (_memberToken[msg.sender] == 0)
            revert CallerNotMember(msg.sender);
        if (approvalRequired && !_approved[msg.sender])
            revert CallerNotMember(msg.sender);
        _;
    }

    /**
     * @dev Restricts to the contract owner or any APPROVER_ROLE holder.
     */
    modifier onlyApprover() {
        if (msg.sender != owner() && !hasRole(APPROVER_ROLE, msg.sender))
            revert Unauthorized();
        _;
    }

    // =========================================================================
    // Constructor
    // =========================================================================

    /**
     * @notice Deploy VaultMatesMembership.
     * @dev    initialOwner receives Ownable ownership, DEFAULT_ADMIN_ROLE,
     *         APPROVER_ROLE, and MINTER_ROLE. In production transfer ownership
     *         to a Gnosis Safe or Timelock post-deployment.
     *
     * @param  initialOwner       Non-zero address receiving all initial privileges.
     * @param  _approvalRequired  false = open mode; true = gated mode.
     * @param  _transferable      true = tokens transfer freely; false = soulbound.
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

        // Token ID 0 is reserved as the "no membership" sentinel.
        _nextTokenId = 1;
    }

    // =========================================================================
    // External -- Minting
    // =========================================================================

    /**
     * @notice Mint a membership token to the caller.
     * @dev    One-per-address invariant enforced in _update(). If approvalRequired
     *         == true, the caller receives the NFT but isMember() returns false
     *         until approveMember() is called.
     *
     * @custom:throws EnforcedPause  Contract is paused.
     * @custom:throws AlreadyMember  Caller already holds a token.
     * @custom:emits  MembershipMinted
     */
    function mint() external whenNotPaused {
        _mintMembership(msg.sender);
    }

    /**
     * @notice Mint a membership token to an arbitrary address.
     * @dev    Restricted to MINTER_ROLE. Intended for DAO grants and airdrops.
     *
     * @param  to  Recipient. Must be non-zero and not already hold a token.
     *
     * @custom:throws EnforcedPause       Contract is paused.
     * @custom:throws ZeroAddress         to == address(0).
     * @custom:throws TargetAlreadyMember to already holds a token.
     * @custom:emits  MembershipMinted
     */
    function mintTo(address to)
        external
        onlyRole(MINTER_ROLE)
        whenNotPaused
    {
        if (to == address(0)) revert ZeroAddress();
        _mintMembership(to);
    }

    // =========================================================================
    // External -- Burning
    // =========================================================================

    /**
     * @notice Burn the caller's own membership token (voluntary exit).
     * @dev    Intentionally omits whenNotPaused -- users must always be able
     *         to exit even during an emergency pause.
     *
     * @custom:throws NotTokenHolder  Caller holds no token.
     * @custom:emits  MembershipRevoked
     */
    function burn() external {
        uint256 tokenId = _memberToken[msg.sender];
        if (tokenId == 0) revert NotTokenHolder(msg.sender);
        _burnMembership(msg.sender, tokenId);
    }

    /**
     * @notice Force-burn any address's membership token.
     * @dev    Owner-only. Intentionally omits whenNotPaused -- admin removals
     *         must always be possible regardless of pause state.
     *
     * @param  account  Address to remove.
     *
     * @custom:throws NotTokenHolder  account holds no token.
     * @custom:emits  MembershipRevoked
     */
    function burnFrom(address account) external onlyOwner {
        uint256 tokenId = _memberToken[account];
        if (tokenId == 0) revert NotTokenHolder(account);
        _burnMembership(account, tokenId);
    }

    // =========================================================================
    // External -- Approval Management
    // =========================================================================

    /**
     * @notice Approve a single token holder as an active member.
     * @dev    Only meaningful when approvalRequired == true. Address must
     *         already hold a token.
     *
     * @param  account  Address to approve.
     *
     * @custom:throws EnforcedPause   Contract is paused.
     * @custom:throws Unauthorized    Caller lacks owner or APPROVER_ROLE.
     * @custom:throws NotTokenHolder  account holds no token.
     * @custom:emits  MemberApproved
     */
    function approveMember(address account)
        external
        whenNotPaused
        onlyApprover
    {
        if (_memberToken[account] == 0) revert NotTokenHolder(account);
        _approved[account] = true;
        emit MemberApproved(account, msg.sender);
    }

    /**
     * @notice Approve multiple token holders in one transaction.
     * @dev    Silently skips addresses with no token (no revert on partial lists).
     *
     * @param  accounts  Calldata array of addresses to approve.
     *
     * @custom:throws EnforcedPause  Contract is paused.
     * @custom:throws Unauthorized   Caller lacks owner or APPROVER_ROLE.
     * @custom:emits  MemberApproved for each successfully approved address.
     */
    function approveMemberBatch(address[] calldata accounts)
        external
        whenNotPaused
        onlyApprover
    {
        uint256 len = accounts.length;
        for (uint256 i; i < len; ) {
            address account = accounts[i];
            if (_memberToken[account] != 0) {
                _approved[account] = true;
                emit MemberApproved(account, msg.sender);
            }
            unchecked { ++i; }
        }
    }

    /**
     * @notice Revoke explicit membership approval from a single address.
     * @dev    Does NOT burn the token. isMember() returns false until
     *         approveMember() is called again.
     *
     * @param  account  Address to revoke.
     *
     * @custom:throws EnforcedPause  Contract is paused.
     * @custom:throws Unauthorized   Caller lacks owner or APPROVER_ROLE.
     * @custom:emits  MemberApprovalRevoked
     */
    function revokeMember(address account)
        external
        whenNotPaused
        onlyApprover
    {
        _approved[account] = false;
        emit MemberApprovalRevoked(account, msg.sender);
    }

    /**
     * @notice Revoke approval from multiple addresses in one transaction.
     *
     * @param  accounts  Calldata array of addresses to revoke.
     *
     * @custom:throws EnforcedPause  Contract is paused.
     * @custom:throws Unauthorized   Caller lacks owner or APPROVER_ROLE.
     * @custom:emits  MemberApprovalRevoked for each address.
     */
    function revokeMemberBatch(address[] calldata accounts)
        external
        whenNotPaused
        onlyApprover
    {
        uint256 len = accounts.length;
        for (uint256 i; i < len; ) {
            _approved[accounts[i]] = false;
            emit MemberApprovalRevoked(accounts[i], msg.sender);
            unchecked { ++i; }
        }
    }

    // =========================================================================
    // External -- Owner Configuration
    // =========================================================================

    /**
     * @notice Toggle whether minting requires subsequent owner approval.
     * @dev    false->true: existing non-approved holders lose access until approved.
     *         true->false: all token holders immediately become active members.
     *
     * @custom:emits ApprovalModeChanged
     */
    function setApprovalRequired(bool required) external onlyOwner {
        approvalRequired = required;
        emit ApprovalModeChanged(required);
    }

    /**
     * @notice Toggle whether tokens may be transferred between wallets.
     * @dev    Mint and burn remain permitted regardless of this flag.
     *
     * @custom:emits TransferabilityChanged
     */
    function setTransferable(bool _transferable) external onlyOwner {
        transferable = _transferable;
        emit TransferabilityChanged(_transferable);
    }

    /**
     * @notice Pause minting, approval management, and ERC-721 transfers.
     * @dev    burn() and burnFrom() remain available while paused.
     * @custom:emits OZ Paused(address)
     */
    function pause() external onlyOwner { _pause(); }

    /**
     * @notice Unpause and restore all normal operations.
     * @custom:emits OZ Unpaused(address)
     */
    function unpause() external onlyOwner { _unpause(); }

    /**
     * @notice Permanently disabled -- prevents accidental admin loss.
     * @dev    Use transferOwnership(newOwner) to migrate to a Safe or Timelock.
     * @custom:throws RenounceOwnershipDisabled  Always.
     */
    function renounceOwnership() public view override onlyOwner {
        revert RenounceOwnershipDisabled();
    }

    // =========================================================================
    // External -- IMembershipChecker
    // =========================================================================

    /**
     * @notice Returns true when `account` is an active member.
     * @dev    VaultMates calls this via staticcall inside its onlyMember modifier.
     *
     *         Short-circuit (1-3 SLOADs):
     *           1. _memberToken[account] == 0  -> false (no token)
     *           2. approvalRequired == false    -> true  (open mode)
     *           3. _approved[account]           -> result (gated mode)
     *
     * @param  account  Address to query.
     * @return          True if account is an active member.
     */
    function isMember(address account) external view override returns (bool) {
        if (_memberToken[account] == 0) return false;
        if (!approvalRequired)          return true;
        return _approved[account];
    }

    // =========================================================================
    // External -- View
    // =========================================================================

    /**
     * @notice Returns the live count of addresses holding a membership token.
     * @dev    O(1) single SLOAD. Replaces ERC721Enumerable.totalSupply().
     * @return  Current number of token holders.
     */
    function totalMembers() external view returns (uint256) {
        return _memberCount;
    }

    /**
     * @notice Returns the membership ID for `account`, or 0 if none.
     * @dev    IDs start at 1; 0 is the unambiguous "no membership" sentinel.
     *         O(1) single SLOAD.
     * @param  account  Address to query.
     * @return          Membership ID (= token ID in v1), or 0.
     */
    function getMemberId(address account) external view returns (uint256) {
        return _memberToken[account];
    }

    /**
     * @notice Returns the ERC-721 token ID held by `account`, or 0 if none.
     * @dev    Alias for getMemberId(). Reads the same storage slot.
     * @param  account  Address to query.
     * @return          Token ID, or 0.
     */
    function tokenOf(address account) external view returns (uint256) {
        return _memberToken[account];
    }

    /**
     * @notice Returns whether `account` has been explicitly approved.
     * @dev    Only meaningful when approvalRequired == true.
     * @param  account  Address to query.
     * @return          True if explicitly approved.
     */
    function isApproved(address account) external view returns (bool) {
        return _approved[account];
    }

    /**
     * @notice Returns the token ID that will be assigned to the next mint.
     * @dev    Not reserved; another tx may mine first.
     * @return  Current _nextTokenId value.
     */
    function nextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    // =========================================================================
    // Internal -- Mint / Burn
    // =========================================================================

    /**
     * @dev Shared internal mint path.
     *      1. Post-increment _nextTokenId (unchecked -- 2^256 overflow impossible).
     *      2. _safeMint -> _update() enforces one-per-address + writes _memberToken.
     *      3. Increment _memberCount (unchecked).
     *      4. Emit MembershipMinted.
     */
    function _mintMembership(address to) internal {
        uint256 tokenId;
        unchecked { tokenId = _nextTokenId++; }
        _safeMint(to, tokenId);
        unchecked { ++_memberCount; }
        emit MembershipMinted(to, tokenId, tokenId, _memberCount);
    }

    /**
     * @dev Shared internal burn path. Caller pre-reads tokenId to save one SLOAD.
     *      1. _burn -> _update() clears _memberToken[account].
     *      2. Decrement _memberCount (unchecked -- token existed so count >= 1).
     *      3. delete _approved[account].
     *      4. Emit MembershipRevoked.
     */
    function _burnMembership(address account, uint256 tokenId) internal {
        _burn(tokenId);
        unchecked { --_memberCount; }
        delete _approved[account];
        emit MembershipRevoked(account, tokenId, tokenId, _memberCount);
    }

    // =========================================================================
    // Internal -- ERC-721 _update Hook
    // =========================================================================

    /**
     * @dev Single hook covering every ERC-721 state transition (OZ v5).
     *
     *      Rule 1  Pause gate    -- all transitions revert when paused, except burns.
     *      Rule 2  Soulbound     -- wallet-to-wallet transfers revert when !transferable.
     *      Rule 3  One-per-addr  -- destination must not already hold a token.
     *      Rule 4  Bookkeeping   -- _memberToken kept in sync on every transition.
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    )
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);

        bool isMint = (from == address(0));
        bool isBurn = (to   == address(0));

        if (paused() && !isBurn)                    revert EnforcedPause();
        if (!transferable && !isMint && !isBurn)    revert TransferLocked();

        if (!isBurn && _memberToken[to] != 0) {
            if (isMint) revert AlreadyMember(to);
            revert TargetAlreadyMember(to);
        }

        if (!isMint) delete _memberToken[from];
        if (!isBurn) _memberToken[to] = tokenId;

        return super._update(to, tokenId, auth);
    }

    // =========================================================================
    // Internal -- EIP-165
    // =========================================================================

    /**
     * @notice Returns true if this contract implements the given interface.
     * @dev    Advertises ERC-721, AccessControl, and IMembershipChecker.
     *         IMembershipChecker checked first to short-circuit the super chain.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return
            interfaceId == type(IMembershipChecker).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
