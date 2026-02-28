// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MembershipNFT} from "../src/MembershipNFT.sol";
import {Vault} from "../src/Vault.sol";
import {Governance} from "../src/Governance.sol";
import {AIRecommendation} from "../src/AIRecommendation.sol";
import {Executor} from "../src/Executor.sol";
import {IGovernance} from "../src/interfaces/IGovernance.sol";

/// @notice End-to-end integration test covering the full VaultMates lifecycle:
///   Onboard members → Deposit funds → Create proposal → Add AI rec →
///   Vote → Finalize → Execute → Verify funds moved
contract IntegrationTest is Test {
    MembershipNFT public membership;
    Vault public vault;
    Governance public gov;
    AIRecommendation public aiRec;
    Executor public executor;

    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    address carol = address(0x4);
    address aiOracle = address(0x5);
    address investmentTarget = address(0xBEEF);

    string[] options;

    function setUp() public {
        // Deploy all contracts
        vm.startPrank(owner);
        membership = new MembershipNFT(owner);
        vault = new Vault(owner, address(membership));
        gov = new Governance(owner, address(membership), 5000, 3 days);
        aiRec = new AIRecommendation(owner, address(membership), aiOracle);
        executor = new Executor(owner, address(gov), address(vault));

        vault.setExecutor(address(executor));
        vm.stopPrank();

        // Fund test accounts
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(carol, 10 ether);

        options = new string[](2);
        options[0] = "Approve";
        options[1] = "Reject";
    }

    function test_FullLifecycle() public {
        // ---- Step 1: Onboard members ----------------------------------------
        vm.startPrank(owner);
        membership.mintMembershipNFT(alice, "ipfs://alice");
        membership.mintMembershipNFT(bob, "ipfs://bob");
        membership.mintMembershipNFT(carol, "ipfs://carol");
        gov.syncMemberCount(3);
        vm.stopPrank();

        assertTrue(membership.checkMembership(alice));
        assertTrue(membership.checkMembership(bob));
        assertTrue(membership.checkMembership(carol));

        // ---- Step 2: Members deposit funds into the vault --------------------
        vm.prank(alice);
        vault.depositFunds{value: 3 ether}();
        vm.prank(bob);
        vault.depositFunds{value: 2 ether}();

        assertEq(vault.totalAssets(), 5 ether);

        // ---- Step 3: Alice creates a proposal --------------------------------
        vm.prank(alice);
        uint256 proposalId = gov.createProposal(
            "Invest in Stablecoin Strategy",
            "Allocate 1 ETH to a stablecoin yield strategy at 0xBEEF",
            options,
            investmentTarget,
            1 ether
        );

        assertEq(proposalId, 1);
        assertEq(uint8(gov.getProposalStatus(proposalId)), uint8(IGovernance.ProposalStatus.Active));

        // ---- Step 4: AI oracle adds a recommendation ------------------------
        vm.prank(aiOracle);
        aiRec.addAIRecommendation(
            proposalId,
            "Low risk stablecoin allocation. Risk score: 20/100, Reward score: 65/100. Recommended.",
            20,
            65
        );

        assertTrue(aiRec.hasRecommendation(proposalId));
        console.log("AI Rec:", aiRec.getRecommendationText(proposalId));

        // ---- Step 5: Members review AI rec and vote -------------------------
        vm.prank(alice);
        gov.vote(proposalId, 0); // Approve
        vm.prank(bob);
        gov.vote(proposalId, 0); // Approve
        vm.prank(carol);
        gov.vote(proposalId, 0); // Approve

        // ---- Step 6: Finalize after deadline --------------------------------
        vm.warp(block.timestamp + 3 days + 1);
        gov.finalizeProposal(proposalId);

        assertEq(uint8(gov.getProposalStatus(proposalId)), uint8(IGovernance.ProposalStatus.Passed));

        // ---- Step 7: Execute automatically ----------------------------------
        uint256 targetBefore = investmentTarget.balance;
        uint256 vaultBefore = vault.totalAssets();

        executor.executeProposal(proposalId);

        assertEq(investmentTarget.balance, targetBefore + 1 ether);
        assertEq(vault.totalAssets(), vaultBefore - 1 ether);
        assertEq(uint8(gov.getProposalStatus(proposalId)), uint8(IGovernance.ProposalStatus.Executed));
        assertTrue(executor.isExecuted(proposalId));

        // ---- Step 8: Verify execution log -----------------------------------
        Executor.ExecutionLog memory log = executor.getProposalLog(proposalId);
        assertEq(log.proposalId, proposalId);
        assertEq(log.destination, investmentTarget);
        assertEq(log.executedAmount, 1 ether);

        console.log("Full lifecycle completed successfully.");
        console.log("Vault remaining:", vault.totalAssets());
        console.log("Investment target received:", investmentTarget.balance);
    }

    function test_CannotExecuteRejectedProposal() public {
        vm.startPrank(owner);
        membership.mintMembershipNFT(alice, "");
        membership.mintMembershipNFT(bob, "");
        gov.syncMemberCount(2);
        vm.stopPrank();

        vm.prank(alice);
        vault.depositFunds{value: 2 ether}();

        vm.prank(alice);
        uint256 pid = gov.createProposal("Bad idea", "desc", options, investmentTarget, 1 ether);

        // Only alice votes – below 50% quorum of 2
        // Actually with 2 members and 50% quorum, quorumNeeded = 1, so both need to vote or majority
        // Let's have alice vote reject
        vm.prank(alice);
        gov.vote(pid, 1); // Reject
        vm.prank(bob);
        gov.vote(pid, 1); // Reject

        vm.warp(block.timestamp + 3 days + 1);
        gov.finalizeProposal(pid);

        assertEq(uint8(gov.getProposalStatus(pid)), uint8(IGovernance.ProposalStatus.Rejected));

        vm.expectRevert(abi.encodeWithSelector(Executor.ProposalNotPassed.selector, pid));
        executor.executeProposal(pid);
    }

    function test_CannotExecuteTwice() public {
        vm.startPrank(owner);
        membership.mintMembershipNFT(alice, "");
        membership.mintMembershipNFT(bob, "");
        gov.syncMemberCount(2);
        vm.stopPrank();

        vm.prank(alice);
        vault.depositFunds{value: 2 ether}();

        vm.prank(alice);
        uint256 pid = gov.createProposal("title", "desc", options, investmentTarget, 1 ether);

        vm.prank(alice);
        gov.vote(pid, 0);
        vm.prank(bob);
        gov.vote(pid, 0);

        vm.warp(block.timestamp + 3 days + 1);
        gov.finalizeProposal(pid);

        executor.executeProposal(pid);

        vm.expectRevert(abi.encodeWithSelector(Executor.AlreadyExecuted.selector, pid));
        executor.executeProposal(pid);
    }
}
