// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AIRecommendation} from "../src/AIRecommendation.sol";
import {MembershipNFT} from "../src/MembershipNFT.sol";

contract AIRecommendationTest is Test {
    MembershipNFT public nft;
    AIRecommendation public aiRec;

    address owner = address(0x1);
    address oracle = address(0x2);
    address alice = address(0x3);

    function setUp() public {
        vm.startPrank(owner);
        nft = new MembershipNFT(owner);
        aiRec = new AIRecommendation(owner, address(nft), oracle);
        nft.mintMembershipNFT(alice, "");
        vm.stopPrank();
    }

    function test_OracleCanAddRecommendation() public {
        vm.prank(oracle);
        aiRec.addAIRecommendation(
            1,
            "Allocating 30% to ETH has moderate risk with good long-term reward potential.",
            40,
            75
        );

        assertTrue(aiRec.hasRecommendation(1));
        AIRecommendation.Recommendation memory r = aiRec.getAIRecommendation(1);
        assertEq(r.riskScore, 40);
        assertEq(r.rewardScore, 75);
    }

    function test_NonOracleCannotAddRecommendation() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AIRecommendation.NotOracle.selector, alice));
        aiRec.addAIRecommendation(1, "text", 50, 50);
    }

    function test_OwnerCanAlsoAddRecommendation() public {
        vm.prank(owner);
        aiRec.addAIRecommendation(1, "Owner recommendation", 20, 80);
        assertTrue(aiRec.hasRecommendation(1));
    }

    function test_CannotAddDuplicateRecommendation() public {
        vm.startPrank(oracle);
        aiRec.addAIRecommendation(1, "first", 10, 90);
        vm.expectRevert(abi.encodeWithSelector(AIRecommendation.RecommendationExists.selector, 1));
        aiRec.addAIRecommendation(1, "second", 20, 80);
        vm.stopPrank();
    }

    function test_UpdateRecommendation() public {
        vm.startPrank(oracle);
        aiRec.addAIRecommendation(1, "original", 30, 70);
        aiRec.updateAIRecommendation(1, "updated", 55, 60);
        vm.stopPrank();

        AIRecommendation.Recommendation memory r = aiRec.getAIRecommendation(1);
        assertEq(r.text, "updated");
        assertEq(r.riskScore, 55);
    }

    function test_GetRecommendationNotFoundReverts() public {
        vm.expectRevert(abi.encodeWithSelector(AIRecommendation.RecommendationNotFound.selector, 99));
        aiRec.getAIRecommendation(99);
    }

    function test_ScoreOutOfRangeReverts() public {
        vm.prank(oracle);
        vm.expectRevert(AIRecommendation.InvalidScore.selector);
        aiRec.addAIRecommendation(1, "text", 101, 50);
    }

    function test_SetNewOracle() public {
        address newOracle = address(0x5);
        vm.prank(owner);
        aiRec.setAIOracle(newOracle);
        assertEq(aiRec.aiOracle(), newOracle);
    }
}
