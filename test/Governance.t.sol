// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Governance} from "../src/Governance.sol";
import {MembershipNFT} from "../src/MembershipNFT.sol";
import {IGovernance} from "../src/interfaces/IGovernance.sol";

contract GovernanceTest is Test {
    MembershipNFT public nft;
    Governance public gov;

    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    address carol = address(0x4);
    address destination = address(0xDEAD);

    string[] twoOptions;

    function setUp() public {
        vm.startPrank(owner);
        nft = new MembershipNFT(owner);
        gov = new Governance(owner, address(nft), 5000, 3 days);

        nft.mintMembershipNFT(alice, "");
        nft.mintMembershipNFT(bob, "");
        nft.mintMembershipNFT(carol, "");
        gov.syncMemberCount(3);
        vm.stopPrank();

        twoOptions = new string[](2);
        twoOptions[0] = "Approve";
        twoOptions[1] = "Reject";
    }

    function test_CreateProposal() public {
        vm.prank(alice);
        uint256 pid = gov.createProposal("Invest in ETH", "Allocate 1 ETH to ETH strategy", twoOptions, destination, 1 ether);

        assertEq(pid, 1);
        Governance.Proposal memory p = gov.getProposal(pid);
        assertEq(p.title, "Invest in ETH");
        assertEq(uint8(p.status), uint8(IGovernance.ProposalStatus.Active));
    }

    function test_NonMemberCannotCreateProposal() public {
        address stranger = address(0x99);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Governance.NotMember.selector, stranger));
        gov.createProposal("title", "desc", twoOptions, destination, 1 ether);
    }

    function test_ProposalRequiresMinTwoOptions() public {
        string[] memory oneOpt = new string[](1);
        oneOpt[0] = "Only";

        vm.prank(alice);
        vm.expectRevert(Governance.InvalidParams.selector);
        gov.createProposal("title", "desc", oneOpt, destination, 1 ether);
    }

    function test_MemberCanVote() public {
        vm.prank(alice);
        uint256 pid = gov.createProposal("title", "desc", twoOptions, destination, 1 ether);

        vm.prank(alice);
        gov.vote(pid, 0);

        assertEq(gov.getOptionVotes(pid, 0), 1);
    }

    function test_CannotVoteTwice() public {
        vm.prank(alice);
        uint256 pid = gov.createProposal("title", "desc", twoOptions, destination, 1 ether);

        vm.prank(alice);
        gov.vote(pid, 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Governance.AlreadyVoted.selector, alice, pid));
        gov.vote(pid, 0);
    }

    function test_CannotVoteAfterDeadline() public {
        vm.prank(alice);
        uint256 pid = gov.createProposal("title", "desc", twoOptions, destination, 1 ether);

        vm.warp(block.timestamp + 3 days + 1);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Governance.VotingClosed.selector, pid));
        gov.vote(pid, 0);
    }

    function test_ProposalPassesWithMajority() public {
        vm.prank(alice);
        uint256 pid = gov.createProposal("title", "desc", twoOptions, destination, 1 ether);

        vm.prank(alice);
        gov.vote(pid, 0);
        vm.prank(bob);
        gov.vote(pid, 0);
        vm.prank(carol);
        gov.vote(pid, 1);

        vm.warp(block.timestamp + 3 days + 1);
        gov.finalizeProposal(pid);

        assertEq(uint8(gov.getProposalStatus(pid)), uint8(IGovernance.ProposalStatus.Passed));
    }

    function test_ProposalRejectedWithoutQuorum() public {
        vm.prank(alice);
        uint256 pid = gov.createProposal("title", "desc", twoOptions, destination, 1 ether);

        vm.prank(alice);
        gov.vote(pid, 0);

        vm.warp(block.timestamp + 3 days + 1);
        gov.finalizeProposal(pid);

        assertEq(uint8(gov.getProposalStatus(pid)), uint8(IGovernance.ProposalStatus.Rejected));
    }

    function test_ProposalCanBeCancelled() public {
        vm.prank(alice);
        uint256 pid = gov.createProposal("title", "desc", twoOptions, destination, 1 ether);

        vm.prank(alice);
        gov.cancelProposal(pid);

        assertEq(uint8(gov.getProposalStatus(pid)), uint8(IGovernance.ProposalStatus.Cancelled));
    }
}
