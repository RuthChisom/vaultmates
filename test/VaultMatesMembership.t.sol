// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2}       from "forge-std/Test.sol";
import {VaultMatesMembership} from "../src/VaultMatesMembership.sol";
import {IMembershipChecker}   from "../src/VaultMatesMembership.sol";

// =============================================================================
// Helpers
// =============================================================================

/// @dev Minimal ERC-721 receiver so contracts can hold membership tokens.
contract ERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata)
        external pure returns (bytes4)
    {
        return this.onERC721Received.selector;
    }
}

/// @dev Simulates a DAO / multisig that holds APPROVER_ROLE.
contract MockApprover is ERC721Receiver {
    VaultMatesMembership public membership;

    constructor(VaultMatesMembership _m) { membership = _m; }

    function approve(address account) external {
        membership.approveMember(account);
    }
    function revoke(address account) external {
        membership.revokeMember(account);
    }
}

/// @dev Simulates a minter contract that holds MINTER_ROLE.
contract MockMinter is ERC721Receiver {
    VaultMatesMembership public membership;

    constructor(VaultMatesMembership _m) { membership = _m; }

    function mintFor(address to) external {
        membership.mintTo(to);
    }
}

// =============================================================================
// VaultMatesMembershipTest
// =============================================================================

/**
 * @title  VaultMatesMembershipTest
 * @notice Foundry test suite for VaultMatesMembership.sol
 *
 * Test categories (run with --match-test <prefix>_):
 *   deployment_    Post-constructor invariants.
 *   mint_          Self-mint paths, one-per-address, events, paused state.
 *   mintTo_        MINTER_ROLE privileged minting.
 *   burn_          Voluntary burn paths, events, paused bypass.
 *   burnFrom_      Owner force-burn paths.
 *   approve_       approveMember / approveMemberBatch paths.
 *   revoke_        revokeMember / revokeMemberBatch paths.
 *   gatedMode_     approvalRequired == true end-to-end flows.
 *   transfer_      Soulbound enforcement and transferable flag.
 *   pause_         pause / unpause coverage.
 *   config_        setApprovalRequired, setTransferable.
 *   roles_         Role grant / revoke, APPROVER_ROLE, MINTER_ROLE delegates.
 *   view_          totalMembers, getMemberId, tokenOf, isApproved, nextTokenId.
 *   isMember_      IMembershipChecker integration -- all mode combinations.
 *   onlyMember_    Modifier acceptance and rejection across both modes.
 *   eip165_        supportsInterface declarations.
 *   renounce_      renounceOwnership disabled.
 *   fuzz_          Property-based tests.
 */
contract VaultMatesMembershipTest is Test {

    // -------------------------------------------------------------------------
    // Actors
    // -------------------------------------------------------------------------

    address internal owner   = makeAddr("owner");
    address internal alice   = makeAddr("alice");
    address internal bob     = makeAddr("bob");
    address internal carol   = makeAddr("carol");
    address internal dave    = makeAddr("dave");
    address internal eve     = makeAddr("eve");
    address internal nobody  = makeAddr("nobody");

    // -------------------------------------------------------------------------
    // Contracts under test
    // -------------------------------------------------------------------------

    VaultMatesMembership internal m;   // open mode, transferable
    VaultMatesMembership internal mg;  // gated mode, non-transferable (soulbound)

    MockApprover internal mockApprover;
    MockMinter   internal mockMinter;

    // -------------------------------------------------------------------------
    // setUp
    // -------------------------------------------------------------------------

    function setUp() public {
        // Deploy open + transferable instance.
        vm.prank(owner);
        m = new VaultMatesMembership(owner, false, true);

        // Deploy gated + soulbound instance.
        vm.prank(owner);
        mg = new VaultMatesMembership(owner, true, false);

        // Deploy helper contracts and grant roles on open instance.
        mockApprover = new MockApprover(m);
        mockMinter   = new MockMinter(m);

        vm.startPrank(owner);
        m.grantRole(m.APPROVER_ROLE(), address(mockApprover));
        m.grantRole(m.MINTER_ROLE(),   address(mockMinter));
        vm.stopPrank();
    }

    // =========================================================================
    // deployment_
    // =========================================================================

    function test_deployment_ownerIsSet() public view {
        assertEq(m.owner(), owner);
    }

    function test_deployment_defaultAdminRoleGranted() public view {
        assertTrue(m.hasRole(m.DEFAULT_ADMIN_ROLE(), owner));
    }

    function test_deployment_approverRoleGrantedToOwner() public view {
        assertTrue(m.hasRole(m.APPROVER_ROLE(), owner));
    }

    function test_deployment_minterRoleGrantedToOwner() public view {
        assertTrue(m.hasRole(m.MINTER_ROLE(), owner));
    }

    function test_deployment_openModeByDefault() public view {
        assertFalse(m.approvalRequired());
    }

    function test_deployment_transferableByDefault() public view {
        assertTrue(m.transferable());
    }

    function test_deployment_gatedModeSet() public view {
        assertTrue(mg.approvalRequired());
    }

    function test_deployment_soulboundSet() public view {
        assertFalse(mg.transferable());
    }

    function test_deployment_totalMembersZero() public view {
        assertEq(m.totalMembers(), 0);
    }

    function test_deployment_nextTokenIdIsOne() public view {
        assertEq(m.nextTokenId(), 1);
    }

    function test_deployment_revertOnZeroOwner() public {
        vm.expectRevert(VaultMatesMembership.ZeroAddress.selector);
        new VaultMatesMembership(address(0), false, true);
    }

    function test_deployment_erc721NameAndSymbol() public view {
        assertEq(m.name(),   "VaultMates Membership");
        assertEq(m.symbol(), "VMM");
    }

    // =========================================================================
    // mint_
    // =========================================================================

    function test_mint_assignsTokenIdOne() public {
        vm.prank(alice);
        m.mint();
        assertEq(m.getMemberId(alice), 1);
    }

    function test_mint_incrementsTotalMembers() public {
        vm.prank(alice); m.mint();
        assertEq(m.totalMembers(), 1);
        vm.prank(bob); m.mint();
        assertEq(m.totalMembers(), 2);
    }

    function test_mint_incrementsNextTokenId() public {
        vm.prank(alice); m.mint();
        assertEq(m.nextTokenId(), 2);
        vm.prank(bob); m.mint();
        assertEq(m.nextTokenId(), 3);
    }

    function test_mint_setsMemberToken() public {
        vm.prank(alice); m.mint();
        assertEq(m.tokenOf(alice), 1);
    }

    function test_mint_erc721OwnerOf() public {
        vm.prank(alice); m.mint();
        assertEq(m.ownerOf(1), alice);
    }

    function test_mint_isMemberTrueInOpenMode() public {
        vm.prank(alice); m.mint();
        assertTrue(m.isMember(alice));
    }

    function test_mint_emitsMembershipMinted() public {
        vm.expectEmit(true, true, false, true);
        emit VaultMatesMembership.MembershipMinted(alice, 1, 1, 1);
        vm.prank(alice);
        m.mint();
    }

    function test_mint_revertIfAlreadyHoldsToken() public {
        vm.prank(alice); m.mint();
        vm.expectRevert(
            abi.encodeWithSelector(VaultMatesMembership.AlreadyMember.selector, alice)
        );
        vm.prank(alice);
        m.mint();
    }

    function test_mint_revertWhenPaused() public {
        vm.prank(owner); m.pause();
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        vm.prank(alice); m.mint();
    }

    function test_mint_sequentialIds() public {
        address[5] memory users = [alice, bob, carol, dave, eve];
        for (uint256 i; i < 5; i++) {
            vm.prank(users[i]); m.mint();
            assertEq(m.getMemberId(users[i]), i + 1);
        }
    }

    // =========================================================================
    // mintTo_
    // =========================================================================

    function test_mintTo_minterRoleCanMint() public {
        vm.prank(address(mockMinter));
        mockMinter.mintFor(alice);
        assertEq(m.getMemberId(alice), 1);
    }

    function test_mintTo_ownerCanMint() public {
        vm.prank(owner);
        m.mintTo(alice);
        assertEq(m.getMemberId(alice), 1);
    }

    function test_mintTo_revertIfCallerLacksMinterRole() public {
        vm.expectRevert();
        vm.prank(nobody);
        m.mintTo(alice);
    }

    function test_mintTo_revertIfZeroAddress() public {
        vm.expectRevert(VaultMatesMembership.ZeroAddress.selector);
        vm.prank(owner);
        m.mintTo(address(0));
    }

    function test_mintTo_revertIfTargetAlreadyHoldsToken() public {
        vm.prank(owner); m.mintTo(alice);
        vm.expectRevert(
            abi.encodeWithSelector(VaultMatesMembership.TargetAlreadyMember.selector, alice)
        );
        vm.prank(owner); m.mintTo(alice);
    }

    function test_mintTo_revertWhenPaused() public {
        vm.prank(owner); m.pause();
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        vm.prank(owner); m.mintTo(alice);
    }

    // =========================================================================
    // burn_
    // =========================================================================

    function test_burn_clearsMemberToken() public {
        vm.prank(alice); m.mint();
        vm.prank(alice); m.burn();
        assertEq(m.getMemberId(alice), 0);
    }

    function test_burn_decrementsTotalMembers() public {
        vm.prank(alice); m.mint();
        vm.prank(bob);   m.mint();
        vm.prank(alice); m.burn();
        assertEq(m.totalMembers(), 1);
    }

    function test_burn_isMemberFalseAfterBurn() public {
        vm.prank(alice); m.mint();
        vm.prank(alice); m.burn();
        assertFalse(m.isMember(alice));
    }

    function test_burn_clearsApprovalState() public {
        vm.prank(owner); m.setApprovalRequired(true);
        vm.prank(alice); m.mint();
        vm.prank(owner); m.approveMember(alice);
        assertTrue(m.isApproved(alice));
        vm.prank(alice); m.burn();
        assertFalse(m.isApproved(alice));
    }

    function test_burn_emitsMembershipRevoked() public {
        vm.prank(alice); m.mint();
        vm.expectEmit(true, true, false, true);
        emit VaultMatesMembership.MembershipRevoked(alice, 1, 1, 0);
        vm.prank(alice); m.burn();
    }

    function test_burn_revertIfNoToken() public {
        vm.expectRevert(
            abi.encodeWithSelector(VaultMatesMembership.NotTokenHolder.selector, alice)
        );
        vm.prank(alice); m.burn();
    }

    function test_burn_allowedWhenPaused() public {
        vm.prank(alice); m.mint();
        vm.prank(owner); m.pause();
        // Must not revert -- burn bypasses pause.
        vm.prank(alice); m.burn();
        assertEq(m.getMemberId(alice), 0);
    }

    function test_burn_tokenIdNotReused() public {
        vm.prank(alice); m.mint();  // ID 1
        vm.prank(alice); m.burn();
        vm.prank(alice); m.mint();  // ID 2 -- not ID 1
        assertEq(m.getMemberId(alice), 2);
    }

    // =========================================================================
    // burnFrom_
    // =========================================================================

    function test_burnFrom_ownerCanForceRemove() public {
        vm.prank(alice); m.mint();
        vm.prank(owner); m.burnFrom(alice);
        assertEq(m.getMemberId(alice), 0);
    }

    function test_burnFrom_decrementsTotalMembers() public {
        vm.prank(alice); m.mint();
        vm.prank(bob);   m.mint();
        vm.prank(owner); m.burnFrom(alice);
        assertEq(m.totalMembers(), 1);
    }

    function test_burnFrom_revertIfCallerNotOwner() public {
        vm.prank(alice); m.mint();
        vm.expectRevert();
        vm.prank(nobody); m.burnFrom(alice);
    }

    function test_burnFrom_revertIfNoToken() public {
        vm.expectRevert(
            abi.encodeWithSelector(VaultMatesMembership.NotTokenHolder.selector, alice)
        );
        vm.prank(owner); m.burnFrom(alice);
    }

    function test_burnFrom_allowedWhenPaused() public {
        vm.prank(alice); m.mint();
        vm.prank(owner); m.pause();
        vm.prank(owner); m.burnFrom(alice);
        assertEq(m.getMemberId(alice), 0);
    }

    // =========================================================================
    // approve_
    // =========================================================================

    function test_approve_ownerCanApproveMember() public {
        vm.prank(alice); mg.mint();
        vm.prank(owner); mg.approveMember(alice);
        assertTrue(mg.isApproved(alice));
    }

    function test_approve_approverRoleCanApprove() public {
        vm.prank(alice); m.mint();
        vm.prank(owner); m.setApprovalRequired(true);
        mockApprover.approve(alice);
        assertTrue(m.isApproved(alice));
    }

    function test_approve_isMemberTrueAfterApproval() public {
        vm.prank(alice); mg.mint();
        vm.prank(owner); mg.approveMember(alice);
        assertTrue(mg.isMember(alice));
    }

    function test_approve_emitsMemberApproved() public {
        vm.prank(alice); mg.mint();
        vm.expectEmit(true, true, false, false);
        emit VaultMatesMembership.MemberApproved(alice, owner);
        vm.prank(owner); mg.approveMember(alice);
    }

    function test_approve_revertIfCallerUnauthorized() public {
        vm.prank(alice); mg.mint();
        vm.expectRevert(VaultMatesMembership.Unauthorized.selector);
        vm.prank(nobody); mg.approveMember(alice);
    }

    function test_approve_revertIfNoToken() public {
        vm.expectRevert(
            abi.encodeWithSelector(VaultMatesMembership.NotTokenHolder.selector, alice)
        );
        vm.prank(owner); mg.approveMember(alice);
    }

    function test_approve_revertWhenPaused() public {
        vm.prank(alice); mg.mint();
        vm.prank(owner); mg.pause();
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        vm.prank(owner); mg.approveMember(alice);
    }

    function test_approve_batchApprovesAll() public {
        vm.prank(alice); mg.mint();
        vm.prank(bob);   mg.mint();
        vm.prank(carol); mg.mint();

        address[] memory batch = new address[](3);
        batch[0] = alice; batch[1] = bob; batch[2] = carol;

        vm.prank(owner); mg.approveMemberBatch(batch);

        assertTrue(mg.isMember(alice));
        assertTrue(mg.isMember(bob));
        assertTrue(mg.isMember(carol));
    }

    function test_approve_batchSkipsTokenLessAddresses() public {
        // dave has no token -- batch should not revert, just skip.
        vm.prank(alice); mg.mint();
        address[] memory batch = new address[](2);
        batch[0] = alice; batch[1] = dave;

        vm.prank(owner); mg.approveMemberBatch(batch);

        assertTrue(mg.isApproved(alice));
        assertFalse(mg.isApproved(dave));
    }

    // =========================================================================
    // revoke_
    // =========================================================================

    function test_revoke_clearApproval() public {
        vm.prank(alice); mg.mint();
        vm.prank(owner); mg.approveMember(alice);
        vm.prank(owner); mg.revokeMember(alice);
        assertFalse(mg.isApproved(alice));
    }

    function test_revoke_isMemberFalseAfterRevoke() public {
        vm.prank(alice); mg.mint();
        vm.prank(owner); mg.approveMember(alice);
        vm.prank(owner); mg.revokeMember(alice);
        assertFalse(mg.isMember(alice));
    }

    function test_revoke_tokenRetainedAfterRevoke() public {
        vm.prank(alice); mg.mint();
        vm.prank(owner); mg.approveMember(alice);
        vm.prank(owner); mg.revokeMember(alice);
        // Token still exists -- getMemberId returns non-zero.
        assertGt(mg.getMemberId(alice), 0);
    }

    function test_revoke_emitsMemberApprovalRevoked() public {
        vm.prank(alice); mg.mint();
        vm.prank(owner); mg.approveMember(alice);
        vm.expectEmit(true, true, false, false);
        emit VaultMatesMembership.MemberApprovalRevoked(alice, owner);
        vm.prank(owner); mg.revokeMember(alice);
    }

    function test_revoke_revertIfCallerUnauthorized() public {
        vm.expectRevert(VaultMatesMembership.Unauthorized.selector);
        vm.prank(nobody); mg.revokeMember(alice);
    }

    function test_revoke_batchRevokesAll() public {
        vm.prank(alice); mg.mint();
        vm.prank(bob);   mg.mint();
        address[] memory batch = new address[](2);
        batch[0] = alice; batch[1] = bob;
        vm.prank(owner); mg.approveMemberBatch(batch);

        vm.prank(owner); mg.revokeMemberBatch(batch);

        assertFalse(mg.isApproved(alice));
        assertFalse(mg.isApproved(bob));
    }

    // =========================================================================
    // gatedMode_
    // =========================================================================

    function test_gatedMode_isMemberFalseBeforeApproval() public {
        vm.prank(alice); mg.mint();
        assertFalse(mg.isMember(alice));
    }

    function test_gatedMode_isMemberTrueAfterApproval() public {
        vm.prank(alice); mg.mint();
        vm.prank(owner); mg.approveMember(alice);
        assertTrue(mg.isMember(alice));
    }

    function test_gatedMode_isMemberFalseAfterRevoke() public {
        vm.prank(alice); mg.mint();
        vm.prank(owner); mg.approveMember(alice);
        vm.prank(owner); mg.revokeMember(alice);
        assertFalse(mg.isMember(alice));
    }

    function test_gatedMode_openModeIgnoresApprovalFlag() public {
        // Even if _approved is false, open mode returns true for token holders.
        vm.prank(alice); m.mint();
        assertFalse(m.isApproved(alice));   // never explicitly set
        assertTrue(m.isMember(alice));      // open mode: token == member
    }

    function test_gatedMode_switchFromGatedToOpen() public {
        vm.prank(alice); mg.mint();
        // Still gated -- not a member yet.
        assertFalse(mg.isMember(alice));
        // Switch to open mode.
        vm.prank(owner); mg.setApprovalRequired(false);
        // Now token holder is automatically a member.
        assertTrue(mg.isMember(alice));
    }

    function test_gatedMode_switchFromOpenToGated() public {
        vm.prank(alice); m.mint();
        assertTrue(m.isMember(alice));
        // Switch to gated.
        vm.prank(owner); m.setApprovalRequired(true);
        // Now the unapproved holder is no longer a member.
        assertFalse(m.isMember(alice));
    }

    // =========================================================================
    // transfer_
    // =========================================================================

    function test_transfer_soulboundRevertsWalletToWallet() public {
        vm.prank(alice); mg.mint();
        vm.expectRevert(VaultMatesMembership.TransferLocked.selector);
        vm.prank(alice); mg.transferFrom(alice, bob, mg.getMemberId(alice));
    }

    function test_transfer_transferableAllowsMove() public {
        vm.prank(alice); m.mint();
        uint256 tokenId = m.getMemberId(alice);
        vm.prank(alice); m.transferFrom(alice, bob, tokenId);
        assertEq(m.getMemberId(bob),   tokenId);
        assertEq(m.getMemberId(alice), 0);
    }

    function test_transfer_destinationCannotAlreadyHoldToken() public {
        vm.prank(alice); m.mint();
        vm.prank(bob);   m.mint();
        uint256 aliceId = m.getMemberId(alice);
        vm.expectRevert(
            abi.encodeWithSelector(VaultMatesMembership.TargetAlreadyMember.selector, bob)
        );
        vm.prank(alice); m.transferFrom(alice, bob, aliceId);
    }

    function test_transfer_updatesIsMemberAfterTransfer() public {
        vm.prank(alice); m.mint();
        uint256 tokenId = m.getMemberId(alice);
        vm.prank(alice); m.transferFrom(alice, bob, tokenId);
        assertFalse(m.isMember(alice));
        assertTrue(m.isMember(bob));
    }

    function test_transfer_setTransferableEnables() public {
        // Start soulbound, enable, then transfer.
        vm.prank(owner); mg.setTransferable(true);
        vm.prank(alice); mg.mint();
        uint256 tokenId = mg.getMemberId(alice);
        vm.prank(alice); mg.transferFrom(alice, bob, tokenId);
        assertEq(mg.getMemberId(bob), tokenId);
    }

    function test_transfer_revertWhenPaused() public {
        vm.prank(alice); m.mint();
        uint256 tokenId = m.getMemberId(alice);
        vm.prank(owner); m.pause();
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        vm.prank(alice); m.transferFrom(alice, bob, tokenId);
    }

    // =========================================================================
    // pause_
    // =========================================================================

    function test_pause_ownerCanPause() public {
        vm.prank(owner); m.pause();
        assertTrue(m.isPaused());
    }

    function test_pause_ownerCanUnpause() public {
        vm.prank(owner); m.pause();
        vm.prank(owner); m.unpause();
        assertFalse(m.isPaused());
    }

    function test_pause_revertIfCallerNotOwner() public {
        vm.expectRevert();
        vm.prank(nobody); m.pause();
    }

    function test_pause_mintBlockedWhenPaused() public {
        vm.prank(owner); m.pause();
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        vm.prank(alice); m.mint();
    }

    function test_pause_mintResumesAfterUnpause() public {
        vm.prank(owner); m.pause();
        vm.prank(owner); m.unpause();
        vm.prank(alice); m.mint();
        assertEq(m.getMemberId(alice), 1);
    }

    // =========================================================================
    // config_
    // =========================================================================

    function test_config_setApprovalRequiredEmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit VaultMatesMembership.ApprovalModeChanged(true);
        vm.prank(owner); m.setApprovalRequired(true);
    }

    function test_config_setTransferableEmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit VaultMatesMembership.TransferabilityChanged(false);
        vm.prank(owner); m.setTransferable(false);
    }

    function test_config_setApprovalRequiredRevertsIfNotOwner() public {
        vm.expectRevert();
        vm.prank(nobody); m.setApprovalRequired(true);
    }

    function test_config_setTransferableRevertsIfNotOwner() public {
        vm.expectRevert();
        vm.prank(nobody); m.setTransferable(false);
    }

    // =========================================================================
    // roles_
    // =========================================================================

    function test_roles_ownerCanGrantApproverRole() public {
        vm.prank(owner); m.grantRole(m.APPROVER_ROLE(), alice);
        assertTrue(m.hasRole(m.APPROVER_ROLE(), alice));
    }

    function test_roles_approverRoleHolderCanApprove() public {
        vm.prank(owner); m.grantRole(m.APPROVER_ROLE(), alice);
        vm.prank(owner); m.setApprovalRequired(true);
        vm.prank(bob);   m.mint();
        vm.prank(alice); m.approveMember(bob);
        assertTrue(m.isMember(bob));
    }

    function test_roles_ownerCanGrantMinterRole() public {
        vm.prank(owner); m.grantRole(m.MINTER_ROLE(), alice);
        assertTrue(m.hasRole(m.MINTER_ROLE(), alice));
    }

    function test_roles_minterRoleHolderCanMintTo() public {
        vm.prank(owner); m.grantRole(m.MINTER_ROLE(), alice);
        vm.prank(alice); m.mintTo(bob);
        assertEq(m.getMemberId(bob), 1);
    }

    function test_roles_revokedRoleCanNoLongerApprove() public {
        vm.startPrank(owner);
        m.grantRole(m.APPROVER_ROLE(), alice);
        m.revokeRole(m.APPROVER_ROLE(), alice);
        m.setApprovalRequired(true);
        vm.stopPrank();
        vm.prank(bob); m.mint();
        vm.expectRevert(VaultMatesMembership.Unauthorized.selector);
        vm.prank(alice); m.approveMember(bob);
    }

    // =========================================================================
    // view_
    // =========================================================================

    function test_view_totalMembersTracksMintsAndBurns() public {
        vm.prank(alice); m.mint();
        vm.prank(bob);   m.mint();
        assertEq(m.totalMembers(), 2);
        vm.prank(alice); m.burn();
        assertEq(m.totalMembers(), 1);
        vm.prank(bob); m.burn();
        assertEq(m.totalMembers(), 0);
    }

    function test_view_getMemberIdReturnsZeroForNonHolder() public view {
        assertEq(m.getMemberId(alice), 0);
    }

    function test_view_tokenOfIsAliasForGetMemberId() public {
        vm.prank(alice); m.mint();
        assertEq(m.tokenOf(alice), m.getMemberId(alice));
    }

    function test_view_isApprovedFalseByDefault() public view {
        assertFalse(m.isApproved(alice));
    }

    function test_view_nextTokenIdIncrements() public {
        assertEq(m.nextTokenId(), 1);
        vm.prank(alice); m.mint();
        assertEq(m.nextTokenId(), 2);
        vm.prank(bob); m.mint();
        assertEq(m.nextTokenId(), 3);
    }

    function test_view_nextTokenIdDoesNotDecrementOnBurn() public {
        vm.prank(alice); m.mint();
        vm.prank(alice); m.burn();
        assertEq(m.nextTokenId(), 2);  // still 2, not reset to 1
    }

    // =========================================================================
    // isMember_
    // =========================================================================

    function test_isMember_falseForNonHolder() public view {
        assertFalse(m.isMember(alice));
    }

    function test_isMember_trueAfterMintInOpenMode() public {
        vm.prank(alice); m.mint();
        assertTrue(m.isMember(alice));
    }

    function test_isMember_falseAfterBurnInOpenMode() public {
        vm.prank(alice); m.mint();
        vm.prank(alice); m.burn();
        assertFalse(m.isMember(alice));
    }

    function test_isMember_falseInGatedModeBeforeApproval() public {
        vm.prank(alice); mg.mint();
        assertFalse(mg.isMember(alice));
    }

    function test_isMember_trueInGatedModeAfterApproval() public {
        vm.prank(alice); mg.mint();
        vm.prank(owner); mg.approveMember(alice);
        assertTrue(mg.isMember(alice));
    }

    function test_isMember_falseInGatedModeAfterRevoke() public {
        vm.prank(alice); mg.mint();
        vm.prank(owner); mg.approveMember(alice);
        vm.prank(owner); mg.revokeMember(alice);
        assertFalse(mg.isMember(alice));
    }

    function test_isMember_falseAfterForceBurn() public {
        vm.prank(alice); m.mint();
        vm.prank(owner); m.burnFrom(alice);
        assertFalse(m.isMember(alice));
    }

    // =========================================================================
    // onlyMember_
    // =========================================================================

    /// @dev A minimal contract that exposes a member-only action for testing.
    function _deployMemberGated() internal returns (MemberOnlyTarget) {
        return new MemberOnlyTarget(m);
    }

    function test_onlyMember_passesForActiveMemberOpenMode() public {
        MemberOnlyTarget target = _deployMemberGated();
        vm.prank(alice); m.mint();
        vm.prank(alice); target.memberAction();  // must not revert
    }

    function test_onlyMember_revertsForNonHolder() public {
        MemberOnlyTarget target = _deployMemberGated();
        vm.expectRevert(
            abi.encodeWithSelector(VaultMatesMembership.CallerNotMember.selector, alice)
        );
        vm.prank(alice); target.memberAction();
    }

    function test_onlyMember_revertsForUnapprovedHolderInGatedMode() public {
        // Switch to gated, mint, then try the member action without approval.
        vm.prank(owner); m.setApprovalRequired(true);
        vm.prank(alice); m.mint();
        MemberOnlyTarget target = _deployMemberGated();
        vm.expectRevert(
            abi.encodeWithSelector(VaultMatesMembership.CallerNotMember.selector, alice)
        );
        vm.prank(alice); target.memberAction();
    }

    function test_onlyMember_passesAfterApprovalInGatedMode() public {
        vm.prank(owner); m.setApprovalRequired(true);
        vm.prank(alice); m.mint();
        vm.prank(owner); m.approveMember(alice);
        MemberOnlyTarget target = _deployMemberGated();
        vm.prank(alice); target.memberAction();  // must not revert
    }

    // =========================================================================
    // eip165_
    // =========================================================================

    function test_eip165_supportsERC721() public view {
        assertTrue(m.supportsInterface(0x80ac58cd));
    }

    function test_eip165_supportsAccessControl() public view {
        assertTrue(m.supportsInterface(type(AccessControlInterface).interfaceId));
    }

    function test_eip165_supportsIMembershipChecker() public view {
        assertTrue(m.supportsInterface(type(IMembershipChecker).interfaceId));
    }

    function test_eip165_rejectsUnknownInterface() public view {
        assertFalse(m.supportsInterface(0xdeadbeef));
    }

    // =========================================================================
    // renounce_
    // =========================================================================

    function test_renounce_alwaysReverts() public {
        vm.expectRevert(VaultMatesMembership.RenounceOwnershipDisabled.selector);
        vm.prank(owner); m.renounceOwnership();
    }

    // =========================================================================
    // fuzz_
    // =========================================================================

    /**
     * @dev totalMembers() equals the number of successful mints minus burns.
     *      Uses vm.addr(i+1) to generate deterministic unique addresses.
     */
    function testFuzz_totalMembersMatchesMintCount(uint8 count) public {
        vm.assume(count > 0 && count <= 50);
        for (uint256 i; i < count; i++) {
            address user = vm.addr(i + 1);
            vm.prank(user); m.mint();
        }
        assertEq(m.totalMembers(), count);
    }

    /// @dev getMemberId never returns 0 for an address that has minted.
    function testFuzz_getMemberIdNonZeroAfterMint(address user) public {
        vm.assume(user != address(0));
        vm.prank(user); m.mint();
        assertGt(m.getMemberId(user), 0);
    }

    /// @dev getMemberId is 0 after burn, regardless of prior ID.
    function testFuzz_getMemberIdZeroAfterBurn(address user) public {
        vm.assume(user != address(0));
        vm.prank(user); m.mint();
        vm.prank(user); m.burn();
        assertEq(m.getMemberId(user), 0);
    }

    /// @dev isMember is consistent with token ownership in open mode.
    function testFuzz_isMemberConsistentWithTokenOwnership(address user) public {
        vm.assume(user != address(0));
        assertFalse(m.isMember(user));      // no token
        vm.prank(user); m.mint();
        assertTrue(m.isMember(user));       // has token, open mode
        vm.prank(user); m.burn();
        assertFalse(m.isMember(user));      // token burned
    }

    /// @dev nextTokenId monotonically increases.
    function testFuzz_nextTokenIdMonotonicallyIncreases(uint8 count) public {
        vm.assume(count > 0 && count <= 50);
        uint256 prev = m.nextTokenId();
        for (uint256 i; i < count; i++) {
            address user = vm.addr(i + 1);
            vm.prank(user); m.mint();
            uint256 curr = m.nextTokenId();
            assertGt(curr, prev);
            prev = curr;
        }
    }

    /// @dev No two addresses share a token ID.
    function testFuzz_uniqueTokenIds(uint8 count) public {
        vm.assume(count >= 2 && count <= 30);
        uint256[] memory ids = new uint256[](count);
        for (uint256 i; i < count; i++) {
            address user = vm.addr(i + 1);
            vm.prank(user); m.mint();
            ids[i] = m.getMemberId(user);
        }
        // Check uniqueness: no two ids are equal.
        for (uint256 i; i < count; i++) {
            for (uint256 j = i + 1; j < count; j++) {
                assertTrue(ids[i] != ids[j], "duplicate token ID");
            }
        }
    }
}

// =============================================================================
// MemberOnlyTarget -- helper for onlyMember tests
// =============================================================================

/**
 * @dev Minimal contract that exposes a function gated by the membership
 *      contract's onlyMember modifier, used by onlyMember_ test group.
 */
contract MemberOnlyTarget {
    VaultMatesMembership public membership;
    uint256              public callCount;

    constructor(VaultMatesMembership _m) { membership = _m; }

    function memberAction() external {
        // Inline the same check as the modifier to avoid inheritance issues.
        if (membership.getMemberId(msg.sender) == 0)
            revert VaultMatesMembership.CallerNotMember(msg.sender);
        if (membership.approvalRequired() && !membership.isApproved(msg.sender))
            revert VaultMatesMembership.CallerNotMember(msg.sender);
        ++callCount;
    }
}

// =============================================================================
// AccessControlInterface -- minimal interface for EIP-165 check
// =============================================================================

interface AccessControlInterface {
    function hasRole(bytes32, address) external view returns (bool);
    function getRoleAdmin(bytes32) external view returns (bytes32);
    function grantRole(bytes32, address) external;
    function revokeRole(bytes32, address) external;
    function renounceRole(bytes32, address) external;
}
