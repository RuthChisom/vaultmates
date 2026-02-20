// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title VaultMates
 * @notice A collaborative vault for pooled native token deposits with per-user accounting.
 *         Designed for future DAO governance and proposal execution integration.
 * @dev    Uses Checks-Effects-Interactions pattern + ReentrancyGuard for security.
 *         AccessControl provides a foundation for DAO role assignment later.
 */
contract VaultMates is ReentrancyGuard, AccessControl, Pausable {

    // =========================================================================
    // Roles
    // =========================================================================

    /// @notice Default admin role (inherited from AccessControl — held by deployer)
    // bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00; // Already defined in AccessControl

    /// @notice Governance role — assigned to a DAO contract or multisig in the future
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    /// @notice Executor role — assigned to a proposal execution contract in the future
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    // =========================================================================
    // Storage Layout
    // =========================================================================

    /// @dev Slot 0 (inherited: ReentrancyGuard._status)
    /// @dev Slot 1 (inherited: AccessControl._roles mapping)
    /// @dev Slot 2 (inherited: Pausable._paused)

    /// @notice Per-user deposited balance (does NOT reflect yield or fees)
    /// @dev    mapping(address => uint256) — packed with nothing; full 32-byte slot per entry
    mapping(address => uint256) private _balances;

    /// @notice Ordered list of depositors for enumeration (DAO proposals may need to iterate)
    address[] private _depositors;

    /// @notice Whether an address already exists in _depositors
    mapping(address => bool) private _isDepositor;

    /// @notice Snapshot of the last known total deposited (used for off-chain accounting / events)
    uint256 private _totalDeposited;

    // =========================================================================
    // Events
    // =========================================================================

    /// @notice Emitted when a user deposits native tokens
    event Deposited(address indexed depositor, uint256 amount, uint256 newBalance, uint256 vaultTotal);

    /// @notice Emitted when a user withdraws native tokens
    event Withdrawn(address indexed recipient, uint256 amount, uint256 remainingBalance, uint256 vaultTotal);

    /// @notice Emitted when governance executes a vault-level action (future use)
    event GovernanceAction(address indexed executor, bytes4 indexed selector, bytes data);

    /// @notice Emitted when the vault is paused or unpaused
    event VaultPaused(address indexed by);
    event VaultUnpaused(address indexed by);

    // =========================================================================
    // Errors (gas-efficient vs require strings)
    // =========================================================================

    error ZeroAmount();
    error InsufficientBalance(uint256 requested, uint256 available);
    error TransferFailed();
    error NotAuthorized();
    error ProposalExecutionFailed(bytes returnData);

    // =========================================================================
    // Constructor
    // =========================================================================

    /**
     * @param admin Address that receives DEFAULT_ADMIN_ROLE (typically a multisig or deployer).
     */
    constructor(address admin) {
        if (admin == address(0)) revert NotAuthorized();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // =========================================================================
    // External — Deposit
    // =========================================================================

    /**
     * @notice Deposit native tokens into the shared vault.
     * @dev    No minimum enforced here; governance can add policy later.
     *         Follows Checks-Effects-Interactions: state updated before any external call.
     */
    function deposit() external payable nonReentrant whenNotPaused {
        if (msg.value == 0) revert ZeroAmount();

        // Effects
        _balances[msg.sender] += msg.value;
        _totalDeposited += msg.value;

        if (!_isDepositor[msg.sender]) {
            _isDepositor[msg.sender] = true;
            _depositors.push(msg.sender);
        }

        emit Deposited(msg.sender, msg.value, _balances[msg.sender], address(this).balance);
    }

    /**
     * @notice Receive hook — forwards bare ETH transfers to deposit logic.
     */
    receive() external payable {
        if (msg.value == 0) revert ZeroAmount();

        _balances[msg.sender] += msg.value;
        _totalDeposited += msg.value;

        if (!_isDepositor[msg.sender]) {
            _isDepositor[msg.sender] = true;
            _depositors.push(msg.sender);
        }

        emit Deposited(msg.sender, msg.value, _balances[msg.sender], address(this).balance);
    }

    // =========================================================================
    // External — Withdrawal
    // =========================================================================

    /**
     * @notice Withdraw a specific amount of native tokens.
     * @param  amount Amount in wei to withdraw.
     * @dev    CEI pattern: balance zeroed BEFORE transfer to block reentrancy (backed by ReentrancyGuard too).
     */
    function withdraw(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        uint256 userBalance = _balances[msg.sender];
        if (amount > userBalance) revert InsufficientBalance(amount, userBalance);

        // Effects — update state before external call
        unchecked {
            _balances[msg.sender] = userBalance - amount;
            _totalDeposited -= amount;
        }

        emit Withdrawn(msg.sender, amount, _balances[msg.sender], address(this).balance);

        // Interaction — call after all state changes
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /**
     * @notice Withdraw the caller's entire balance in one call.
     */
    function withdrawAll() external nonReentrant whenNotPaused {
        uint256 userBalance = _balances[msg.sender];
        if (userBalance == 0) revert ZeroAmount();

        // Effects
        _balances[msg.sender] = 0;
        unchecked {
            _totalDeposited -= userBalance;
        }

        emit Withdrawn(msg.sender, userBalance, 0, address(this).balance);

        // Interaction
        (bool success, ) = msg.sender.call{value: userBalance}("");
        if (!success) revert TransferFailed();
    }

    // =========================================================================
    // External — Governance / Executor Hooks (future DAO integration)
    // =========================================================================

    /**
     * @notice Execute an arbitrary low-level call from a governance proposal.
     *         Restricted to EXECUTOR_ROLE (assigned to a proposal contract later).
     * @param  target   Contract to call.
     * @param  value    ETH to forward.
     * @param  data     Calldata payload.
     * @return returnData  Raw return bytes from the call.
     * @dev    This is intentionally generic to support future proposal types.
     *         EXECUTOR_ROLE must be carefully managed by governance.
     */
    function executeProposal(
        address target,
        uint256 value,
        bytes calldata data
    ) external nonReentrant onlyRole(EXECUTOR_ROLE) returns (bytes memory returnData) {
        bool success;
        (success, returnData) = target.call{value: value}(data);
        if (!success) revert ProposalExecutionFailed(returnData);

        emit GovernanceAction(msg.sender, bytes4(data[:4]), data);
    }

    /**
     * @notice Pause deposits and withdrawals. Emergency use only.
     *         Restricted to GOVERNANCE_ROLE.
     */
    function pause() external onlyRole(GOVERNANCE_ROLE) {
        _pause();
        emit VaultPaused(msg.sender);
    }

    /**
     * @notice Unpause the vault.
     *         Restricted to GOVERNANCE_ROLE.
     */
    function unpause() external onlyRole(GOVERNANCE_ROLE) {
        _unpause();
        emit VaultUnpaused(msg.sender);
    }

    // =========================================================================
    // External — View / Accounting
    // =========================================================================

    /**
     * @notice Returns the native token balance credited to a depositor.
     * @param  depositor Address to query.
     */
    function balanceOf(address depositor) external view returns (uint256) {
        return _balances[depositor];
    }

    /**
     * @notice Returns the live ETH balance held by the vault contract.
     * @dev    Includes any ETH sent directly (e.g. via selfdestruct or coinbase) —
     *         compare to totalDeposited() to detect unaccounted inflows.
     */
    function totalVaultBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Returns the sum of all tracked user deposits (may differ from
     *         address(this).balance if ETH was force-sent to the contract).
     */
    function totalDeposited() external view returns (uint256) {
        return _totalDeposited;
    }

    /**
     * @notice Returns the number of unique depositors.
     */
    function depositorCount() external view returns (uint256) {
        return _depositors.length;
    }

    /**
     * @notice Returns the depositor address at index `i`.
     * @dev    Useful for governance snapshot iteration.
     */
    function depositorAt(uint256 i) external view returns (address) {
        return _depositors[i];
    }

    /**
     * @notice Returns a paginated slice of depositor addresses.
     * @param  start  Inclusive start index.
     * @param  end    Exclusive end index.
     */
    function depositorsSlice(uint256 start, uint256 end)
        external
        view
        returns (address[] memory slice)
    {
        uint256 len = _depositors.length;
        if (end > len) end = len;
        slice = new address[](end - start);
        for (uint256 i = start; i < end; ) {
            slice[i - start] = _depositors[i];
            unchecked { ++i; }
        }
    }

    /**
     * @notice Convenience view to check a depositor's share of pooled funds as a fraction.
     * @return numerator   User balance (wei).
     * @return denominator Total deposited (wei).
     * @dev    Caller divides numerator/denominator for the exact share. Avoids floating point.
     */
    function shareOf(address depositor)
        external
        view
        returns (uint256 numerator, uint256 denominator)
    {
        numerator = _balances[depositor];
        denominator = _totalDeposited;
    }

    // =========================================================================
    // Internal Helpers
    // =========================================================================

    /**
     * @dev Required override: AccessControl + Pausable both define supportsInterface.
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