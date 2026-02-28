// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2}       from "forge-std/Script.sol";
import {VaultMatesMembership}   from "../src/VaultMatesMembership.sol";

// =============================================================================
// DeployVaultMatesMembership
// =============================================================================
//
// USAGE
// -----
//
//   Dry-run (local simulation, no broadcast):
//     forge script script/DeployVaultMatesMembership.s.sol \
//       --rpc-url $RPC_URL -vvvv
//
//   Live broadcast + Etherscan verification:
//     forge script script/DeployVaultMatesMembership.s.sol \
//       --rpc-url $RPC_URL \
//       --broadcast \
//       --verify \
//       --etherscan-api-key $ETHERSCAN_API_KEY \
//       -vvvv
//
//   Anvil (local dev, auto-funded accounts):
//     forge script script/DeployVaultMatesMembership.s.sol \
//       --target-contract DeployVaultMatesMembershipAnvil \
//       --rpc-url http://127.0.0.1:8545 \
//       --broadcast -vvvv
//
// ENV VARS
// --------
//   DEPLOYER_PRIVATE_KEY  Hex private key of the deployer EOA.
//   INITIAL_OWNER         Address that receives ownership and all initial roles.
//                         Defaults to the deployer address if unset.
//   APPROVAL_REQUIRED     "true" to deploy in gated mode; anything else = open.
//   TRANSFERABLE          "true" to allow token transfers; anything else = soulbound.
//   RPC_URL               JSON-RPC endpoint.
//   ETHERSCAN_API_KEY     Required for --verify.
// =============================================================================

contract DeployVaultMatesMembership is Script {

    VaultMatesMembership public membership;

    function run() external {
        // ── Resolve configuration ─────────────────────────────────────────────
        address initialOwner    = _resolveOwner();
        bool approvalRequired   = _resolveFlag("APPROVAL_REQUIRED");
        bool transferable       = _resolveFlag("TRANSFERABLE");
        uint256 deployerKey     = _resolvePrivateKey();

        // ── Pre-flight ────────────────────────────────────────────────────────
        require(initialOwner != address(0), "Deploy: INITIAL_OWNER is zero");

        console2.log("=== DeployVaultMatesMembership ===");
        console2.log("  Owner            :", initialOwner);
        console2.log("  approvalRequired :", approvalRequired);
        console2.log("  transferable     :", transferable);
        console2.log("  Chain ID         :", block.chainid);
        console2.log("==================================");

        // ── Deploy ────────────────────────────────────────────────────────────
        vm.startBroadcast(deployerKey);
        membership = new VaultMatesMembership(
            initialOwner,
            approvalRequired,
            transferable
        );
        vm.stopBroadcast();

        // ── Post-deploy invariant checks ──────────────────────────────────────
        _assertInvariants(initialOwner, approvalRequired, transferable);

        // ── Summary ───────────────────────────────────────────────────────────
        console2.log("");
        console2.log("Deployed VaultMatesMembership :", address(membership));
        console2.log("Next steps:");
        console2.log("  1. transferOwnership(gnosisSafe)");
        console2.log("  2. grantRole(APPROVER_ROLE, daoContract)");
        console2.log("  3. grantRole(MINTER_ROLE,   airdropContract)");
        console2.log("  4. Call setMembershipContract() on VaultMates vault");
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _resolveOwner() internal view returns (address) {
        try vm.envAddress("INITIAL_OWNER") returns (address a) {
            if (a != address(0)) return a;
        } catch {}
        try vm.envUint("DEPLOYER_PRIVATE_KEY") returns (uint256 k) {
            if (k != 0) return vm.addr(k);
        } catch {}
        return 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // Anvil #0
    }

    function _resolvePrivateKey() internal view returns (uint256) {
        try vm.envUint("DEPLOYER_PRIVATE_KEY") returns (uint256 k) {
            if (k != 0) return k;
        } catch {}
        return 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    }

    function _resolveFlag(string memory envKey) internal view returns (bool) {
        try vm.envBool(envKey) returns (bool v) { return v; } catch {}
        return false;
    }

    function _assertInvariants(
        address owner,
        bool    approvalRequired,
        bool    transferable
    ) internal view {
        require(membership.owner() == owner,
            "Deploy: owner mismatch");
        require(membership.hasRole(membership.DEFAULT_ADMIN_ROLE(), owner),
            "Deploy: DEFAULT_ADMIN_ROLE not set");
        require(membership.approvalRequired() == approvalRequired,
            "Deploy: approvalRequired mismatch");
        require(membership.transferable() == transferable,
            "Deploy: transferable mismatch");
        require(membership.totalMembers() == 0,
            "Deploy: unexpected initial members");
        require(membership.nextTokenId() == 1,
            "Deploy: nextTokenId should be 1");
    }
}

// =============================================================================
// DeployVaultMatesMembershipAnvil
// =============================================================================
//
// Local-dev seed script. Deploys and mints memberships to three test accounts
// so you can interact immediately via cast or a frontend.
//
// Usage:
//   anvil
//   forge script script/DeployVaultMatesMembership.s.sol \
//     --target-contract DeployVaultMatesMembershipAnvil \
//     --rpc-url http://127.0.0.1:8545 --broadcast -vvvv
// =============================================================================

contract DeployVaultMatesMembershipAnvil is Script {

    // Anvil default private keys (accounts 0-3)
    uint256 constant OWNER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant ALICE_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant BOB_KEY   = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 constant CAROL_KEY = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;

    function run() external {
        address owner = vm.addr(OWNER_KEY);
        address alice = vm.addr(ALICE_KEY);
        address bob   = vm.addr(BOB_KEY);
        address carol = vm.addr(CAROL_KEY);

        // Deploy in open mode, tokens transferable.
        vm.startBroadcast(OWNER_KEY);
        VaultMatesMembership membership = new VaultMatesMembership(
            owner,
            false,  // approvalRequired = false (open mode)
            true    // transferable = true
        );
        vm.stopBroadcast();

        // Alice, Bob, Carol self-mint.
        vm.prank(alice); membership.mint();
        vm.prank(bob);   membership.mint();
        vm.prank(carol); membership.mint();

        console2.log("=== Anvil Seed Deployment ===");
        console2.log("  Contract     :", address(membership));
        console2.log("  Owner        :", owner);
        console2.log("  totalMembers :", membership.totalMembers());
        console2.log("  Alice ID     :", membership.getMemberId(alice));
        console2.log("  Bob ID       :", membership.getMemberId(bob));
        console2.log("  Carol ID     :", membership.getMemberId(carol));
        console2.log("=============================");
        console2.log("Try:");
        console2.log("  cast call", address(membership), "\"totalMembers()\" --rpc-url http://127.0.0.1:8545");
        console2.log("  cast call", address(membership), "\"isMember(address)\" <addr> --rpc-url http://127.0.0.1:8545");
    }
}
