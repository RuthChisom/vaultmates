// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {VaultMates}       from "../src/VaultMates.sol";

// ─────────────────────────────────────────────────────────────────────────────
// DeployVaultMates
// ─────────────────────────────────────────────────────────────────────────────
//
// USAGE
// ──────
//
//  1. Dry-run (local simulation, no broadcast, no gas spent):
//       forge script script/DeployVaultMates.s.sol \
//         --rpc-url $RPC_URL \
//         -vvvv
//
//  2. Live broadcast + Etherscan verification:
//       forge script script/DeployVaultMates.s.sol \
//         --rpc-url $RPC_URL \
//         --broadcast \
//         --verify \
//         --etherscan-api-key $ETHERSCAN_API_KEY \
//         -vvvv
//
//  3. Resume a failed broadcast (e.g. after nonce gap):
//       forge script script/DeployVaultMates.s.sol \
//         --rpc-url $RPC_URL \
//         --broadcast \
//         --resume \
//         -vvvv
//
//  4. Ledger hardware wallet:
//       forge script script/DeployVaultMates.s.sol \
//         --rpc-url $RPC_URL \
//         --broadcast \
//         --ledger \
//         --mnemonic-derivation-path "m/44'/60'/0'/0/0" \
//         -vvvv
//
// REQUIRED ENV VARS
// ──────────────────
//   DEPLOYER_PRIVATE_KEY   Hex private key of the deployer EOA (for --broadcast).
//                          Not needed for dry-run or --ledger mode.
//   INITIAL_OWNER          Checksummed address that receives Ownable ownership
//                          and DEFAULT_ADMIN_ROLE. Defaults to deployer if unset.
//   RPC_URL                JSON-RPC endpoint (Alchemy / Infura / Anvil / etc.).
//   ETHERSCAN_API_KEY      Required for --verify. Leave unset for local runs.
//
// OPTIONAL ENV VARS
// ──────────────────
//   SALT                   32-byte hex salt for CREATE2 deterministic deployment.
//                          Leave unset to use standard CREATE (nonce-based).
//
// SUPPORTED NETWORKS (set RPC_URL accordingly)
// ──────────────────────────────────────────────
//   Mainnet   — https://eth-mainnet.g.alchemy.com/v2/<key>
//   Sepolia   — https://eth-sepolia.g.alchemy.com/v2/<key>
//   Holesky   — https://ethereum-holesky.publicnode.com
//   Anvil     — http://127.0.0.1:8545   (forge anvil)
//
// OUTPUT
// ───────
//   Deployment details are printed to stdout and written to:
//     broadcast/DeployVaultMates.s.sol/<chainId>/run-latest.json
//
// ─────────────────────────────────────────────────────────────────────────────

contract DeployVaultMates is Script {

    // ── Deployment artefact (populated by run()) ──────────────────────────────
    VaultMates public vault;

    // ── run() — primary entry-point called by `forge script` ─────────────────

    function run() external {

        // ── 1. Resolve configuration from environment ─────────────────────────

        address initialOwner = _resolveOwner();
        bytes32 salt         = _resolveSalt();
        bool    useCREATE2   = (salt != bytes32(0));

        // ── 2. Pre-flight checks ───────────────────────────────────────────────

        _preflight(initialOwner);

        // ── 3. Begin broadcast (no-op in dry-run) ────────────────────────────

        uint256 deployerKey = _resolvePrivateKey();
        vm.startBroadcast(deployerKey);

        // ── 4. Deploy ─────────────────────────────────────────────────────────

        if (useCREATE2) {
            vault = new VaultMates{salt: salt}(initialOwner);
        } else {
            vault = new VaultMates(initialOwner);
        }

        // ── 5. Post-deployment invariant checks ───────────────────────────────

        _assertInvariants(initialOwner);

        vm.stopBroadcast();

        // ── 6. Print deployment summary ───────────────────────────────────────

        _printSummary(initialOwner, useCREATE2, salt);
    }

    // =========================================================================
    // Internal — Configuration Helpers
    // =========================================================================

    /**
     * @dev Resolves `INITIAL_OWNER` env var.
     *      Falls back to the deployer address derived from `DEPLOYER_PRIVATE_KEY`.
     *      Falls back further to the default Anvil account #0 for local runs.
     */
    function _resolveOwner() internal view returns (address owner) {
        // Explicit override wins.
        try vm.envAddress("INITIAL_OWNER") returns (address a) {
            if (a != address(0)) return a;
        } catch {}

        // Derive from private key if available.
        try vm.envUint("DEPLOYER_PRIVATE_KEY") returns (uint256 key) {
            if (key != 0) return vm.addr(key);
        } catch {}

        // Anvil default account #0 as last resort (local dev only).
        return 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    }

    /**
     * @dev Resolves `DEPLOYER_PRIVATE_KEY` env var.
     *      Returns the Anvil default test key (0xac0974…) when unset —
     *      safe for local development, but never use on mainnet.
     */
    function _resolvePrivateKey() internal view returns (uint256 key) {
        try vm.envUint("DEPLOYER_PRIVATE_KEY") returns (uint256 k) {
            if (k != 0) return k;
        } catch {}

        // Anvil account #0 test private key — local only.
        return 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    }

    /**
     * @dev Resolves `SALT` env var for CREATE2.
     *      Returns bytes32(0) when unset, signalling standard CREATE.
     */
    function _resolveSalt() internal view returns (bytes32 salt) {
        try vm.envBytes32("SALT") returns (bytes32 s) {
            return s;
        } catch {
            return bytes32(0);
        }
    }

    // =========================================================================
    // Internal — Pre-flight Checks
    // =========================================================================

    /**
     * @dev Asserts safe deployment preconditions before spending any gas.
     *      All checks revert with descriptive messages to aid CI diagnosis.
     */
    function _preflight(address initialOwner) internal view {
        // Owner must be a non-zero address.
        require(
            initialOwner != address(0),
            "DeployVaultMates: INITIAL_OWNER is the zero address"
        );

        // Warn if deploying to mainnet with an EOA owner (multisig strongly preferred).
        if (block.chainid == 1) {
            uint256 ownerCodeSize;
            assembly { ownerCodeSize := extcodesize(initialOwner) }
            if (ownerCodeSize == 0) {
                console2.log(
                    "[WARN] Mainnet deployment with an EOA owner. "
                    "Consider using a Gnosis Safe or Timelock as initialOwner."
                );
            }
        }

        console2.log("=== DeployVaultMates pre-flight ===");
        console2.log("  Chain ID    :", block.chainid);
        console2.log("  Block       :", block.number);
        console2.log("  Owner       :", initialOwner);
        console2.log("  Network     :", _networkName());
        console2.log("===================================");
    }

    // =========================================================================
    // Internal — Post-deployment Invariant Checks
    // =========================================================================

    /**
     * @dev Checks critical post-deployment state.
     *      Reverts loudly if any invariant is broken — better to fail on deploy
     *      than to operate with misconfigured permissions.
     */
    function _assertInvariants(address initialOwner) internal view {

        // Ownership must be set correctly.
        require(
            vault.owner() == initialOwner,
            "DeployVaultMates: owner mismatch after deploy"
        );

        // DEFAULT_ADMIN_ROLE must be held by initialOwner.
        require(
            vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), initialOwner),
            "DeployVaultMates: DEFAULT_ADMIN_ROLE not granted"
        );

        // Vault must start unpaused.
        require(
            !vault.isPaused(),
            "DeployVaultMates: vault is paused post-deploy"
        );

        // Vault must start empty.
        require(
            vault.totalPooledFunds() == 0,
            "DeployVaultMates: vault has unexpected balance post-deploy"
        );

        // Membership gate must be disabled by default.
        require(
            vault.membershipContract() == address(0),
            "DeployVaultMates: membership gate unexpectedly active"
        );

        // Depositor list must be empty.
        require(
            vault.depositorCount() == 0,
            "DeployVaultMates: unexpected depositors post-deploy"
        );

        // EXECUTOR_ROLE and GOVERNANCE_ROLE must NOT be pre-assigned.
        require(
            !vault.hasRole(vault.EXECUTOR_ROLE(), initialOwner),
            "DeployVaultMates: EXECUTOR_ROLE must not be pre-assigned to owner"
        );
        require(
            !vault.hasRole(vault.GOVERNANCE_ROLE(), initialOwner),
            "DeployVaultMates: GOVERNANCE_ROLE must not be pre-assigned to owner"
        );
    }

    // =========================================================================
    // Internal — Logging
    // =========================================================================

    function _printSummary(
        address initialOwner,
        bool    useCREATE2,
        bytes32 salt
    ) internal view {
        console2.log("");
        console2.log("==================================================");
        console2.log("         VaultMates Deployment Complete           ");
        console2.log("==================================================");
        console2.log("  Contract  :", address(vault));
        console2.log("  Owner     :", initialOwner);
        console2.log("  Network   :", _networkName());
        console2.log("  Chain ID  :", block.chainid);
        console2.log("  Method    :", useCREATE2 ? "CREATE2" : "CREATE");
        if (useCREATE2) {
            console2.logBytes32(salt);
        }
        console2.log("--------------------------------------------------");
        console2.log("  NEXT STEPS:");
        console2.log("  1. Transfer ownership to a Gnosis Safe or");
        console2.log("     Timelock if deploying to production.");
        console2.log("  2. Grant GOVERNANCE_ROLE to your DAO contract");
        console2.log("     once it is deployed and audited.");
        console2.log("  3. Grant EXECUTOR_ROLE to the proposal");
        console2.log("     execution contract ONLY after audit.");
        console2.log("  4. Call setMembershipContract() to activate");
        console2.log("     the membership gate when ready.");
        console2.log("==================================================");
        console2.log("");
    }

    function _networkName() internal view returns (string memory) {
        uint256 id = block.chainid;
        if (id == 1)        return "Ethereum Mainnet";
        if (id == 11155111) return "Sepolia Testnet";
        if (id == 17000)    return "Holesky Testnet";
        if (id == 31337)    return "Anvil (Local)";
        if (id == 8453)     return "Base Mainnet";
        if (id == 84532)    return "Base Sepolia";
        if (id == 42161)    return "Arbitrum One";
        if (id == 10)       return "Optimism Mainnet";
        return "Unknown Network";
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// DeployVaultMatesAnvil — convenience script for `forge anvil` local dev
// ─────────────────────────────────────────────────────────────────────────────
//
// Deploys VaultMates and seeds three funded accounts (Alice, Bob, Carol)
// with deposits so you can interact immediately via cast or a frontend.
//
// Usage:
//   anvil                                          # terminal 1
//   forge script script/DeployVaultMates.s.sol \  # terminal 2
//     --target-contract DeployVaultMatesAnvil \
//     --rpc-url http://127.0.0.1:8545 \
//     --broadcast \
//     -vvvv
//
// ─────────────────────────────────────────────────────────────────────────────

contract DeployVaultMatesAnvil is Script {

    // Anvil default private keys (accounts 0–3).
    uint256 constant OWNER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant ALICE_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant BOB_KEY   = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 constant CAROL_KEY = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;

    function run() external {

        address owner = vm.addr(OWNER_KEY);
        address alice = vm.addr(ALICE_KEY);
        address bob   = vm.addr(BOB_KEY);
        address carol = vm.addr(CAROL_KEY);

        // ── Deploy as owner ───────────────────────────────────────────────────
        vm.startBroadcast(OWNER_KEY);
        VaultMates vault = new VaultMates(owner);
        vm.stopBroadcast();

        // ── Alice deposits 2 ETH ──────────────────────────────────────────────
        vm.startBroadcast(ALICE_KEY);
        vault.deposit{value: 2 ether}();
        vm.stopBroadcast();

        // ── Bob deposits 3 ETH ────────────────────────────────────────────────
        vm.startBroadcast(BOB_KEY);
        vault.deposit{value: 3 ether}();
        vm.stopBroadcast();

        // ── Carol deposits 5 ETH ─────────────────────────────────────────────
        vm.startBroadcast(CAROL_KEY);
        vault.deposit{value: 5 ether}();
        vm.stopBroadcast();

        // ── Print state ───────────────────────────────────────────────────────
        console2.log("");
        console2.log("=== VaultMates Anvil Seed Deployment ===");
        console2.log("  Contract         :", address(vault));
        console2.log("  Owner            :", owner);
        console2.log("  Total pooled ETH :", vault.totalPooledFunds());
        console2.log("  Depositor count  :", vault.depositorCount());
        console2.log("  Alice balance    :", vault.balanceOf(alice),  "wei");
        console2.log("  Alice share      :", vault.sharePercentage(alice), "bps");
        console2.log("  Bob balance      :", vault.balanceOf(bob),    "wei");
        console2.log("  Bob share        :", vault.sharePercentage(bob),   "bps");
        console2.log("  Carol balance    :", vault.balanceOf(carol),  "wei");
        console2.log("  Carol share      :", vault.sharePercentage(carol), "bps");
        console2.log("========================================");
        console2.log("");
        console2.log("Interact with cast:");
        console2.log("  cast call", address(vault), "\"totalPooledFunds()\"", "--rpc-url http://127.0.0.1:8545");
        // console2.log("  cast send", address(vault), "\"deposit()\"", "--value 1ether", "--private-key <KEY>", "--rpc-url http://127.0.0.1:8545");
        console2.log(string.concat(
            "  cast send ",
            vm.toString(address(vault)),
            " \"deposit()\" --value 1ether --private-key <KEY> --rpc-url http://127.0.0.1:8545"
        ));
    }
}
