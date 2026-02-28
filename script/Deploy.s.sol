// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MembershipNFT} from "../src/MembershipNFT.sol";
import {Vault} from "../src/Vault.sol";
import {Governance} from "../src/Governance.sol";
import {AIRecommendation} from "../src/AIRecommendation.sol";
import {Executor} from "../src/Executor.sol";

/// @notice Deploys all VaultMates contracts in dependency order and wires them together.
///
/// Usage:
///   forge script script/Deploy.s.sol:DeployScript \
///     --rpc-url $RPC_URL \
///     --private-key $PRIVATE_KEY \
///     --broadcast \
///     --verify
///
/// Environment variables:
///   DEPLOYER_ADDRESS  – address that becomes owner of all contracts
///   AI_ORACLE_ADDRESS – address of the off-chain AI oracle (may be DEPLOYER_ADDRESS for testing)
///   QUORUM_BPS        – quorum in basis points (e.g. 5000 = 50 %)
///   VOTING_DURATION   – voting window in seconds (default 259200 = 3 days)
contract DeployScript is Script {
    function run() external {
        address deployer = vm.envOr("DEPLOYER_ADDRESS", msg.sender);
        address aiOracle = vm.envOr("AI_ORACLE_ADDRESS", deployer);
        uint256 quorumBps = vm.envOr("QUORUM_BPS", uint256(5000));
        uint256 votingDuration = vm.envOr("VOTING_DURATION", uint256(3 days));

        vm.startBroadcast();

        // 1. MembershipNFT
        MembershipNFT membership = new MembershipNFT(deployer);
        console.log("MembershipNFT deployed at:", address(membership));

        // 2. Vault
        Vault vault = new Vault(deployer, address(membership));
        console.log("Vault deployed at:", address(vault));

        // 3. Governance
        Governance governance = new Governance(
            deployer,
            address(membership),
            quorumBps,
            votingDuration
        );
        console.log("Governance deployed at:", address(governance));

        // 4. AIRecommendation
        AIRecommendation aiRec = new AIRecommendation(deployer, address(membership), aiOracle);
        console.log("AIRecommendation deployed at:", address(aiRec));

        // 5. Executor
        Executor executor = new Executor(deployer, address(governance), address(vault));
        console.log("Executor deployed at:", address(executor));

        // 6. Wire contracts together
        //    - Grant the Executor permission to move vault funds
        vault.setExecutor(address(executor));
        console.log("Vault executor set to:", address(executor));

        vm.stopBroadcast();

        // Summary
        console.log("\n=== VaultMates Deployment Summary ===");
        console.log("Owner / Deployer :", deployer);
        console.log("MembershipNFT    :", address(membership));
        console.log("Vault            :", address(vault));
        console.log("Governance       :", address(governance));
        console.log("AIRecommendation :", address(aiRec));
        console.log("Executor         :", address(executor));
        console.log("AI Oracle        :", aiOracle);
    }
}
