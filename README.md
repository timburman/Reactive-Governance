# Reactive Governance
#### Author: Aryan Kaushik
#### Status: Research / Proof-of-Concept

A novel, on-demand snapshotting framework for secure and gas-efficient on-chain DAO governance. This repository contains the reference implementation for the research paper.

## Abstract
On-chain governance for Decentralized Autonomous Organizations (DAOs) is constrained by a critical trilemma, forcing a choice between insecure live-balance reading, unscalable "brute-force" snapshots, or inefficient "continuous checkpointing" systems (`ERC20Votes`) that impose a heavy gas tax on all token transfers.

Reactive Governance is a new design pattern that resolves this trilemma. The model applies balance snapshots on a reactive, just-in-time basis, recording a user's balance only when they attempt to alter their stake during an active proposal period.

This approach eliminates the gas overhead on common token transfers, isolating the cost of security to a marginal, on-demand event. The result is a secure, scalable, and economically efficient on-chain governance system.

## The Problem: The Hidden "Gas Tax"
The current industry standard for secure on-chain voting is Continuous Checkpointing (popularized in OpenZeppelin's `ERC20Votes`). While secure, this model writes to storage on every `transfer()`, adding a significant gas overhead to the most common function of any token.

This acts as a hidden "gas tax" on all token holders, 24/7, making the token less efficient for trading, payments, and general DeFi composability.

## The Solution: On-Demand, Reactive Snapshots
Reactive Governance provides the same robust security guarantees without the constant overhead. It is a "just-in-time" system that only takes a snapshot of a user's balance under one specific condition:

When a user tries to alter their stake (`stake()` or `unstake()`) during a live proposal period.

For all other token transfers, the system does nothing, resulting in zero additional gas overhead.

## Key Features
- Zero Gas Overhead on Transfers: Makes the token as efficient as a standard ERC20 for all non-governance activities.

- Robust Security: Fully protects against flash loan and late-staking governance attacks.

- Scalable Proposal Creation: The cost to create a proposal is a fixed, O(1) operation, regardless of the number of stakers.

- Architectural Simplicity: The logic is contained within a modular, two-contract system.

## Architecture Overview
The system is composed of two core contracts, promoting a strong separation of concerns:

- `StakingContract.sol` (The Ledger): This contract is the engine. It manages all staking/unstaking logic, cooldown periods, and implements the entire selective snapshot algorithm. It is the single source of truth for voting power.

- `VotingContract.sol` (The Governor): This is the high-level orchestrator. It manages the full proposal lifecycle (creation, voting, execution) and delegates all voting power lookups to the StakingContract.

## Getting Started
This project is built with the Foundry framework.

**Prerequisites**
- Foundry

**Installation & Setup**
1.  Clone the repository:
```
git clone [https://github.com/timburman/Reactive-Governance.git](https://github.com/timburman/Reactive-Governance.git)
cd Reactive-Governance
```

2. Install dependencies:
```
forge install
```
**Compile & Test**
1. Compile the contracts:
```
forge build
```
2. Run the test suite:
```
forge test
```


## License
This work is licensed under a Creative Commons Attribution 4.0 International License. You are free to share and adapt this work for any purpose, including commercial, as long as you give appropriate credit.

## Citation
If you use this work in your research, please cite it as follows:
```
A. Kaushik, "Reactive Governance: An On-Demand Snapshotting Framework for Secure DAOS," [Online]. Available: [Link to your Paragraph article or PDF], 2025.
```