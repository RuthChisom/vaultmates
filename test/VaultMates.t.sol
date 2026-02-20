// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {VaultMates}     from "../src/VaultMates.sol";
import {IMembershipChecker} from "../src/VaultMates.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Helper contracts
// ─────────────────────────────────────────────────────────────────────────────

/// @dev A contract that accepts ETH but calls back into the vault on receive(),
///      used to verify reentrancy protection on withdraw().
contract ReentrantAttacker {
    VaultMates public vault;
    uint256    public attackAmount;

    constructor(VaultMates _vault) { vault = _vault; }

    function attack() external payable {
        attackAmount = msg.value;
        vault.deposit{value: msg.value}();
        vault.withdraw(msg.value);
    }

    receive() external payable {
        // Attempt to re-enter withdraw while the mutex is locked.
        if (address(vault).balance >= attackAmount) {
            vault.withdraw(attackAmount);
        }
    }
}

/// @dev Stub membership checker — owner-controlled allowlist.
contract StubMembershipChecker is IMembershipChecker {
    mapping(address => bool) public members;

    function allow(address account) external { members[account] = true; }
    function deny(address account)  external { members[account] = false; }

    function isMember(address account) external view override returns (bool) {
        return members[account];
    }
}

/// @dev Membership checker that always reverts (tests robustness of onlyMember).
contract RevertingChecker is IMembershipChecker {
    function isMember(address) external pure override returns (bool) {
        revert("checker down");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// VaultMates Test Suite
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @title  VaultMatesTest
 * @notice Foundry test suite for VaultMates.sol.
 *
 * Test categories (labelled with category prefix in function names):
 *   deployment_  — constructor and initial state
 *   deposit_     — deposit() and receive() accounting
 *   withdraw_    — withdraw() and withdrawAll() correctness
 *   pause_       — pause / unpause access and behaviour
 *   membership_  — onlyMember gate activation and enforcement
 *   accounting_  — shareOf / sharePercentage / totalPooledFunds views
 *   access_      — role-based access control
 *   reentrancy_  — reentrancy attack simulation
 *   fuzz_        — property-based fuzz tests
 *
 * Run the full suite:
 *   forge test -vvv
 *
 * Run a single category:
 *   forge test --match-test "deposit_" -vvv
 *
 * Run with gas report:
 *   forge test --gas-report
 */
contract VaultMatesTest is Test {

    // ── Fixtures ─────────────────────────────────────────────────────────────

    VaultMates             public vault;
    StubMembershipChecker  public checker;

    address public owner   = makeAddr("owner");
    address public alice   = makeAddr("alice");
    address public bob     = makeAddr("bob");
    address public carol   = makeAddr("carol");
    address public stranger = makeAddr("stranger");

    uint256 constant ONE_ETH  = 1 ether;
    uint256 constant HALF_ETH = 0.5 ether;

    // ── Events (must mirror contract exactly for vm.expectEmit) ──────────────

    event Deposited(
        address indexed depositor,
        uint256 indexed amount,
        uint256         newBalance,
        uint256         vaultTotal
    );
    event Withdrawn(
        address indexed recipient,
        uint256 indexed amount,
        uint256         remainingBalance,
        uint256         vaultTotal
    );
    event VaultPaused(address indexed by);
    event VaultUnpaused(address indexed by);
    event MembershipContractUpdated(address indexed oldContract, address indexed newContract);

    // ── Setup ─────────────────────────────────────────────────────────────────

    function setUp() public {
        vault   = new VaultMates(owner);
        checker = new StubMembershipChecker();

        // Fund test accounts
        deal(alice,   10 ether);
        deal(bob,     10 ether);
        deal(carol,   10 ether);
        deal(stranger, 5 ether);
    }

    // =========================================================================
    // DEPLOYMENT
    // =========================================================================

    function test_deployment_ownerIsSet() public view {
        assertEq(vault.owner(), owner);
    }

    function test_deployment_ownerHasAdminRole() public view {
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), owner));
    }

    function test_deployment_vaultStartsEmpty() public view {
        assertEq(vault.totalPooledFunds(), 0);
        assertEq(vault.totalDeposited(),   0);
        assertEq(vault.depositorCount(),   0);
    }

    function test_deployment_notPaused() public view {
        assertFalse(vault.isPaused());
    }

    function test_deployment_membershipGateDisabledByDefault() public view {
        assertEq(vault.membershipContract(), address(0));
    }

    function test_deployment_revertIfZeroOwner() public {
        vm.expectRevert(VaultMates.ZeroAddress.selector);
        new VaultMates(address(0));
    }

    // =========================================================================
    // DEPOSIT
    // =========================================================================

    function test_deposit_creditsBalance() public {
        vm.prank(alice);
        vault.deposit{value: ONE_ETH}();

        assertEq(vault.balanceOf(alice), ONE_ETH);
    }

    function test_deposit_updatesTotalDeposited() public {
        vm.prank(alice);
        vault.deposit{value: ONE_ETH}();

        assertEq(vault.totalDeposited(), ONE_ETH);
    }

    function test_deposit_updatesTotalPooledFunds() public {
        vm.prank(alice);
        vault.deposit{value: ONE_ETH}();

        assertEq(vault.totalPooledFunds(), ONE_ETH);
    }

    function test_deposit_registersDepositor() public {
        vm.prank(alice);
        vault.deposit{value: ONE_ETH}();

        assertEq(vault.depositorCount(), 1);
        assertEq(vault.depositorAt(0), alice);
    }

    function test_deposit_multipleDepositors() public {
        vm.prank(alice); vault.deposit{value: ONE_ETH}();
        vm.prank(bob);   vault.deposit{value: ONE_ETH}();

        assertEq(vault.depositorCount(), 2);
        assertEq(vault.totalDeposited(), 2 * ONE_ETH);
    }

    function test_deposit_sameDepositorTwiceNotDuplicated() public {
        vm.startPrank(alice);
        vault.deposit{value: ONE_ETH}();
        vault.deposit{value: ONE_ETH}();
        vm.stopPrank();

        assertEq(vault.depositorCount(), 1);
        assertEq(vault.balanceOf(alice), 2 * ONE_ETH);
    }

    function test_deposit_emitsEvent() public {
        vm.expectEmit(true, true, false, true, address(vault));
        emit Deposited(alice, ONE_ETH, ONE_ETH, ONE_ETH);

        vm.prank(alice);
        vault.deposit{value: ONE_ETH}();
    }

    function test_deposit_revertOnZeroValue() public {
        vm.expectRevert(VaultMates.ZeroAmount.selector);
        vm.prank(alice);
        vault.deposit{value: 0}();
    }

    function test_deposit_viaReceiveFallback() public {
        // Plain ETH transfer should also be tracked.
        vm.prank(alice);
        (bool ok,) = address(vault).call{value: ONE_ETH}("");
        assertTrue(ok);

        assertEq(vault.balanceOf(alice), ONE_ETH);
        assertEq(vault.totalDeposited(), ONE_ETH);
    }

    function test_deposit_revertWhenPaused() public {
        vm.prank(owner);
        vault.pause();

        vm.expectRevert(); // EnforcedPause
        vm.prank(alice);
        vault.deposit{value: ONE_ETH}();
    }

    // =========================================================================
    // WITHDRAW
    // =========================================================================

    function test_withdraw_partialAmount() public {
        vm.prank(alice);
        vault.deposit{value: ONE_ETH}();

        uint256 aliceBefore = alice.balance;

        vm.prank(alice);
        vault.withdraw(HALF_ETH);

        assertEq(vault.balanceOf(alice), HALF_ETH);
        assertEq(alice.balance, aliceBefore + HALF_ETH);
    }

    function test_withdraw_updatesVaultBalance() public {
        vm.prank(alice); vault.deposit{value: ONE_ETH}();
        vm.prank(bob);   vault.deposit{value: ONE_ETH}();

        vm.prank(alice);
        vault.withdraw(ONE_ETH);

        assertEq(vault.totalDeposited(),   ONE_ETH); // bob's 1 ETH remains
        assertEq(vault.totalPooledFunds(), ONE_ETH);
    }

    function test_withdraw_emitsEvent() public {
        vm.prank(alice);
        vault.deposit{value: ONE_ETH}();

        vm.expectEmit(true, true, false, true, address(vault));
        emit Withdrawn(alice, ONE_ETH, 0, 0);

        vm.prank(alice);
        vault.withdraw(ONE_ETH);
    }

    function test_withdraw_revertOnZero() public {
        vm.prank(alice); vault.deposit{value: ONE_ETH}();

        vm.expectRevert(VaultMates.ZeroAmount.selector);
        vm.prank(alice);
        vault.withdraw(0);
    }

    function test_withdraw_revertInsufficientBalance() public {
        vm.prank(alice);
        vault.deposit{value: ONE_ETH}();

        vm.expectRevert(
            abi.encodeWithSelector(VaultMates.InsufficientBalance.selector, 2 ether, ONE_ETH)
        );
        vm.prank(alice);
        vault.withdraw(2 ether);
    }

    function test_withdraw_revertWhenPaused() public {
        vm.prank(alice); vault.deposit{value: ONE_ETH}();
        vm.prank(owner); vault.pause();

        vm.expectRevert(); // EnforcedPause
        vm.prank(alice);
        vault.withdraw(ONE_ETH);
    }

    function test_withdraw_cannotExceedOwnBalance() public {
        vm.prank(alice); vault.deposit{value: ONE_ETH}();
        vm.prank(bob);   vault.deposit{value: 2 ether}();

        // alice cannot withdraw bob's ETH
        vm.expectRevert(
            abi.encodeWithSelector(VaultMates.InsufficientBalance.selector, 2 ether, ONE_ETH)
        );
        vm.prank(alice);
        vault.withdraw(2 ether);
    }

    // ── withdrawAll ──────────────────────────────────────────────────────────

    function test_withdrawAll_drainsSenderBalance() public {
        vm.prank(alice);
        vault.deposit{value: ONE_ETH}();

        uint256 aliceBefore = alice.balance;

        vm.prank(alice);
        vault.withdrawAll();

        assertEq(vault.balanceOf(alice), 0);
        assertEq(alice.balance, aliceBefore + ONE_ETH);
    }

    function test_withdrawAll_revertIfNoBalance() public {
        vm.expectRevert(VaultMates.ZeroAmount.selector);
        vm.prank(alice);
        vault.withdrawAll();
    }

    function test_withdrawAll_doesNotAffectOtherDepositors() public {
        vm.prank(alice); vault.deposit{value: ONE_ETH}();
        vm.prank(bob);   vault.deposit{value: 2 ether}();

        vm.prank(alice);
        vault.withdrawAll();

        assertEq(vault.balanceOf(bob), 2 ether);
        assertEq(vault.totalDeposited(), 2 ether);
    }

    // =========================================================================
    // PAUSE
    // =========================================================================

    function test_pause_ownerCanPause() public {
        vm.prank(owner);
        vault.pause();

        assertTrue(vault.isPaused());
    }

    function test_pause_emitsEvent() public {
        vm.expectEmit(true, false, false, false, address(vault));
        emit VaultPaused(owner);

        vm.prank(owner);
        vault.pause();
    }

    function test_unpause_ownerCanUnpause() public {
        vm.prank(owner); vault.pause();
        vm.prank(owner); vault.unpause();

        assertFalse(vault.isPaused());
    }

    function test_unpause_emitsEvent() public {
        vm.prank(owner); vault.pause();

        vm.expectEmit(true, false, false, false, address(vault));
        emit VaultUnpaused(owner);

        vm.prank(owner);
        vault.unpause();
    }

    function test_pause_revertIfNotOwner() public {
        vm.expectRevert(); // OwnableUnauthorizedAccount
        vm.prank(alice);
        vault.pause();
    }

    function test_pause_depositsRestoredAfterUnpause() public {
        vm.prank(owner); vault.pause();
        vm.prank(owner); vault.unpause();

        vm.prank(alice);
        vault.deposit{value: ONE_ETH}();

        assertEq(vault.balanceOf(alice), ONE_ETH);
    }

    // =========================================================================
    // MEMBERSHIP GATE
    // =========================================================================

    function test_membership_depositOpenWhenGateDisabled() public {
        // No membership contract set — anyone can deposit.
        vm.prank(stranger);
        vault.deposit{value: ONE_ETH}();

        assertEq(vault.balanceOf(stranger), ONE_ETH);
    }

    function test_membership_setContractEmitsEvent() public {
        vm.expectEmit(true, true, false, false, address(vault));
        emit MembershipContractUpdated(address(0), address(checker));

        vm.prank(owner);
        vault.setMembershipContract(address(checker));
    }

    function test_membership_allowedMemberCanDeposit() public {
        checker.allow(alice);
        vm.prank(owner);
        vault.setMembershipContract(address(checker));

        vm.prank(alice);
        vault.deposit{value: ONE_ETH}();

        assertEq(vault.balanceOf(alice), ONE_ETH);
    }

    function test_membership_nonMemberCannotDeposit() public {
        // alice is NOT allowed in checker
        vm.prank(owner);
        vault.setMembershipContract(address(checker));

        vm.expectRevert(
            abi.encodeWithSelector(VaultMates.NotAMember.selector, alice)
        );
        vm.prank(alice);
        vault.deposit{value: ONE_ETH}();
    }

    function test_membership_revertingCheckerBlocksDeposit() public {
        RevertingChecker rc = new RevertingChecker();
        vm.prank(owner);
        vault.setMembershipContract(address(rc));

        vm.expectRevert(
            abi.encodeWithSelector(VaultMates.NotAMember.selector, alice)
        );
        vm.prank(alice);
        vault.deposit{value: ONE_ETH}();
    }

    function test_membership_disableGateRestoresOpenAccess() public {
        checker.allow(alice); // only alice allowed
        vm.prank(owner); vault.setMembershipContract(address(checker));
        vm.prank(owner); vault.setMembershipContract(address(0)); // disable

        // stranger (not in allowlist) can now deposit
        vm.prank(stranger);
        vault.deposit{value: ONE_ETH}();
        assertEq(vault.balanceOf(stranger), ONE_ETH);
    }

    function test_membership_onlyOwnerCanSetContract() public {
        vm.expectRevert(); // OwnableUnauthorizedAccount
        vm.prank(alice);
        vault.setMembershipContract(address(checker));
    }

    // =========================================================================
    // ACCOUNTING VIEWS
    // =========================================================================

    function test_accounting_shareOf() public {
        vm.prank(alice); vault.deposit{value: ONE_ETH}();
        vm.prank(bob);   vault.deposit{value: 3 ether}();

        (uint256 num, uint256 den) = vault.shareOf(alice);
        assertEq(num, ONE_ETH);
        assertEq(den, 4 ether);
    }

    function test_accounting_sharePercentage_25pct() public {
        vm.prank(alice); vault.deposit{value: ONE_ETH}();
        vm.prank(bob);   vault.deposit{value: 3 ether}();

        // alice: 1/4 → 2500 bps
        assertEq(vault.sharePercentage(alice), 2_500);
    }

    function test_accounting_sharePercentage_100pct() public {
        vm.prank(alice);
        vault.deposit{value: ONE_ETH}();

        assertEq(vault.sharePercentage(alice), 10_000);
    }

    function test_accounting_sharePercentage_zeroWhenVaultEmpty() public view {
        assertEq(vault.sharePercentage(alice), 0);
    }

    function test_accounting_sharePercentage_zeroAfterFullWithdraw() public {
        vm.prank(alice); vault.deposit{value: ONE_ETH}();
        vm.prank(bob);   vault.deposit{value: ONE_ETH}();

        vm.prank(alice);
        vault.withdrawAll();

        assertEq(vault.sharePercentage(alice), 0);
        assertEq(vault.sharePercentage(bob), 10_000);
    }

    function test_accounting_depositorsSlice() public {
        vm.prank(alice); vault.deposit{value: ONE_ETH}();
        vm.prank(bob);   vault.deposit{value: ONE_ETH}();
        vm.prank(carol); vault.deposit{value: ONE_ETH}();

        address[] memory slice = vault.depositorsSlice(0, 2);
        assertEq(slice.length, 2);
        assertEq(slice[0], alice);
        assertEq(slice[1], bob);
    }

    function test_accounting_depositorsSliceClampedEnd() public {
        vm.prank(alice); vault.deposit{value: ONE_ETH}();
        vm.prank(bob);   vault.deposit{value: ONE_ETH}();

        // end=999 should clamp to 2
        address[] memory slice = vault.depositorsSlice(0, 999);
        assertEq(slice.length, 2);
    }

    function test_accounting_depositorsSliceRevertInvalidRange() public {
        vm.prank(alice); vault.deposit{value: ONE_ETH}();

        vm.expectRevert(
            abi.encodeWithSelector(VaultMates.InvalidRange.selector, 5, 1)
        );
        vault.depositorsSlice(5, 1);
    }

    // =========================================================================
    // ACCESS CONTROL
    // =========================================================================

    function test_access_nonOwnerCannotPause() public {
        vm.expectRevert();
        vm.prank(alice);
        vault.pause();
    }

    function test_access_nonExecutorCannotCallExecuteProposal() public {
        vm.expectRevert(); // AccessControlUnauthorizedAccount
        vm.prank(alice);
        vault.executeProposal(address(this), 0, abi.encodeWithSignature("foo()"));
    }

    function test_access_executorCanCallExecuteProposal() public {
        // Grant EXECUTOR_ROLE to alice
        vm.prank(owner);
        vault.grantRole(vault.EXECUTOR_ROLE(), alice);

        // Deposit ETH so vault has funds
        vm.prank(bob);
        vault.deposit{value: ONE_ETH}();

        // Call a view function on the vault itself as the target
        vm.prank(alice);
        vault.executeProposal(
            address(vault),
            0,
            abi.encodeWithSignature("totalPooledFunds()")
        );
    }

    function test_access_executeProposalRevertOnZeroTarget() public {
        vm.prank(owner);
        vault.grantRole(vault.EXECUTOR_ROLE(), alice);

        vm.expectRevert(VaultMates.ZeroAddress.selector);
        vm.prank(alice);
        vault.executeProposal(address(0), 0, "");
    }

    // =========================================================================
    // REENTRANCY
    // =========================================================================

    function test_reentrancy_withdrawBlockedByMutex() public {
        ReentrantAttacker attacker = new ReentrantAttacker(vault);
        deal(address(attacker), 2 ether);

        // The attacker deposits 1 ETH then attempts a reentrant withdraw in its
        // receive(). nonReentrant should cause the inner call to revert, and the
        // outer withdraw should also revert (or succeed with correct final state).
        //
        // Either way, the attacker must end up with AT MOST their deposited amount.
        uint256 vaultBefore = address(vault).balance;

        vm.expectRevert(); // nonReentrant reverts the inner call, outer reverts too
        attacker.attack{value: ONE_ETH}();

        // Vault balance should be unchanged (attack fully reverted)
        assertEq(address(vault).balance, vaultBefore);
    }

    // =========================================================================
    // FUZZ TESTS
    // =========================================================================

    /**
     * @dev Property: any non-zero deposit must increase the depositor's balance
     *      and totalDeposited by exactly msg.value.
     */
    function testFuzz_deposit_balanceIncreasesExactly(uint96 amount) public {
        vm.assume(amount > 0);

        deal(alice, uint256(amount));

        uint256 balBefore   = vault.balanceOf(alice);
        uint256 totalBefore = vault.totalDeposited();

        vm.prank(alice);
        vault.deposit{value: amount}();

        assertEq(vault.balanceOf(alice),  balBefore   + amount);
        assertEq(vault.totalDeposited(),  totalBefore + amount);
    }

    /**
     * @dev Property: withdraw(amount) transfers exactly `amount` to the caller
     *      and reduces their balance and totalDeposited by exactly `amount`.
     */
    function testFuzz_withdraw_exactTransfer(uint96 depositAmt, uint96 withdrawAmt) public {
        vm.assume(depositAmt  > 0);
        vm.assume(withdrawAmt > 0 && withdrawAmt <= depositAmt);

        deal(alice, depositAmt);
        vm.prank(alice); vault.deposit{value: depositAmt}();

        uint256 aliceBefore = alice.balance;
        uint256 totalBefore = vault.totalDeposited();

        vm.prank(alice);
        vault.withdraw(withdrawAmt);

        assertEq(alice.balance,          aliceBefore + withdrawAmt);
        assertEq(vault.balanceOf(alice), depositAmt  - withdrawAmt);
        assertEq(vault.totalDeposited(), totalBefore - withdrawAmt);
    }

    /**
     * @dev Property: sharePercentage always returns a value in [0, 10_000].
     */
    function testFuzz_sharePercentage_bounded(uint96 aliceAmt, uint96 bobAmt) public {
        vm.assume(aliceAmt > 0 && bobAmt > 0);

        deal(alice, aliceAmt);
        deal(bob,   bobAmt);

        vm.prank(alice); vault.deposit{value: aliceAmt}();
        vm.prank(bob);   vault.deposit{value: bobAmt}();

        uint256 bps = vault.sharePercentage(alice);
        assertLe(bps, 10_000);
    }

    /**
     * @dev Property: sum of all depositor sharePercentages <= 10_000
     *      (floor division may leave a small remainder, so strict equality
     *       is not guaranteed — but it must never exceed 100%).
     */
    function testFuzz_sharePercentage_sumNeverExceeds100pct(
        uint96 a,
        uint96 b,
        uint96 c
    ) public {
        vm.assume(a > 0 && b > 0 && c > 0);

        deal(alice, a); deal(bob, b); deal(carol, c);

        vm.prank(alice); vault.deposit{value: a}();
        vm.prank(bob);   vault.deposit{value: b}();
        vm.prank(carol); vault.deposit{value: c}();

        uint256 total = vault.sharePercentage(alice)
                      + vault.sharePercentage(bob)
                      + vault.sharePercentage(carol);

        assertLe(total, 10_000);
    }
}
