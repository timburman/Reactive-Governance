# Appendix B: Reactive Governance Gas Report

## B.1 Compiler & Configuration Details

This appendix details the comprehensive gas profiling results following the architectural transition of the Reactive Governance protocol from an upgradeable proxy model to a standard, non-upgradeable architecture. 

The tests were compiled and executed under the following environment parameters:

- **Solidity Version**: `0.8.30`
- **Optimizer**: Enabled (`true`)
- **Optimizer Runs**: `200`
- **IR Pipeline**: Enabled (`via_ir = true`)
- **EVM Target**: `cancun`

> [!NOTE]
> **Availability of Raw Output**
> The tables below summarize the aggregated and isolated gas execution costs. Researchers seeking the complete, unparsed Foundry execution logs may refer to the raw report file provided in the repository: `ReactiveGovernanceGasReport.txt`.

---

## B.2 Deployment Costs

| Contract | Deployment Cost (Gas) | Deployment Size (Bytes) |
| :--- | :--- | :--- |
| **StakingContract** | 1,354,084 | 5,980 |
| **VotingContract** | 2,525,171 | 10,856 |
| **Token (ERC20Mock - Standard)** | 513,368 | 2,656 |
| **Token (MyToken - ERC20Votes)** | 1,765,719 | 9,443 |

---

## B.3 Core Function Gas Profiling

The integration test suite was executed against the fully linked system to provide an accurate representation of end-to-end execution costs. This methodology accounts for all cross-contract calls between the `VotingContract` and `StakingContract`.

### Staking Contract

| Function | Min Gas | Avg Gas | Median Gas | Max Gas |
| :--- | :--- | :--- | :--- | :--- |
| `stake()` | 28,989 | 90,588 | 79,998 | 114,208 |
| `unstake()` | 33,071 | 103,030 | 110,018 | 161,340 |
| `claimUnstake()` | 35,703 | 47,069 | 51,875 | 53,631 |
| `claimAllReady()` | 63,070 | 63,070 | 63,070 | 63,070 |

*Note: The max gas on `stake()` and `unstake()` accounts for worst-case scenarios where proposals are active and user snapshots must be taken prior to modifying balances.*

### Voting Contract

| Function | Min Gas | Avg Gas | Median Gas | Max Gas |
| :--- | :--- | :--- | :--- | :--- |
| `createProposal()` | 629,911 | 649,280 | 629,959 | 813,766 |
| `vote()` | 35,569 | 128,190 | 140,298 | 160,273 |
| `resolveProposal()` | 78,839 | 78,839 | 78,839 | 78,839 |
| `executeProposal()` | 36,495 | 36,495 | 36,495 | 36,495 |
| `cancelProposal()` | 64,579 | 64,579 | 64,579 | 64,579 |

*Note: `createProposal()` gas varies heavily depending on the number of choices and the length of the string data provided. The Max Gas (813,766) reflects the robust `testGas_Vote_MultiChoice_MaxOptions` test with 10 string options.*

### B.3.1 Token Operations

#### Standard ERC-20 (ERC20Mock)
| Function | Min Gas | Avg Gas | Median Gas | Max Gas |
| :--- | :--- | :--- | :--- | :--- |
| `transfer()` | 34,184 | 34,184 | 34,184 | 34,184 |
| `approve()` | 46,269 | 46,269 | 46,269 | 46,269 |
| `mint()` | 51,009 | 55,284 | 51,009 | 68,109 |

#### Governance Token (MyToken - ERC20Votes)
| Function | Min Gas | Avg Gas | Median Gas | Max Gas |
| :--- | :--- | :--- | :--- | :--- |
| `transfer()` | 24,707 | 50,782 | 56,274 | 56,274 |
| `transferFrom()` | 24,729 | 34,727 | 34,727 | 44,726 |
| `approve()` | 28,959 | 43,259 | 46,059 | 46,359 |
| `delegate()` | 88,444 | 93,216 | 95,603 | 95,603 |

*Note: The new `testGas_transfer()` was successfully executed on the standard ERC20Mock and its cost is accurately reflected above.*

---

## B.4 Isolated Execution Gas Costs

While standard gas reporting aggregates and averages execution costs across all test variations, precise research necessitates exact best-case versus worst-case execution profiles. For the protocol's core interactions, execution blocks were wrapped with `gasleft()` checkpoints to mathematically strip away setup and assertion overhead, yielding the isolated protocol costs.

| Action | Isolated Gas Cost | Description |
| :--- | :--- | :--- |
| **Normal Stake** | `66,621` | Staking tokens when no proposals are active. |
| **Stake w/ Snapshot** | `84,336` | Staking tokens when a proposal is active (triggers a checkpoint write). |
| **Normal Unstake** | `96,653` | Unstaking tokens when no proposals are active. |
| **Unstake w/ Snapshot** | `131,468` | Unstaking tokens when a proposal is active (triggers a checkpoint write). |
| **Create Binary Proposal** | `617,970` | Pure cost of generating a proposal without options arrays. |
| **Normal Vote** | `101,877` | Voting on a proposal. |
| **Resolve Proposal** | `15,848` | Resolving an active proposal after the voting period ends. |
| **Execute Proposal** | `5,889` | Executing the proposal payload (varies by payload size, this is a blank test execution). |