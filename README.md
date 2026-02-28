# VaultMates – AI-Managed Collaborative Vault DAO

VaultMates is a decentralised autonomous organisation (DAO) where members collaboratively manage a shared treasury, create investment proposals, and let Claude AI provide recommendations before voting. Approved proposals are executed automatically on-chain.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      VaultMates DAO                     │
│                                                         │
│  ┌──────────────┐     ┌──────────────────────────────┐  │
│  │ MembershipNFT│────▶│           Vault              │  │
│  │  (Module 1)  │     │         (Module 2)           │  │
│  └──────────────┘     └──────────────┬───────────────┘  │
│                                      │ allocateFunds    │
│  ┌──────────────┐     ┌──────────────▼───────────────┐  │
│  │  Governance  │────▶│           Executor           │  │
│  │  (Module 3)  │     │          (Module 5)          │  │
│  └──────────────┘     └──────────────────────────────┘  │
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │         AIRecommendation (Module 4)             │    │
│  │   Off-chain Claude AI ──▶ On-chain storage      │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

## Modules

| # | Contract | Purpose |
|---|---|---|
| 1 | `MembershipNFT.sol` | Soulbound ERC-721 membership tokens. Mint/revoke via owner. |
| 2 | `Vault.sol` | Pool member deposits; track per-user balances; authorise fund allocation. |
| 3 | `Governance.sol` | Create proposals, cast votes, finalize outcomes. |
| 4 | `AIRecommendation.sol` | Store Claude AI risk/reward scores and recommendation text per proposal. |
| 5 | `Executor.sol` | Automatically execute passed proposals and log every action on-chain. |

### Interfaces
- `IMembership` – shared membership check consumed by Vault & Governance
- `IVault` – fund allocation interface consumed by Executor
- `IGovernance` – proposal status interface consumed by Executor

## Quick Start

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Install dependencies
```bash
forge install
```

### Build
```bash
forge build
```

### Test
```bash
forge test -vvv
```

### Deploy (local Anvil)
```bash
# Start local node
anvil

# Deploy
cp .env.example .env   # fill in values
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url http://localhost:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```

### Deploy (Flow EVM Testnet)
```bash
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

## Key Flows

### 1. Onboard a Member
```
owner → MembershipNFT.mintMembershipNFT(user, metadataURI)
```

### 2. Deposit Funds
```
member → Vault.depositFunds{value: X}()
```

### 3. Create a Proposal
```
member → Governance.createProposal(title, description, options, destination, amount)
```

### 4. Add AI Recommendation (off-chain Claude → on-chain)
```
aiOracle → AIRecommendation.addAIRecommendation(proposalId, text, riskScore, rewardScore)
```

### 5. Vote
```
member → Governance.vote(proposalId, optionIndex)
```

### 6. Finalize (after deadline)
```
anyone → Governance.finalizeProposal(proposalId)
```

### 7. Execute Approved Proposal
```
anyone → Executor.executeProposal(proposalId)
         └──▶ Vault.allocateFunds(destination, amount)
         └──▶ Governance.markExecuted(proposalId)
         └──▶ emits ProposalExecuted event with full log
```

## Environment Variables

See [`.env.example`](.env.example) for all configuration options.

## Roadmap / What's Next

- [ ] **Module 6 – Privacy/Security**: Lit Protocol integration for encrypted voting
- [ ] **Frontend**: React/HTML demo showing vault state, proposals, and AI recommendations
- [ ] **Token-weighted voting**: Replace 1-member-1-vote with stake-proportional weight
- [ ] **Flow SDK walletless onboarding**: Email / passkey account creation
- [ ] **Automated quorum sync**: Event-driven `syncMemberCount` via oracle or Chainlink

## License

MIT
