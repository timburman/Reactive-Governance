# Reactive Governance

#### Author: Aryan Kaushik (mail.aryankaushik@gmail.com)
#### Status: Research / Proof-of-Concept

A novel, selective on-demand snapshotting framework for secure and gas-efficient on-chain DAO governance. This repository contains the production-ready reference implementation for the research paper.

## Abstract
On-chain governance systems for Decentralized Autonomous Organizations (DAOs) face a critical trilemma between security, scalability, and gas efficiency. Existing approaches either expose governance to manipulation (live balances), impose exponential proposal costs (brute-force snapshots), or burden all token transfers with continuous checkpointing overhead (`ERC20Votes`).

**Reactive Governance** challenges the notion that this trade-off is necessary. It is a novel selective snapshot model that resolves this trilemma by providing robust security while prioritizing ecosystem-wide gas efficiency. The model applies balance snapshots on a reactive, just-in-time basis, recording a user's balance only when they attempt to alter their stake during an active proposal period. 

By completely eliminating the gas overhead on the common `transfer` function, Reactive Governance proves that DAOs no longer have to sacrifice ecosystem-wide efficiency for the security of on-chain voting.

## The Problem: The Governance Trilemma
Existing governance systems rely on three flawed approaches:
1. **Live Balance Reading:** Vulnerable to flash-loan and temporal manipulation attacks.
2. **Brute-Force Snapshots:** Secure, but economically impractical at scale due to O(N) proposal iteration costs.
3. **Continuous Checkpointing:** The industry standard (`ERC20Votes`). While it makes proposal creation efficient (O(1)), it imposes a constant "gas tax" on every single token transfer, making the token highly inefficient for non-governance activities.

## The Solution: Reactive Governance
Reactive Governance utilizes **lazy computation** to provide the same robust security guarantees without the constant overhead. It only takes a snapshot of a user's balance under one specific condition:

> When a user tries to alter their stake (`stake()` or `unstake()`) during a live proposal period.

For all other token transfers, the system does nothing. This isolates the full cost of security to a marginal, on-demand event paid only by the small subset of users who interact with staking during a live vote.

## Key Contributions & Features
- **Zero Gas Overhead on Transfers:** Eliminates the continuous checkpointing gas tax, making the token as efficient as a standard ERC-20 for all DeFi and payment activities.
- **Robust Security Proof:** Formally prevents mid-proposal voting power manipulation, completely defeating Flash Loan attacks and late-staking strategies.
- **Scalable Proposal Creation:** The cost to create a proposal remains a fixed, highly-optimized operation, regardless of network size or staker count.
- **Modular Architecture:** The system implements a strict separation of concerns through an event-based, two-contract ecosystem (`StakingContract` and `VotingContract`).

## Architecture & Gas Efficiency
The system is composed of two core contracts:
- **`StakingContract.sol` (The Ledger):** Handles all staking/unstaking logic, cooldown periods, and implements the selective snapshot algorithm. It is the single source of truth for voting power.
- **`VotingContract.sol` (The Governor):** Orchestrates the full proposal lifecycle (creation, voting, execution) and delegates all voting power lookups to the `StakingContract`.

For a comprehensive empirical analysis of the gas savings, deployment costs, and the isolated metrics for core operations, please see the full [Gas Report (Appendix B)](gas_report.md) and the raw Foundry execution logs in `ReactiveGovernanceGasReport.txt`.

## Getting Started
This project is built with the Foundry framework.

**Prerequisites**
- Foundry

**Installation & Setup**
1.  Clone the repository:
```bash
git clone https://github.com/timburman/Reactive-Governance.git
cd Reactive-Governance
```

2. Install dependencies:
```bash
forge install
```

**Compile & Test**
1. Compile the contracts:
```bash
forge build
```
2. Run the test suite and gas profiler:
```bash
forge test
forge test --gas-report
```

## Citation
If you use this work in your research, please cite it as follows:
```text
A. Kaushik, "Reactive Governance: A Selective Snapshotting Framework for Secure and Gas-Efficient DAO Voting," 2026.
```

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.