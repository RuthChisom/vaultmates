// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IMembership.sol";
import "./interfaces/IVault.sol";

contract Vault is Ownable, ReentrancyGuard, IVault {
    IMembership public immutable membership;

    mapping(address => uint256) private _balances;
    uint256 private _totalAssets;
    address public executor;

    event FundsDeposited(address indexed user, uint256 amount);
    event FundsWithdrawn(address indexed user, uint256 amount);
    event FundsAllocated(address indexed destination, uint256 amount, uint256 indexed proposalId);
    event ExecutorUpdated(address indexed newExecutor);

    error NotMember(address user);
    error InsufficientBalance(address user, uint256 requested, uint256 available);
    error InsufficientVaultFunds(uint256 requested, uint256 available);
    error ZeroAmount();
    error Unauthorized();
    error InvalidAddress();

    modifier onlyMember() {
        if (!membership.checkMembership(msg.sender)) revert NotMember(msg.sender);
        _;
    }

    modifier onlyExecutor() {
        if (msg.sender != executor && msg.sender != owner()) revert Unauthorized();
        _;
    }

    constructor(address initialOwner, address membershipContract) Ownable(initialOwner) {
        if (membershipContract == address(0)) revert InvalidAddress();
        membership = IMembership(membershipContract);
    }

    function depositFunds() external payable onlyMember nonReentrant {
        if (msg.value == 0) revert ZeroAmount();
        _balances[msg.sender] += msg.value;
        _totalAssets += msg.value;
        emit FundsDeposited(msg.sender, msg.value);
    }

    function withdrawFunds(uint256 amount) external onlyMember nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 userBalance = _balances[msg.sender];
        if (amount > userBalance) revert InsufficientBalance(msg.sender, amount, userBalance);

        _balances[msg.sender] -= amount;
        _totalAssets -= amount;

        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "ETH transfer failed");

        emit FundsWithdrawn(msg.sender, amount);
    }

    function getUserBalance(address user) external view override returns (uint256) {
        return _balances[user];
    }

    function totalAssets() external view override returns (uint256) {
        return _totalAssets;
    }

    function allocateFunds(address destination, uint256 amount) external override onlyExecutor nonReentrant {
        if (destination == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();
        if (amount > _totalAssets) revert InsufficientVaultFunds(amount, _totalAssets);

        _totalAssets -= amount;

        (bool success,) = destination.call{value: amount}("");
        require(success, "ETH transfer failed");

        emit FundsAllocated(destination, amount, 0);
    }

    function allocateFunds(address destination, uint256 amount, uint256 proposalId)
        external
        onlyExecutor
        nonReentrant
    {
        if (destination == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();
        if (amount > _totalAssets) revert InsufficientVaultFunds(amount, _totalAssets);

        _totalAssets -= amount;

        (bool success,) = destination.call{value: amount}("");
        require(success, "ETH transfer failed");

        emit FundsAllocated(destination, amount, proposalId);
    }

    function setExecutor(address newExecutor) external onlyOwner {
        if (newExecutor == address(0)) revert InvalidAddress();
        executor = newExecutor;
        emit ExecutorUpdated(newExecutor);
    }

    receive() external payable {
        _totalAssets += msg.value;
    }
}
