// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/VotingContract.sol";
import "../src/StakingContract.sol";
import "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract VotingContractTest is Test {
    StakingContract public stakingContract;
    VotingContract public votingContract;
    ERC20Mock public stakingToken;

    address public owner;
    address public proposalManager;
    address public proposer;
    address public voter1;
    address public voter2;
    address public voter3;

    uint256 constant INITIAL_MINT = 1_000_000 ether;
    uint256 constant STAKE_AMOUNT = 100 ether;

    function setUp() public {
        owner = makeAddr("owner");
        proposalManager = makeAddr("proposalManager");
        proposer = makeAddr("proposer");
        voter1 = makeAddr("voter1");
        voter2 = makeAddr("voter2");
        voter3 = makeAddr("voter3");

        stakingToken = new ERC20Mock();

        stakingContract = new StakingContract();
        stakingContract.initialize(address(stakingToken), 7 days, owner);

        votingContract = new VotingContract();
        votingContract.initialize(address(stakingContract), proposalManager, owner);

        vm.prank(owner);
        stakingContract.setVotingContract(address(votingContract));

        vm.startPrank(owner);
        votingContract.addAuthorizedProposer(proposer);
        votingContract.addAdmin(owner);
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
    }

    // --- Proposal Lifecycle Tests ---

    function testGas_CreateProposal_Binary() public {
        vm.prank(proposer);
        votingContract.createProposal(
            "Test Proposal",
            "A binary choice.",
            VotingContract.ProposalCategory.PARAMETER_CHANGE,
            VotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );
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
            VotingContract.ProposalCategory.GOVERNANCE_CHANGE,
            VotingContract.ProposalType.MULTICHOICE,
            choices,
            "",
            address(0),
            0
        );
    }

    function testGas_Vote_Success() public {
        // Create a proposal first
        vm.prank(proposer);
        uint256 proposalId = votingContract.createProposal(
            "Vote on This",
            "...",
            VotingContract.ProposalCategory.PARAMETER_CHANGE,
            VotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        // voter1 casts their vote
        vm.prank(voter1);
        votingContract.vote(proposalId, 0); // Vote "For"
    }

    function testRevert_Vote_Twice() public {
        vm.prank(proposer);
        uint256 proposalId = votingContract.createProposal(
            "Vote on This",
            "...",
            VotingContract.ProposalCategory.PARAMETER_CHANGE,
            VotingContract.ProposalType.BINARY,
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
        // 1. Create Proposal
        vm.prank(proposer);
        uint256 proposalId = votingContract.createProposal(
            "Executable Prop",
            "...",
            VotingContract.ProposalCategory.EMERGENCY_ACTION,
            VotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        // 2. Voters vote to ensure it passes
        vm.prank(voter1);
        votingContract.vote(proposalId, 0); // For
        vm.prank(voter2);
        votingContract.vote(proposalId, 0); // For
        vm.prank(voter3);
        votingContract.vote(proposalId, 0); // For

        // 3. Fast-forward past voting period
        vm.warp(block.timestamp + votingContract.VOTING_PERIOD() + 1);

        // 4. Resolve the proposal
        votingContract.resolveProposal(proposalId);
        (,,, VotingContract.ProposalState state,,,,) = votingContract.getProposalDetails(proposalId);
        require(state == VotingContract.ProposalState.SUCCEEDED, "Proposal did not succeed");

        // 5. Fast-forward past execution delay
        (,,,,,,,, uint256 executionTime,,,,,,,,,) = votingContract.proposals(proposalId);
        vm.warp(executionTime + 1);

        // 6. Execute the proposal
        vm.prank(owner); // Owner is an admin
        votingContract.executeProposal(proposalId);
    }

    function testGas_CancelProposal() public {
        vm.prank(proposer);
        uint256 proposalId = votingContract.createProposal(
            "To Be Cancelled",
            "...",
            VotingContract.ProposalCategory.PARAMETER_CHANGE,
            VotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        vm.prank(owner); // Admin cancels it
        votingContract.cancelProposal(proposalId);
    }

    // --- Snapshot Functionality Tests ---

    function testGas_Snapshot_OnStakeAfterProposal() public {
        uint256 initialStake = stakingContract.getStakedAmount(voter1);

        // 1. Create a proposal. At this point, voter1 has `initialStake` (100e18) tokens.
        vm.prank(proposer);
        uint256 proposalId = votingContract.createProposal(
            "Snapshot Test",
            "...",
            VotingContract.ProposalCategory.PARAMETER_CHANGE,
            VotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        // 2. voter1 stakes *more* tokens. This should trigger a snapshot of their balance *before* this stake.
        vm.prank(voter1);
        stakingContract.stake(50e18);

        // 3. Check voting power. It should be the pre-stake amount, not the new total.
        uint256 votingPower = stakingContract.getVotingPowerForProposal(voter1, proposalId);
        assertEq(votingPower, initialStake, "Voting power should be the snapshotted amount");
        assertNotEq(
            votingPower, stakingContract.getStakedAmount(voter1), "Voting power should not be the current amount"
        );

        // 4. voter1 now votes with their snapshotted power.
        vm.prank(voter1);
        votingContract.vote(proposalId, 0);
    }

    function testGas_Snapshot_OnUnstakeAfterProposal() public {
        uint256 initialStake = stakingContract.getStakedAmount(voter2); // 200e18

        // 1. Create a proposal.
        vm.prank(proposer);
        uint256 proposalId = votingContract.createProposal(
            "Unstake Snapshot",
            "...",
            VotingContract.ProposalCategory.PARAMETER_CHANGE,
            VotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        // 2. voter2 unstakes tokens. This triggers a snapshot of their balance *before* the unstake.
        vm.prank(voter2);
        stakingContract.unstake(50e18);

        // 3. Check voting power. It should be the pre-unstake amount.
        uint256 votingPower = stakingContract.getVotingPowerForProposal(voter2, proposalId);
        assertEq(votingPower, initialStake, "Voting power should be the snapshotted amount");
        assertNotEq(
            votingPower, stakingContract.getStakedAmount(voter2), "Voting power should not be the current amount"
        );

        // 4. voter2 votes.
        vm.prank(voter2);
        votingContract.vote(proposalId, 1); // Vote "Against"
    }

    function testGas_Snapshot_VoteWithLiveBalance() public {
        uint256 initialStake = stakingContract.getStakedAmount(voter3); // 300e18

        // 1. Create a proposal.
        vm.prank(proposer);
        uint256 proposalId = votingContract.createProposal(
            "Live Balance Vote",
            "...",
            VotingContract.ProposalCategory.PARAMETER_CHANGE,
            VotingContract.ProposalType.BINARY,
            new string[](0),
            "",
            address(0),
            0
        );

        // 2. voter3 does NOT interact with the staking contract. They just vote.
        // Their voting power should be their current, live balance because no snapshot was triggered.
        uint256 votingPower = stakingContract.getVotingPowerForProposal(voter3, proposalId);
        assertEq(votingPower, initialStake, "Voting power should be the live balance");

        // 3. voter3 votes.
        vm.prank(voter3);
        votingContract.vote(proposalId, 0);
    }

    function testGas_transfer() public {
        vm.prank(voter1);
        stakingToken.transfer(voter2, 100 ether);
    }
}
