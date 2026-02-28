// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MembershipNFT} from "../src/MembershipNFT.sol";
import {Vault} from "../src/Vault.sol";
import {Governance} from "../src/Governance.sol";
import {AIRecommendation} from "../src/AIRecommendation.sol";
import {Executor} from "../src/Executor.sol";

contract DeployScript is Script {
    function run() external {
        address deployer = vm.envOr("DEPLOYER_ADDRESS", msg.sender);
        address aiOracle = vm.envOr("AI_ORACLE_ADDRESS", deployer);
        uint256 quorumBps = vm.envOr("QUORUM_BPS", uint256(5000));
        uint256 votingDuration = vm.envOr("VOTING_DURATION", uint256(3 days));

        vm.startBroadcast();

        MembershipNFT membership = new MembershipNFT(deployer);
        Vault vault = new Vault(deployer, address(membership));
        Governance governance = new Governance(deployer, address(membership), quorumBps, votingDuration);
        AIRecommendation aiRec = new AIRecommendation(deployer, address(membership), aiOracle);
        Executor executor = new Executor(deployer, address(governance), address(vault));

        vault.setExecutor(address(executor));

        vm.stopBroadcast();

        console.log("=== VaultMates Deployment Summary ===");
        console.log("Owner / Deployer :", deployer);
        console.log("MembershipNFT    :", address(membership));
        console.log("Vault            :", address(vault));
        console.log("Governance       :", address(governance));
        console.log("AIRecommendation :", address(aiRec));
        console.log("Executor         :", address(executor));
        console.log("AI Oracle        :", aiOracle);
    }
}
