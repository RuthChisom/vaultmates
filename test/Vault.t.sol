// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";
import {MembershipNFT} from "../src/MembershipNFT.sol";

contract VaultTest is Test {
    MembershipNFT public nft;
    Vault public vault;

    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    address executor = address(0x4);

    function setUp() public {
        vm.startPrank(owner);
        nft = new MembershipNFT(owner);
        vault = new Vault(owner, address(nft));
        vault.setExecutor(executor);

        nft.mintMembershipNFT(alice, "");
        nft.mintMembershipNFT(bob, "");
        vm.stopPrank();

        // Fund test accounts
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    // -------------------------------------------------------------------------
    // Deposit
    // -------------------------------------------------------------------------

    function test_DepositFunds() public {
        vm.prank(alice);
        vault.depositFunds{value: 1 ether}();

        assertEq(vault.getUserBalance(alice), 1 ether);
        assertEq(vault.totalAssets(), 1 ether);
    }

    function test_MultipleDeposits() public {
        vm.prank(alice);
        vault.depositFunds{value: 2 ether}();
        vm.prank(bob);
        vault.depositFunds{value: 3 ether}();

        assertEq(vault.getUserBalance(alice), 2 ether);
        assertEq(vault.getUserBalance(bob), 3 ether);
        assertEq(vault.totalAssets(), 5 ether);
    }

    function test_NonMemberCannotDeposit() public {
        address stranger = address(0x99);
        vm.deal(stranger, 1 ether);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Vault.NotMember.selector, stranger));
        vault.depositFunds{value: 1 ether}();
    }

    function test_ZeroDepositReverts() public {
        vm.prank(alice);
        vm.expectRevert(Vault.ZeroAmount.selector);
        vault.depositFunds{value: 0}();
    }

    // -------------------------------------------------------------------------
    // Withdraw
    // -------------------------------------------------------------------------

    function test_WithdrawFunds() public {
        vm.prank(alice);
        vault.depositFunds{value: 3 ether}();

        uint256 balanceBefore = alice.balance;

        vm.prank(alice);
        vault.withdrawFunds(1 ether);

        assertEq(vault.getUserBalance(alice), 2 ether);
        assertEq(alice.balance, balanceBefore + 1 ether);
    }

    function test_CannotWithdrawMoreThanBalance() public {
        vm.prank(alice);
        vault.depositFunds{value: 1 ether}();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Vault.InsufficientBalance.selector, alice, 2 ether, 1 ether)
        );
        vault.withdrawFunds(2 ether);
    }

    // -------------------------------------------------------------------------
    // Fund Allocation
    // -------------------------------------------------------------------------

    function test_ExecutorCanAllocateFunds() public {
        vm.prank(alice);
        vault.depositFunds{value: 5 ether}();

        address destination = address(0xDEAD);

        vm.prank(executor);
        vault.allocateFunds(destination, 2 ether);

        assertEq(vault.totalAssets(), 3 ether);
        assertEq(destination.balance, 2 ether);
    }

    function test_NonExecutorCannotAllocate() public {
        vm.prank(alice);
        vault.depositFunds{value: 1 ether}();

        vm.prank(alice);
        vm.expectRevert(Vault.Unauthorized.selector);
        vault.allocateFunds(bob, 1 ether);
    }

    // -------------------------------------------------------------------------
    // Fuzz
    // -------------------------------------------------------------------------

    function testFuzz_DepositAndWithdraw(uint96 depositAmt, uint96 withdrawAmt) public {
        vm.assume(depositAmt > 0 && depositAmt <= 5 ether);
        vm.assume(withdrawAmt > 0 && withdrawAmt <= depositAmt);

        vm.deal(alice, depositAmt);
        vm.prank(alice);
        vault.depositFunds{value: depositAmt}();

        vm.prank(alice);
        vault.withdrawFunds(withdrawAmt);

        assertEq(vault.getUserBalance(alice), depositAmt - withdrawAmt);
    }
}
