// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IMembership.sol";
import "./interfaces/IVault.sol";

/// @title VaultMates Collaborative Vault / Treasury
/// @notice Module 2 – Pool user funds and manage them collaboratively.
/// @dev Only active members (holding a MembershipNFT) may deposit.
///      The Executor contract is granted the EXECUTOR role to move funds
///      when a proposal is approved.
contract Vault is Ownable, ReentrancyGuard, IVault {
    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    IMembership public immutable membership;

    /// @notice ETH balance tracked per depositor
    mapping(address => uint256) private _balances;

    /// @notice Total ETH held in the vault
    uint256 private _totalAssets;

    /// @notice Address allowed to allocate funds on behalf of the DAO (Executor)
    address public executor;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event FundsDeposited(address indexed user, uint256 amount);
    event FundsWithdrawn(address indexed user, uint256 amount);
    event FundsAllocated(address indexed destination, uint256 amount, uint256 indexed proposalId);
    event ExecutorUpdated(address indexed newExecutor);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error NotMember(address user);
    error InsufficientBalance(address user, uint256 requested, uint256 available);
    error InsufficientVaultFunds(uint256 requested, uint256 available);
    error ZeroAmount();
    error Unauthorized();
    error InvalidAddress();

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyMember() {
        if (!membership.checkMembership(msg.sender)) revert NotMember(msg.sender);
        _;
    }

    modifier onlyExecutor() {
        if (msg.sender != executor && msg.sender != owner()) revert Unauthorized();
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address initialOwner, address membershipContract)
        Ownable(initialOwner)
    {
        if (membershipContract == address(0)) revert InvalidAddress();
        membership = IMembership(membershipContract);
    }

    // -------------------------------------------------------------------------
    // External – deposit / withdraw
    // -------------------------------------------------------------------------

    /// @notice Deposit ETH into the vault. Caller must be an active member.
    function depositFunds() external payable onlyMember nonReentrant {
        if (msg.value == 0) revert ZeroAmount();

        _balances[msg.sender] += msg.value;
        _totalAssets += msg.value;

        emit FundsDeposited(msg.sender, msg.value);
    }

    /// @notice Withdraw your own deposited ETH from the vault.
    /// @param amount  Amount of ETH (in wei) to withdraw.
    function withdrawFunds(uint256 amount) external onlyMember nonReentrant {
        if (amount == 0) revert ZeroAmount();

        uint256 userBalance = _balances[msg.sender];
        if (amount > userBalance) {
            revert InsufficientBalance(msg.sender, amount, userBalance);
        }

        _balances[msg.sender] -= amount;
        _totalAssets -= amount;

        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "ETH transfer failed");

        emit FundsWithdrawn(msg.sender, amount);
    }

    // -------------------------------------------------------------------------
    // IVault implementation
    // -------------------------------------------------------------------------

    /// @inheritdoc IVault
    function getUserBalance(address user) external view override returns (uint256) {
        return _balances[user];
    }

    /// @inheritdoc IVault
    function totalAssets() external view override returns (uint256) {
        return _totalAssets;
    }

    /// @inheritdoc IVault
    /// @dev Called by the Executor after a proposal passes.
    function allocateFunds(address destination, uint256 amount) external override onlyExecutor nonReentrant {
        if (destination == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();
        if (amount > _totalAssets) {
            revert InsufficientVaultFunds(amount, _totalAssets);
        }

        _totalAssets -= amount;

        (bool success,) = destination.call{value: amount}("");
        require(success, "ETH transfer failed");

        emit FundsAllocated(destination, amount, 0);
    }

    /// @dev Overload that also logs the proposalId for on-chain traceability.
    function allocateFunds(address destination, uint256 amount, uint256 proposalId)
        external
        onlyExecutor
        nonReentrant
    {
        if (destination == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();
        if (amount > _totalAssets) {
            revert InsufficientVaultFunds(amount, _totalAssets);
        }

        _totalAssets -= amount;

        (bool success,) = destination.call{value: amount}("");
        require(success, "ETH transfer failed");

        emit FundsAllocated(destination, amount, proposalId);
    }

    // -------------------------------------------------------------------------
    // Admin
    // -------------------------------------------------------------------------

    /// @notice Set or change the Executor contract address.
    function setExecutor(address newExecutor) external onlyOwner {
        if (newExecutor == address(0)) revert InvalidAddress();
        executor = newExecutor;
        emit ExecutorUpdated(newExecutor);
    }

    // -------------------------------------------------------------------------
    // Receive ETH (e.g. yield / donations)
    // -------------------------------------------------------------------------

    receive() external payable {
        _totalAssets += msg.value;
    }
}
