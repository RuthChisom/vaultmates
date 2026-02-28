// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MembershipNFT} from "../src/MembershipNFT.sol";

contract MembershipNFTTest is Test {
    MembershipNFT public nft;

    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);

    function setUp() public {
        vm.prank(owner);
        nft = new MembershipNFT(owner);
    }

    // -------------------------------------------------------------------------
    // Minting
    // -------------------------------------------------------------------------

    function test_MintMembership() public {
        vm.prank(owner);
        nft.mintMembershipNFT(alice, "ipfs://alice-metadata");

        assertTrue(nft.checkMembership(alice));
        assertEq(nft.getMemberTokenId(alice), 1);
        assertEq(nft.totalMinted(), 1);
    }

    function test_MintEmitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit MembershipNFT.MembershipGranted(alice, 1);

        vm.prank(owner);
        nft.mintMembershipNFT(alice, "");
    }

    function test_CannotMintTwice() public {
        vm.startPrank(owner);
        nft.mintMembershipNFT(alice, "");
        vm.expectRevert(abi.encodeWithSelector(MembershipNFT.AlreadyMember.selector, alice));
        nft.mintMembershipNFT(alice, "");
        vm.stopPrank();
    }

    function test_NonOwnerCannotMint() public {
        vm.expectRevert();
        vm.prank(alice);
        nft.mintMembershipNFT(bob, "");
    }

    // -------------------------------------------------------------------------
    // Revocation
    // -------------------------------------------------------------------------

    function test_RevokeMembership() public {
        vm.startPrank(owner);
        nft.mintMembershipNFT(alice, "");
        nft.revokeMembership(alice);
        vm.stopPrank();

        assertFalse(nft.checkMembership(alice));
        assertEq(nft.getMemberTokenId(alice), 0);
    }

    function test_RevokeEmitsEvent() public {
        vm.startPrank(owner);
        nft.mintMembershipNFT(alice, "");

        vm.expectEmit(true, true, false, false);
        emit MembershipNFT.MembershipRevoked(alice, 1);

        nft.revokeMembership(alice);
        vm.stopPrank();
    }

    function test_RevokeNonMemberReverts() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MembershipNFT.NotMember.selector, alice));
        nft.revokeMembership(alice);
    }

    // -------------------------------------------------------------------------
    // Soulbound
    // -------------------------------------------------------------------------

    function test_TransferReverts() public {
        vm.prank(owner);
        nft.mintMembershipNFT(alice, "");

        vm.prank(alice);
        vm.expectRevert(MembershipNFT.SoulboundToken.selector);
        nft.transferFrom(alice, bob, 1);
    }

    // -------------------------------------------------------------------------
    // Fuzz
    // -------------------------------------------------------------------------

    function testFuzz_MultipleMembersCheckMembership(uint8 count) public {
        vm.assume(count > 0 && count < 50);
        for (uint160 i = 1; i <= count; i++) {
            address member = address(i + 100);
            vm.prank(owner);
            nft.mintMembershipNFT(member, "");
            assertTrue(nft.checkMembership(member));
        }
        assertEq(nft.totalMinted(), count);
    }
}
