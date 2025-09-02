// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/StakingContract.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract StakingContractTest is Test {
    StakingContract public stakingContract;
    ERC20Mock public stakingToken;

    address public owner;
    address public votingContract;
    address public staker1;
    address public staker2;

    uint256 constant INITIAL_MINT = 1_000_000 ether;
    uint256 constant STAKE_AMOUNT = 100 ether;
    uint256 constant COOLDOWN_PERIOD = 7 days;

    function setUp() public {
        // --- Create Users ---
        owner = makeAddr("owner");
        votingContract = makeAddr("votingContract");
        staker1 = makeAddr("staker1");
        staker2 = makeAddr("staker2");

        // --- Deploy Contracts ---
        stakingToken = new ERC20Mock();
        stakingContract = new StakingContract();
        stakingContract.initialize(owner, address(stakingToken), COOLDOWN_PERIOD, 0.5 ether, 0.5 ether);

        // --- Configure Contracts ---
        vm.prank(owner);
        stakingContract.setVotingContract(votingContract);

        // --- Distribute Tokens ---
        stakingToken.mint(staker1, INITIAL_MINT);
        stakingToken.mint(staker2, INITIAL_MINT);

        // --- Grant Allowances ---
        vm.startPrank(staker1);
        stakingToken.approve(address(stakingContract), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(staker2);
        stakingToken.approve(address(stakingContract), type(uint256).max);
        vm.stopPrank();
    }

    // --- Stake Function Tests ---

    function testGas_Stake_Success() public {
        vm.prank(staker1);
        stakingContract.stake(STAKE_AMOUNT);
    }

    function testGas_Stake_WithActiveProposal() public {
        // Simulate an active proposal
        vm.prank(votingContract);
        stakingContract.createNewProposal(1);

        // Staker 2 stakes, triggering a snapshot
        vm.prank(staker2);
        stakingContract.stake(STAKE_AMOUNT);
    }

    function testRevert_Stake_BelowMinimum() public {
        uint256 minAmount = 0.3 ether;
        vm.prank(staker1);
        vm.expectRevert("Amount below minimum");
        stakingContract.stake(minAmount - 1);
    }

    // --- Unstake & Claim Function Tests ---

    function testGas_Unstake_Success() public {
        // First, stake some tokens
        vm.prank(staker1);
        stakingContract.stake(STAKE_AMOUNT);

        // Then, request to unstake
        vm.prank(staker1);
        stakingContract.unstake(STAKE_AMOUNT / 2);
    }

    function testRevert_Unstake_MaxRequests() public {
        vm.prank(staker1);
        stakingContract.stake(STAKE_AMOUNT);

        // Fill up unstake requests
        uint256 unstakeAmount = 0.5 ether;
        vm.startPrank(staker1);
        for (uint256 i = 0; i < stakingContract.MAX_UNSTAKE_REQUESTS(); i++) {
            stakingContract.unstake(unstakeAmount);
        }
        vm.stopPrank();

        // The next one should fail
        vm.prank(staker1);
        vm.expectRevert("Max unstake requests reached");
        stakingContract.unstake(unstakeAmount);
    }

    function testGas_ClaimUnstake_Success() public {
        vm.startPrank(staker1);
        stakingContract.stake(STAKE_AMOUNT);
        stakingContract.unstake(STAKE_AMOUNT);
        vm.stopPrank();

        // Move time forward past the cooldown period
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        vm.prank(staker1);
        stakingContract.claimUnstake(0);
    }

    function testRevert_ClaimUnstake_CooldownNotPassed() public {
        vm.startPrank(staker1);
        stakingContract.stake(STAKE_AMOUNT);
        stakingContract.unstake(STAKE_AMOUNT);
        vm.stopPrank();

        // Don't move time forward
        vm.prank(staker1);
        vm.expectRevert("Cooldown not passed");
        stakingContract.claimUnstake(0);
    }

    function testGas_ClaimAllReady_Success() public {
        vm.startPrank(staker1);
        stakingContract.stake(STAKE_AMOUNT);

        // Make two requests
        stakingContract.unstake(10e18);
        stakingContract.unstake(20e18);
        vm.stopPrank();
        // Move time forward
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        vm.prank(staker1);
        stakingContract.claimAllReady();
    }

    // --- Owner & Admin Function Tests ---

    function testGas_SetCooldownPeriod() public {
        vm.prank(owner);
        stakingContract.setCooldownPeriod(10 days);
    }
}
