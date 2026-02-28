// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVault {
    function getUserBalance(address user) external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function allocateFunds(address destination, uint256 amount) external;
}
