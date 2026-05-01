# Reactive Governance Gas Optimization Report

## Compiler & Configuration Details

This report details the gas profiling results after transitioning the `Reactive-Governance` project from an upgradeable proxy architecture to a standard, non-upgradeable architecture.

- **Solidity Version**: `0.8.30`
- **Optimizer**: Enabled (`true`)
- **Optimizer Runs**: `200`
- **IR Pipeline**: Enabled (`via_ir = true`)
- **EVM Version**: `cancun`

---

## Deployment Costs

By removing the Upgradeable pattern dependencies (such as `Initializable` and `upgradeTo`), the deployment bytecode size and cost have been significantly reduced.

| Contract | Deployment Cost (Gas) | Deployment Size (Bytes) |
| :--- | :--- | :--- |
| **StakingContract** | 1,354,084 | 5,980 |
| **VotingContract** | 2,525,171 | 10,856 |
| **Token (ERC20Mock)** | 1,765,719 | 9,443 |

---

## Core Function Gas Profiling

The integration tests executed against the fully linked system provide an accurate representation of end-to-end execution costs, accounting for all cross-contract calls between the `VotingContract` and `StakingContract`.

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
