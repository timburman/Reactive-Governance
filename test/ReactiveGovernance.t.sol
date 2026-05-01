// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {VotingContract} from "../src/VotingContract.sol";
import {ReactiveVoting} from "../src/ReactiveVotingAbstract.sol";
import {StakingContract} from "../src/StakingContract.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {console} from "forge-std/console.sol";

contract ReactiveGovernanceTest is Test {
    StakingContract public stakingContract;
    VotingContract public votingContract;
    ERC20Mock public stakingToken;

    address public owner;
    address public proposalManager;
    address public proposer;
    address public voter1;
    address public voter2;
    address public voter3;
    address public staker1; // for raw staking tests

    uint256 constant INITIAL_MINT = 1_000_000 ether;
    uint256 constant STAKE_AMOUNT = 100 ether;

    function setUp() public {
        owner = makeAddr("owner");
        proposalManager = makeAddr("proposalManager");
        proposer = makeAddr("proposer");
        voter1 = makeAddr("voter1");
        voter2 = makeAddr("voter2");
        voter3 = makeAddr("voter3");
        staker1 = makeAddr("staker1");

        stakingToken = new ERC20Mock();

        stakingContract = new StakingContract(owner, address(stakingToken), 7 days, 0.5 ether, 0.5 ether);
        votingContract = new VotingContract(owner, address(stakingContract));

        vm.prank(owner);
        stakingContract.setVotingContract(address(votingContract));

        vm.startPrank(owner);
        votingContract.addAuthorizedProposer(proposer);
        vm.stopPrank();

        address[] memory voters = new address[](3);
        voters[0] = voter1;
        voters[1] = voter2;
        voters[2] = voter3;

        for (uint256 i = 0; i < voters.length; i++) {
            stakingToken.mint(voters[i], INITIAL_MINT);
            vm.prank(voters[i]);
            stakingToken.approve(address(stakingContract), type(uint256).max);
            vm.prank(voters[i]);
            stakingContract.stake(STAKE_AMOUNT * (i + 1));
        }

        // Setup staker1 with tokens but no stake yet
        stakingToken.mint(staker1, INITIAL_MINT);
        vm.prank(staker1);
        stakingToken.approve(address(stakingContract), type(uint256).max);
    }

    // --- Proposal Lifecycle Tests ---

    function testGas_CreateProposal_Binary() public {
        vm.prank(proposer);

        uint256 gasStart = gasleft();
        votingContract.createProposal(
            "Test Proposal",
            "A binary choice.",
            ReactiveVoting.ProposalCategory.PARAMETER_CHANGE,
            ReactiveVoting.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );
        uint256 gasUsed = gasStart - gasleft();
        console.log("Isolated Gas - Create Binary Proposal:", gasUsed);
    }

    function testGas_CreateProposal_MultiChoice() public {
        string[] memory choices = new string[](4);
        choices[0] = "Option A";
        choices[1] = "Option B";
        choices[2] = "Option C";
        choices[3] = "Option D";

        vm.prank(proposer);
        votingContract.createProposal(
            "Multi-Choice",
            "Many options.",
            ReactiveVoting.ProposalCategory.GOVERNANCE_CHANGE,
            ReactiveVoting.ProposalType.MULTICHOICE,
            choices,
            "",
            address(0),
            0
        );
    }

    function testGas_Vote_Success() public {
        vm.prank(proposer);
        uint256 proposalId = votingContract.createProposal(
            "Vote on This",
            "...",
            ReactiveVoting.ProposalCategory.PARAMETER_CHANGE,
            ReactiveVoting.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        vm.prank(voter1);
        uint256 gasStart = gasleft();
        votingContract.vote(proposalId, 0);
        uint256 gasUsed = gasStart - gasleft();
        console.log("Isolated Gas - Normal Vote:", gasUsed);
    }

    function testRevert_Vote_Twice() public {
        vm.prank(proposer);
        uint256 proposalId = votingContract.createProposal(
            "Vote on This",
            "...",
            ReactiveVoting.ProposalCategory.PARAMETER_CHANGE,
            ReactiveVoting.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        vm.prank(voter1);
        votingContract.vote(proposalId, 0);

        vm.prank(voter1);
        vm.expectRevert("Already voted");
        votingContract.vote(proposalId, 1);
    }

    function testGas_Resolve_And_Execute_Proposal() public {
        vm.prank(proposer);
        uint256 proposalId = votingContract.createProposal(
            "Executable Prop",
            "...",
            ReactiveVoting.ProposalCategory.EMERGENCY_ACTION,
            ReactiveVoting.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        vm.prank(voter1);
        votingContract.vote(proposalId, 0);
        vm.prank(voter2);
        votingContract.vote(proposalId, 0);
        vm.prank(voter3);
        votingContract.vote(proposalId, 0);

        vm.warp(block.timestamp + votingContract.VOTING_PERIOD() + 1);

        uint256 resolveStart = gasleft();
        votingContract.resolveProposal(proposalId);
        uint256 resolveUsed = resolveStart - gasleft();
        console.log("Isolated Gas - Resolve Proposal:", resolveUsed);

        ReactiveVoting.ProposalMinimal memory p = votingContract.getProposalDetails(proposalId);
        require(p.state == ReactiveVoting.ProposalState.SUCCEEDED, "Proposal did not succeed");

        vm.warp(p.executionTime + 1);

        vm.prank(owner);
        uint256 execStart = gasleft();
        votingContract.executeProposal(proposalId);
        uint256 execUsed = execStart - gasleft();
        console.log("Isolated Gas - Execute Proposal:", execUsed);
    }

    function testGas_CancelProposal() public {
        vm.prank(proposer);
        uint256 proposalId = votingContract.createProposal(
            "To Be Cancelled",
            "...",
            ReactiveVoting.ProposalCategory.PARAMETER_CHANGE,
            ReactiveVoting.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        vm.prank(owner);
        votingContract.cancelProposal(proposalId);
    }

    // --- Snapshot Functionality Tests ---

    function testGas_Snapshot_OnStakeAfterProposal() public {
        uint256 initialStake = stakingContract.getStakedAmount(voter1);

        vm.prank(proposer);
        uint256 proposalId = votingContract.createProposal(
            "Snapshot Test",
            "...",
            ReactiveVoting.ProposalCategory.PARAMETER_CHANGE,
            ReactiveVoting.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        vm.prank(voter1);
        uint256 stakeStart = gasleft();
        stakingContract.stake(50e18);
        uint256 stakeUsed = stakeStart - gasleft();
        console.log("Isolated Gas - Stake w/ Snapshot (Active Proposal):", stakeUsed);

        uint256 votingPower = stakingContract.getVotingPowerForProposal(voter1, proposalId);
        assertEq(votingPower, initialStake, "Voting power should be the snapshotted amount");

        vm.prank(voter1);
        votingContract.vote(proposalId, 0);
    }

    function testGas_Snapshot_OnUnstakeAfterProposal() public {
        uint256 initialStake = stakingContract.getStakedAmount(voter2);

        vm.prank(proposer);
        uint256 proposalId = votingContract.createProposal(
            "Unstake Snapshot",
            "...",
            ReactiveVoting.ProposalCategory.PARAMETER_CHANGE,
            ReactiveVoting.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        vm.prank(voter2);
        uint256 unstakeStart = gasleft();
        stakingContract.unstake(50e18);
        uint256 unstakeUsed = unstakeStart - gasleft();
        console.log("Isolated Gas - Unstake w/ Snapshot (Active Proposal):", unstakeUsed);

        uint256 votingPower = stakingContract.getVotingPowerForProposal(voter2, proposalId);
        assertEq(votingPower, initialStake, "Voting power should be the snapshotted amount");

        vm.prank(voter2);
        votingContract.vote(proposalId, 1);
    }

    function testGas_Snapshot_VoteWithLiveBalance() public {
        uint256 initialStake = stakingContract.getStakedAmount(voter3);

        vm.prank(proposer);
        uint256 proposalId = votingContract.createProposal(
            "Live Balance Vote",
            "...",
            ReactiveVoting.ProposalCategory.PARAMETER_CHANGE,
            ReactiveVoting.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        uint256 votingPower = stakingContract.getVotingPowerForProposal(voter3, proposalId);
        assertEq(votingPower, initialStake, "Voting power should be the live balance");

        vm.prank(voter3);
        votingContract.vote(proposalId, 0);
    }

    // --- Staking Contract Tests ---

    function testGas_Stake_Success() public {
        vm.prank(staker1);
        uint256 gasStart = gasleft();
        stakingContract.stake(STAKE_AMOUNT);
        uint256 gasUsed = gasStart - gasleft();
        console.log("Isolated Gas - Normal Stake:", gasUsed);
    }

    function testRevert_Stake_BelowMinimum() public {
        uint256 minAmount = 0.5 ether; // updated to 0.5 ether as per deployment
        vm.prank(staker1);
        vm.expectRevert("Amount below minimum");
        stakingContract.stake(minAmount - 1);
    }

    function testGas_Unstake_Success() public {
        vm.prank(voter1);
        uint256 gasStart = gasleft();
        stakingContract.unstake(STAKE_AMOUNT / 2);
        uint256 gasUsed = gasStart - gasleft();
        console.log("Isolated Gas - Normal Unstake:", gasUsed);
    }

    function testRevert_Unstake_MaxRequests() public {
        uint256 unstakeAmount = 0.5 ether;
        vm.startPrank(voter1);
        for (uint256 i = 0; i < stakingContract.MAX_UNSTAKE_REQUESTS(); i++) {
            stakingContract.unstake(unstakeAmount);
        }
        vm.stopPrank();

        vm.prank(voter1);
        vm.expectRevert("Max unstake requests reached");
        stakingContract.unstake(unstakeAmount);
    }

    function testGas_ClaimUnstake_Success() public {
        vm.prank(voter1);
        stakingContract.unstake(STAKE_AMOUNT / 2);

        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(voter1);
        stakingContract.claimUnstake(0);
    }

    function testRevert_ClaimUnstake_CooldownNotPassed() public {
        vm.prank(voter1);
        stakingContract.unstake(STAKE_AMOUNT / 2);

        vm.prank(voter1);
        vm.expectRevert("Cooldown not passed");
        stakingContract.claimUnstake(0);
    }

    function testGas_ClaimAllReady_Success() public {
        vm.startPrank(voter1);
        stakingContract.unstake(10e18);
        stakingContract.unstake(20e18);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(voter1);
        stakingContract.claimAllReady();
    }

    function testGas_SetCooldownPeriod() public {
        vm.prank(owner);
        stakingContract.setCooldownPeriod(10 days);
    }

    // --- Additional Robust Gas Tests ---

    function testGas_Vote_MultiChoice_MaxOptions() public {
        string[] memory choices = new string[](10);
        for (uint256 i = 0; i < 10; i++) {
            choices[i] = string(abi.encodePacked("Option ", vm.toString(i)));
        }

        vm.prank(proposer);
        uint256 proposalId = votingContract.createProposal(
            "Max Options",
            "Testing 10 options",
            ReactiveVoting.ProposalCategory.GOVERNANCE_CHANGE,
            ReactiveVoting.ProposalType.MULTICHOICE,
            choices,
            "",
            address(0),
            0
        );

        vm.prank(voter1);
        votingContract.vote(proposalId, 9); // Vote for last option
    }

    function testGas_Resolve_EmergencyAction() public {
        vm.prank(proposer);
        uint256 proposalId = votingContract.createProposal(
            "Emergency Action",
            "Urgent changes required",
            ReactiveVoting.ProposalCategory.EMERGENCY_ACTION,
            ReactiveVoting.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        // Emergency requires 20% quorum and 75% approval threshold.
        // Total stake = 100 + 200 + 300 = 600. Quorum = 120.
        // Voter2 has 200 voting power, which is > quorum.
        vm.prank(voter2);
        votingContract.vote(proposalId, 0);

        vm.warp(block.timestamp + votingContract.VOTING_PERIOD() + 1);
        votingContract.resolveProposal(proposalId);
    }

    function testGas_EmergencyMode_ClaimUnstake() public {
        // Enable emergency mode
        vm.prank(owner);
        stakingContract.setEmergencyMode(true);

        // Voter requests unstake
        vm.prank(voter1);
        stakingContract.unstake(STAKE_AMOUNT / 2);

        // Claim immediately without waiting for cooldown
        vm.prank(voter1);
        stakingContract.claimUnstake(0);
    }

    function testGas_transfer() public {
        vm.prank(voter1);
        bool s = stakingToken.transfer(voter2, 10 ether);
        assertTrue(s);
    }
}
