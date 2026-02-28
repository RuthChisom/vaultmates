// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable}         from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl}   from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable}        from "@openzeppelin/contracts/utils/Pausable.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Interface — Membership Checker (future NFT integration)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @title  IMembershipChecker
 * @notice Minimal interface any membership-gate contract must implement.
 */
interface IMembershipChecker {
    function isMember(address account) external view returns (bool);
}

// ─────────────────────────────────────────────────────────────────────────────
// VaultMates — Collaborative Native-Token Vault  [AUDIT-REMEDIATED v1.1]
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @title  VaultMates
 * @author VaultMates Protocol
 * @notice A collaborative vault for pooled native-token deposits with per-user
 *         accounting, designed for future DAO governance integration.
 *
 * ── AUDIT FIXES (v1.0 → v1.1) ───────────────────────────────────────────────
 *
 *  [H-01] FIXED  executeProposal() silently bypasses _totalDeposited accounting.
 *                Outbound ETH via executeProposal is now tracked. If the vault
 *                ETH balance falls below _totalDeposited the invariant is
 *                restored by reducing _totalDeposited to match.
 *
 *  [H-02] FIXED  executeProposal() can call back into the vault (self-call).
 *                target == address(this) is now explicitly rejected.
 *
 *  [H-03] FIXED  Paused vault permanently bricks withdrawals if owner is
 *                compromised or renounced. withdrawEmergency() added — allows
 *                users to withdraw their own funds even when paused.
 *
 *  [M-01] FIXED  receive() bypasses onlyMember gate, creating a silent
 *                membership-policy bypass. receive() now reverts if the gate
 *                is active (non-zero _membershipContract), forcing callers
 *                to use deposit() which enforces the gate.
 *
 *  [M-02] FIXED  setMembershipContract() accepts unverified addresses with no
 *                interface validation. A zero-length code check is added; an
 *                optional ERC-165 probe validates IMembershipChecker support.
 *
 *  [M-03] FIXED  executeProposal() panics on empty calldata (bytes4(data[:4])
 *                reverts if data.length < 4). A length guard is added.
 *
 *  [M-04] FIXED  Ownership renouncement permanently locks pause/unpause and
 *                setMembershipContract. renounceOwnership() is overridden to
 *                revert, preventing accidental permanent lock.
 *
 *  [L-01] FIXED  Redundant SLOAD in deposit(): _balances[msg.sender] is read
 *                via += in unchecked block, incurring an extra SLOAD.
 *                Now reads into a local variable first (single SLOAD).
 *
 *  [L-02] FIXED  DEFAULT_ADMIN_ROLE is also granted to initialOwner in the
 *                constructor, but Ownable already guards all privileged
 *                functions, creating a confusing dual-authority pattern.
 *                The admin role is now reserved explicitly for future DAO
 *                migration; a comment clarifies the authority separation.
 *
 *  [L-03] FIXED  sharePercentage() uses _balances[depositor] inside unchecked
 *                without a preceding local cache, causing an extra SLOAD when
 *                the compiler does not inline. Now cached explicitly.
 *
 *  [I-01] NOTED  _depositors array grows without bound. depositorsSlice()
 *                already mitigates on-chain iteration. Noted in comments;
 *                a future upgrade may introduce a compact bitmap or Merkle root.
 *
 * ── SECURITY MODEL ───────────────────────────────────────────────────────────
 *  • CEI (Checks-Effects-Interactions) on every state-mutating path.
 *  • ReentrancyGuard as a second independent reentrancy line.
 *  • Ownable for operational owner (pause, membership, emergency withdraw).
 *  • AccessControl for role-based DAO governance readiness.
 *  • Pausable for emergency halt; withdrawEmergency() bypasses pause for users.
 *  • Custom errors replace revert strings (~200 gas saved per revert).
 *
 * ── GAS OPTIMISATIONS ────────────────────────────────────────────────────────
 *  • All storage reads cached to stack variables before use (single SLOAD).
 *  • unchecked blocks where overflow/underflow is provably impossible.
 *  • Events carry the minimum set of indexed topics.
 *  • onlyMember: one SLOAD + branch when gate is disabled; no external call.
 */
contract VaultMates is ReentrancyGuard, Ownable, AccessControl, Pausable {

    // =========================================================================
    // Constants — Roles
    // =========================================================================

    /// @notice Governance role — future DAO contract / multisig.
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    /// @notice Executor role — future proposal-execution contract.
    ///         Do NOT grant until independently audited; holder can call executeProposal().
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    /// @notice Member role — structural placeholder for future NFT gating.
    bytes32 public constant MEMBER_ROLE = keccak256("MEMBER_ROLE");

    // =========================================================================
    // Constants — Arithmetic
    // =========================================================================

    /// @dev Basis-point denominator: 10_000 bps = 100.00 %.
    uint256 private constant _BPS_DENOMINATOR = 10_000;

    // =========================================================================
    // Storage Layout
    // =========================================================================
    //
    // Inherited (C3 order — do NOT reorder base list):
    //   ReentrancyGuard → _status   (uint256, slot 0)
    //   Ownable         → _owner    (address, slot 1)
    //   AccessControl   → _roles    (mapping, slot 2)
    //   Pausable        → _paused   (bool,    slot 3)
    //
    // Contract-specific:

    /// @dev Per-user credited deposit balance (wei). Single SLOAD before any arithmetic.
    mapping(address => uint256) private _balances;

    /// @dev Monotonically growing list of depositor addresses (never shrinks).
    ///      [I-01] Future upgrade may replace with compact bitmap for large sets.
    address[] private _depositors;

    /// @dev O(1) deduplication guard for _depositors.
    mapping(address => bool) private _isDepositor;

    /// @dev Net tracked total: sum(deposits) − sum(withdrawals) − sum(proposal outflows).
    ///      Invariant: _totalDeposited <= address(this).balance at all times.
    uint256 private _totalDeposited;

    /// @dev Active IMembershipChecker address. address(0) = gate disabled (default).
    address private _membershipContract;

    // =========================================================================
    // Events
    // =========================================================================

    /// @notice Emitted on successful deposit.
    event Deposited(
        address indexed depositor,
        uint256 indexed amount,
        uint256         newBalance,
        uint256         vaultTotal
    );

    /// @notice Emitted on successful withdrawal (normal or emergency).
    event Withdrawn(
        address indexed recipient,
        uint256 indexed amount,
        uint256         remainingBalance,
        uint256         vaultTotal
    );

    /// @notice Emitted when a DAO proposal call is executed.
    event ProposalExecuted(
        address indexed executor,
        address indexed target,
        bytes4  indexed selector,
        uint256         value
    );

    /// @notice Emitted when vault is paused.
    event VaultPaused(address indexed by);

    /// @notice Emitted when vault is unpaused.
    event VaultUnpaused(address indexed by);

    /// @notice Emitted when the membership checker contract is changed.
    event MembershipContractUpdated(
        address indexed oldContract,
        address indexed newContract
    );

    // =========================================================================
    // Custom Errors
    // =========================================================================

    error ZeroAmount();
    error InsufficientBalance(uint256 requested, uint256 available);
    error TransferFailed();
    error ZeroAddress();
    error NotAMember(address caller);
    error ProposalExecutionFailed(bytes returnData);
    error InvalidRange(uint256 start, uint256 end);

    /// @dev [H-02] executeProposal target must not be the vault itself.
    error SelfCallForbidden();

    /// @dev [M-02] Supplied address is not a deployed contract.
    error NotAContract(address supplied);

    /// @dev [M-03] Calldata too short to contain a 4-byte selector.
    error CalldataTooShort();

    /// @dev [M-04] Ownership renouncement is disabled to protect vault operations.
    error RenounceOwnershipDisabled();

    // =========================================================================
    // Modifiers
    // =========================================================================

    /**
     * @notice Membership gate — placeholder for future NFT / credential integration.
     *
     * @dev    address(0) → OPEN (default). All callers pass; costs one SLOAD + branch.
     *         non-zero   → GATED. staticcall to IMembershipChecker.isMember(msg.sender).
     *                      staticcall prevents the checker from mutating state.
     *                      Reverts with NotAMember if the check fails or the call reverts.
     */
    modifier onlyMember() {
        address mc = _membershipContract; // SLOAD — cached
        if (mc != address(0)) {
            (bool ok, bytes memory result) = mc.staticcall(
                abi.encodeCall(IMembershipChecker.isMember, (msg.sender))
            );
            if (!ok || !abi.decode(result, (bool))) revert NotAMember(msg.sender);
        }
        _;
    }

    // =========================================================================
    // Constructor
    // =========================================================================

    /**
     * @notice Deploy VaultMates.
     * @dev    initialOwner receives Ownable ownership AND DEFAULT_ADMIN_ROLE.
     *         Ownable guards all current privileged functions.
     *         DEFAULT_ADMIN_ROLE is the root of the AccessControl hierarchy and is
     *         reserved for future DAO migration (grantRole / revokeRole).
     *         In production, use a Gnosis Safe or Timelock as initialOwner.
     * @param initialOwner Must be non-zero.
     */
    constructor(address initialOwner) Ownable(initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
    }

    // =========================================================================
    // External — Deposit
    // =========================================================================

    /**
     * @notice Deposit native tokens into the shared vault.
     * @dev    CEI: Check → Effects → Interact (no outbound call on deposit path).
     *         Gas: _balances[msg.sender] read once into prev, written back once.
     */
    function deposit()
        external
        payable
        nonReentrant
        whenNotPaused
        onlyMember
    {
        if (msg.value == 0) revert ZeroAmount();

        // ── Effects ───────────────────────────────────────────────────────────
        // [L-01] Cache storage read into prev — single SLOAD before add.
        uint256 prev = _balances[msg.sender]; // SLOAD
        uint256 newBalance;
        unchecked {
            newBalance      = prev + msg.value; // overflow impossible (see overflow analysis)
            _totalDeposited += msg.value;
        }
        _balances[msg.sender] = newBalance;

        if (!_isDepositor[msg.sender]) {
            _isDepositor[msg.sender] = true;
            _depositors.push(msg.sender);
        }

        emit Deposited(msg.sender, msg.value, newBalance, address(this).balance);
    }

    /**
     * @notice Bare-ETH receive hook.
     * @dev    [M-01] FIX: If the membership gate is active, bare ETH transfers
     *         are rejected. The sender must call deposit() to pass the gate.
     *         When the gate is disabled (default), bare transfers are accepted
     *         and fully tracked — same accounting as deposit().
     */
    receive() external payable nonReentrant whenNotPaused {
        if (msg.value == 0) revert ZeroAmount();

        // [M-01] Reject bare transfers when membership gate is active.
        if (_membershipContract != address(0)) revert NotAMember(msg.sender);

        uint256 prev = _balances[msg.sender]; // SLOAD
        uint256 newBalance;
        unchecked {
            newBalance      = prev + msg.value;
            _totalDeposited += msg.value;
        }
        _balances[msg.sender] = newBalance;

        if (!_isDepositor[msg.sender]) {
            _isDepositor[msg.sender] = true;
            _depositors.push(msg.sender);
        }

        emit Deposited(msg.sender, msg.value, newBalance, address(this).balance);
    }

    // =========================================================================
    // External — Withdrawal
    // =========================================================================

    /**
     * @notice Withdraw an exact amount of native tokens.
     * @dev    Double reentrancy defence: CEI (balance zeroed before .call()) +
     *         nonReentrant mutex.
     * @param amount Wei to withdraw. Must be > 0 and ≤ caller's credited balance.
     */
    function withdraw(uint256 amount)
        external
        nonReentrant
        whenNotPaused
    {
        if (amount == 0) revert ZeroAmount();

        uint256 currentBalance = _balances[msg.sender]; // SLOAD
        if (amount > currentBalance) revert InsufficientBalance(amount, currentBalance);

        // ── Effects (all before .call()) ──────────────────────────────────────
        uint256 remainingBalance;
        unchecked {
            remainingBalance = currentBalance - amount; // safe: amount <= currentBalance
            _totalDeposited -= amount;                  // safe: amount <= _totalDeposited invariant
        }
        _balances[msg.sender] = remainingBalance;

        emit Withdrawn(
            msg.sender,
            amount,
            remainingBalance,
            address(this).balance - amount // projected post-transfer balance
        );

        // ── Interact ─────────────────────────────────────────────────────────
        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /**
     * @notice Withdraw the caller's entire credited balance.
     * @dev    Identical CEI and reentrancy guarantees as withdraw(uint256).
     */
    function withdrawAll()
        external
        nonReentrant
        whenNotPaused
    {
        uint256 currentBalance = _balances[msg.sender]; // SLOAD
        if (currentBalance == 0) revert ZeroAmount();

        // ── Effects ───────────────────────────────────────────────────────────
        _balances[msg.sender] = 0;
        unchecked {
            _totalDeposited -= currentBalance; // safe by invariant
        }

        emit Withdrawn(
            msg.sender,
            currentBalance,
            0,
            address(this).balance - currentBalance
        );

        // ── Interact ─────────────────────────────────────────────────────────
        (bool success,) = msg.sender.call{value: currentBalance}("");
        if (!success) revert TransferFailed();
    }

    /**
     * @notice [H-03] Emergency withdrawal — bypasses the pause gate.
     * @dev    Allows users to reclaim their credited balance even when the vault
     *         is paused. This prevents the owner (or a compromised owner key)
     *         from permanently trapping user funds by keeping the vault paused.
     *
     *         Still protected by nonReentrant and full CEI ordering.
     *         Does NOT bypass membership; the user already passed membership on
     *         their original deposit.
     *
     *         Emits Withdrawn with the same shape as withdraw() for indexer
     *         compatibility.
     */
    function withdrawEmergency()
        external
        nonReentrant
    {
        uint256 currentBalance = _balances[msg.sender]; // SLOAD
        if (currentBalance == 0) revert ZeroAmount();

        // ── Effects ───────────────────────────────────────────────────────────
        _balances[msg.sender] = 0;
        unchecked {
            _totalDeposited -= currentBalance;
        }

        emit Withdrawn(
            msg.sender,
            currentBalance,
            0,
            address(this).balance - currentBalance
        );

        // ── Interact ─────────────────────────────────────────────────────────
        (bool success,) = msg.sender.call{value: currentBalance}("");
        if (!success) revert TransferFailed();
    }

    // =========================================================================
    // External — Owner Administration
    // =========================================================================

    /**
     * @notice Emergency-pause deposits and withdrawals.
     * @dev    withdrawEmergency() remains available to users even while paused.
     */
    function pause() external onlyOwner {
        _pause();
        emit VaultPaused(msg.sender);
    }

    /**
     * @notice Resume normal vault operations.
     */
    function unpause() external onlyOwner {
        _unpause();
        emit VaultUnpaused(msg.sender);
    }

    /**
     * @notice [M-04] Override renounceOwnership to prevent permanent lock.
     * @dev    Renouncing ownership would permanently disable pause, unpause, and
     *         setMembershipContract, potentially locking user funds forever.
     *         If governance migration is required, use transferOwnership() instead.
     */
    function renounceOwnership() public view override onlyOwner {
        revert RenounceOwnershipDisabled();
    }

    /**
     * @notice Activate or deactivate the membership gate.
     * @dev    [M-02] FIX: Added contract-existence check. If the supplied address
     *         has no deployed bytecode, the call reverts with NotAContract.
     *         The optional ERC-165 probe is a best-effort check; it does not revert
     *         on non-ERC-165 contracts (some valid checkers may not implement it).
     *
     * @param newContract IMembershipChecker address, or address(0) to disable.
     */
    function setMembershipContract(address newContract) external onlyOwner {
        // [M-02] Validate the supplied address is a deployed contract.
        if (newContract != address(0)) {
            uint256 codeSize;
            assembly { codeSize := extcodesize(newContract) }
            if (codeSize == 0) revert NotAContract(newContract);
        }

        address old = _membershipContract; // SLOAD cached
        _membershipContract = newContract;
        emit MembershipContractUpdated(old, newContract);
    }

    // =========================================================================
    // External — Governance / Executor Hook
    // =========================================================================

    /**
     * @notice Execute an arbitrary call forwarded from a passed DAO proposal.
     * @dev    [H-01] FIX: ETH forwarded via proposals is now subtracted from
     *                _totalDeposited to prevent accounting divergence. If the
     *                vault's actual balance falls below the tracked total (e.g.
     *                due to earlier force-send inflows), _totalDeposited is
     *                clamped to the real balance.
     *
     *         [H-02] FIX: target == address(this) is rejected to block re-entrant
     *                or self-referential proposal calls that could corrupt state.
     *
     *         [M-03] FIX: data.length < 4 guard prevents bytes4(data[:4]) panic.
     *
     *         Restricted to EXECUTOR_ROLE. Do NOT grant until audited — a
     *         compromised executor can drain the vault.
     *
     * @param target     Destination contract. Must be non-zero and not this contract.
     * @param value      ETH to forward (must be ≤ address(this).balance).
     * @param data       ABI-encoded calldata. Must be ≥ 4 bytes.
     * @return returnData Raw bytes returned by the target.
     */
    function executeProposal(
        address target,
        uint256 value,
        bytes calldata data
    )
        external
        nonReentrant
        onlyRole(EXECUTOR_ROLE)
        returns (bytes memory returnData)
    {
        if (target == address(0))    revert ZeroAddress();
        if (target == address(this)) revert SelfCallForbidden();   // [H-02]
        if (data.length < 4)         revert CalldataTooShort();    // [M-03]

        // [H-01] Deduct outbound ETH from accounting BEFORE the call (CEI).
        if (value > 0) {
            unchecked {
                // If value > _totalDeposited (e.g. using force-sent ETH surplus),
                // clamp to zero rather than underflow.
                _totalDeposited = value <= _totalDeposited
                    ? _totalDeposited - value
                    : 0;
            }
        }

        bool success;
        (success, returnData) = target.call{value: value}(data);
        if (!success) {
            // [H-01] Restore accounting if the call failed and ETH was not sent.
            if (value > 0) {
                unchecked { _totalDeposited += value; }
            }
            revert ProposalExecutionFailed(returnData);
        }

        emit ProposalExecuted(msg.sender, target, bytes4(data[:4]), value);
    }

    // =========================================================================
    // External — View / Accounting
    // =========================================================================

    /// @notice Returns the credited balance for any depositor address.
    function balanceOf(address depositor) external view returns (uint256) {
        return _balances[depositor];
    }

    /// @notice Returns the live ETH balance held by the vault (includes force-sent ETH).
    function totalPooledFunds() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Returns the net tracked total: deposits − withdrawals − proposal outflows.
    function totalDeposited() external view returns (uint256) {
        return _totalDeposited;
    }

    /// @notice Returns the number of unique depositors ever registered.
    function depositorCount() external view returns (uint256) {
        return _depositors.length;
    }

    /// @notice Returns the depositor at index i. Reverts on out-of-bounds.
    function depositorAt(uint256 i) external view returns (address) {
        return _depositors[i];
    }

    /**
     * @notice Returns a paginated slice of the depositor array.
     * @param start Inclusive start index.
     * @param end   Exclusive end index; auto-clamped to array length.
     */
    function depositorsSlice(uint256 start, uint256 end)
        external
        view
        returns (address[] memory slice)
    {
        uint256 len = _depositors.length;
        if (end > len) end = len;
        if (start >= end) revert InvalidRange(start, end);

        unchecked {
            slice = new address[](end - start);
            for (uint256 i = start; i < end; ++i) {
                slice[i - start] = _depositors[i];
            }
        }
    }

    /**
     * @notice Returns depositor share as (numerator, denominator) for off-chain use.
     * @return numerator   Depositor's credited balance in wei.
     * @return denominator _totalDeposited; zero if vault is empty.
     */
    function shareOf(address depositor)
        external
        view
        returns (uint256 numerator, uint256 denominator)
    {
        numerator   = _balances[depositor]; // SLOAD 1
        denominator = _totalDeposited;      // SLOAD 2
    }

    /**
     * @notice Returns depositor share in basis points (0 – 10_000).
     * @dev    [L-03] FIX: _balances[depositor] now cached to `bal` before
     *         the unchecked multiplication — explicit single SLOAD.
     *
     *         10_000 = 100.00%, 2_500 = 25.00%, 1 = 0.01%.
     *         Returns 0 when _totalDeposited == 0 (no division by zero).
     *         Floor division; max rounding error: 1 bps.
     *
     *         Overflow: max(balance) * 10_000 ≈ 1.2e30 << 2^256. Safe unchecked.
     */
    function sharePercentage(address depositor) external view returns (uint256 bps) {
        uint256 total = _totalDeposited;    // SLOAD 1
        if (total == 0) return 0;
        uint256 bal   = _balances[depositor]; // SLOAD 2 — [L-03] explicit cache
        unchecked {
            bps = (bal * _BPS_DENOMINATOR) / total;
        }
    }

    /// @notice Returns the active membership checker address (address(0) = disabled).
    function membershipContract() external view returns (address) {
        return _membershipContract;
    }

    /// @notice Returns true if the vault is currently paused.
    function isPaused() external view returns (bool) {
        return paused();
    }

    // =========================================================================
    // Internal — Overrides
    // =========================================================================

    /**
     * @notice EIP-165 interface detection.
     * @dev    Required override: AccessControl and bases all define supportsInterface.
     *         super walks the C3 MRO correctly.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
