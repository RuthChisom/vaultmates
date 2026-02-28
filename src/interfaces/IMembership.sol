// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMembership {
    function checkMembership(address user) external view returns (bool);
    function getMemberTokenId(address user) external view returns (uint256);
}
