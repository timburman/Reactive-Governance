// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./ReactiveStaking.sol";

/**
 * @title ReactiveVoting
 * @notice An abstract base contract for a governance system that uses a ReactiveStaking contract for voting power
 * @dev This contract provides the core logic for proposal creation, voting, resolution, and execution.
 * It is designed to be inherited. Core functions are `internal virtual` to allow for customizations.
 */
abstract contract ReactiveVoting is Initializable, ReentrancyGuardUpgradeable {
    // -- Stake Variables --

    /// @notice The instance of the ReactiveStaking contrract that manages balances and voting power
    ReactiveStaking internal _stakingContract;

    uint256 internal _proposalCounter;
    uint256 internal _activeProposalCount;

    // -- Constants --
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant GRACE_PERIOD = 14 days;
    uint256 public constant MAX_ACTIVE_PROPOSALS = 3;

    // -- Enums --
    enum ProposalCategory {
        PARAMETER_CHANGE,
        TREASURY_ACTION,
        EMERGENCY_ACTION,
        GOVERNANCE_CHANGE
    }

    enum ProposalType {
        BINARY,
        MULTICHOICE
    }

    enum ProposalState {
        PENDING,
        ACTIVE,
        SUCCEEDED,
        DEFEATED,
        QUEUED,
        EXECUTED,
        CANCELLED,
        EXPIRED
    }

    // -- Structs --
    struct ProposalRequirements {
        uint256 quorumPercentage;
        uint256 approvalThreshold;
        uint256 executionDelay;
    }

    struct Proposal {
        uint256 id;
        string title;
        string description;
        ProposalCategory category;
        ProposalType proposalType;
        address proposer;
        uint256 creationTime;
        uint256 votingEnd;
        uint256 executionTime;
        uint256 gracePeriodEnd;
        string[] choices;
        uint256 totalVotes;
        uint256[] voteCounts;
        ProposalState state;
        uint256 quorumRequired; // In basis pointis, e.g., 1000 for 10%
        uint256 approvalRequired; // In percentage, e.g., 51 for 51%
        bytes executionData;
        address target;
        uint256 value;
        uint256 totalStakedSnapshot;
        uint256 winningChoiceIndex;
        mapping(address => bool) hasVoted;
        mapping(address => uint256) userVote;
        mapping(address => uint256) userVotingPower;
    }

    // -- Mappings --
    mapping(uint256 => Proposal) internal _proposals;
    mapping(ProposalCategory => ProposalRequirements) internal _categoryRequirements;

    // -- Events --
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string title,
        ProposalCategory category,
        ProposalType proposalType
    );
    event VoteCast(address indexed voter, uint256 indexed proposalId, uint256 choiceIndex, uint256 votingPower);
    event ProposalCancelled(uint256 indexed proposalId);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalResolved(uint256 proposalId, ProposalState state, uint256 winningChoiceIndex);

    /**
     * @dev Initializes the contract. To be called from the child contract's initializer
     * @param stakingContractAddress The address of the deployed ReactiveStaking contract
     */
    function _initializeReactiveVoting(address stakingContractAddress) internal {
        require(stakingContractAddress != address(0), "Invalid Staking Contract");
        __ReentrancyGuard_init();
        _stakingContract = ReactiveStaking(stakingContractAddress);
        _setDefaultRequirements();
    }

    /**
     * @dev Sets default requirements for proposal categories. Can be overridden.
     */
    function _setDefaultRequirements() internal virtual {
        _categoryRequirements[ProposalCategory.PARAMETER_CHANGE] =
            ProposalRequirements({quorumPercentage: 10, approvalThreshold: 51, executionDelay: 7 days});
        _categoryRequirements[ProposalCategory.TREASURY_ACTION] =
            ProposalRequirements({quorumPercentage: 15, approvalThreshold: 60, executionDelay: 14 days});
        _categoryRequirements[ProposalCategory.EMERGENCY_ACTION] =
            ProposalRequirements({quorumPercentage: 20, approvalThreshold: 75, executionDelay: 1 days});
        _categoryRequirements[ProposalCategory.GOVERNANCE_CHANGE] =
            ProposalRequirements({quorumPercentage: 25, approvalThreshold: 80, executionDelay: 21 days});
    }

    // -- Public Functions --
    function createProposal(
        string memory title,
        string memory description,
        ProposalCategory category,
        ProposalType proposalType,
        string[] memory choices,
        bytes memory exectionData,
        address target,
        uint256 value
    ) public virtual nonReentrant returns (uint256) {
        // Access control (e.g., onlyAuthorizedProposer) should be added in the implementation contract.
        require(_activeProposalCount < MAX_ACTIVE_PROPOSALS, "Too many active proposals");
        return _createProposal(title, description, category, proposalType, choices, exectionData, target, value);
    }

    function vote(uint256 proposalId, uint256 choiceIndex) public virtual nonReentrant {
        _vote(msg.sender, proposalId, choiceIndex);
    }

    function resolveProposal(uint256 proposalId) public virtual {
        Proposal storage p = _proposals[proposalId];
        require(p.state == ProposalState.ACTIVE, "Proposal not active");
        require(block.timestamp > p.votingEnd, "Voting still active");
        _resolve(proposalId);
    }

    function executeProposal(uint256 proposalId) public virtual nonReentrant {
        // Access control (e.g., onlyAdmin) should be added in the implementation contract.
        _execute(proposalId);
    }

    function cancelProposal(uint256 proposalId) public virtual {
        // Access control (e.g., onlyAdmin) should be added in the implementation contract.
        _cancel(proposalId);
    }

    // -- Internal Core Functions --

    function _createProposal(
        string memory title,
        string memory description,
        ProposalCategory category,
        ProposalType proposalType,
        string[] memory choices,
        bytes memory executionData,
        address target,
        uint256 value
    ) internal virtual returns (uint256) {
        require(bytes(title).length > 0, "Title required");
        require(bytes(description).length > 0, "Description required");

        if (proposalType == ProposalType.BINARY) {
            require(choices.length == 0, "Binary proposals don't need choices");
        } else {
            require(choices.length >= 2 && choices.length <= 10, "Invalid choice count");
        }

        _proposalCounter++;
        uint256 proposalId = _proposalCounter;

        _stakingContract.createNewProposal(proposalId);
        _activeProposalCount++;

        ProposalRequirements memory reqs = _categoryRequirements[category];
        uint256 votingEnd = block.timestamp + VOTING_PERIOD;
        uint256 executionDelay = votingEnd + reqs.executionDelay;

        Proposal storage p = _proposals[proposalId];
        p.id = proposalId;
        p.title = title;
        p.description = description;
        p.proposer = msg.sender;
        p.category = category;
        p.proposalType = proposalType;
        p.creationTime = block.timestamp;
        p.votingEnd = votingEnd;
        p.executionTime = executionDelay;
        p.gracePeriodEnd = executionDelay + GRACE_PERIOD;
        p.state = ProposalState.ACTIVE;
        p.quorumRequired = reqs.quorumPercentage * 100; // Convert to basis points
        p.approvalRequired = reqs.approvalThreshold;
        p.executionData = executionData;
        p.target = target;
        p.value = value;
        p.totalStakedSnapshot = _stakingContract.totalStaked();

        if (proposalType == ProposalType.BINARY) {
            p.choices = ["For", "Against", "Abstrain"];
            p.voteCounts = new uint256[](choices.length);
        } else {
            p.choices = choices;
            p.voteCounts = new uint256[](choices.length);
        }

        emit ProposalCreated(proposalId, msg.sender, title, category, proposalType);

        return proposalId;
    }

    function _vote(address voter, uint256 proposalId, uint256 choiceIndex) internal virtual {
        Proposal storage p = _proposals[proposalId];

        require(p.id != 0, "Invalid proposal");
        require(p.state == ProposalState.ACTIVE, "Proposal not active");
        require(block.timestamp <= p.votingEnd, "Voting period ended");
        require(!p.hasVoted[voter], "Already voted");
        require(choiceIndex < p.choices.length, "Invalid choice");

        uint256 votingPower = _stakingContract.getVotingPowerForProposal(voter, proposalId);
        require(votingPower > 0, "No voting power");

        p.hasVoted[voter] = true;
        p.userVote[voter] = choiceIndex;

        p.userVotingPower[voter] = votingPower;
        p.voteCounts[choiceIndex] += votingPower;
        p.totalVotes += votingPower;

        emit VoteCast(voter, proposalId, choiceIndex, votingPower);
    }

    function _resolve(uint256 proposalId) internal virtual {
        Proposal storage p = _proposals[proposalId];

        _stakingContract.endProposal(proposalId);
        _activeProposalCount--;

        uint256 quorumValue = (p.totalStakedSnapshot * p.quorumRequired) / 10000;

        if (p.totalVotes < quorumValue) {
            p.state = ProposalState.DEFEATED;
            p.winningChoiceIndex = p.proposalType == ProposalType.BINARY ? 1 : 0;
            emit ProposalResolved(proposalId, ProposalState.DEFEATED, p.winningChoiceIndex);
            return;
        }

        uint256 winningChoice = 0;
        if (p.proposalType == ProposalType.BINARY) {
            uint256 forVotes = p.voteCounts[0];
            uint256 againstVotes = p.voteCounts[1];
            uint256 totalCastedVotes = forVotes + againstVotes;

            if (totalCastedVotes == 0) {
                p.state = ProposalState.DEFEATED;
                winningChoice = 1;
            } else {
                uint256 approvalPercentage = (forVotes * 100) / totalCastedVotes;
                if (approvalPercentage >= p.approvalRequired) {
                    p.state = ProposalState.SUCCEEDED;
                    winningChoice = 0;
                } else {
                    p.state = ProposalState.DEFEATED;
                    winningChoice = 1;
                }
            }
        } else {
            // Multichoice
            p.state = ProposalState.SUCCEEDED;
            uint256 maxVotes = 0;
            for (uint256 i = 0; i < p.voteCounts.length; i++) {
                if (p.voteCounts[i] > maxVotes) {
                    maxVotes = p.voteCounts[i];
                    winningChoice = i;
                }
            }
        }

        p.winningChoiceIndex = winningChoice;
        emit ProposalResolved(proposalId, p.state, winningChoice);
    }

    function _execute(uint256 proposalId) internal virtual {
        Proposal storage p = _proposals[proposalId];

        require(p.state == ProposalState.SUCCEEDED, "Proposal not passses");
        require(block.timestamp >= p.executionTime, "Execution delay not met");
        require(block.timestamp <= p.gracePeriodEnd, "Grace period expired");

        p.state = ProposalState.EXECUTED;

        if (p.target != address(0)) {
            (bool success,) = p.target.call{value: p.value}(p.executionData);
            require(success, "Execution Failed");
        }

        emit ProposalExecuted(proposalId);
    }

    function _cancel(uint256 proposalId) internal virtual {
        Proposal storage p = _proposals[proposalId];

        require(p.state == ProposalState.ACTIVE, "Proposal not active");

        p.state = ProposalState.CANCELLED;
        _stakingContract.endProposal(proposalId);
        _activeProposalCount--;

        emit ProposalCancelled(proposalId);
    }

    // -- View Functions --

    function getProposalDetails(uint256 proposalId)
        public
        view
        virtual
        returns (
            uint256 id,
            string memory title,
            string memory description,
            address proposer,
            ProposalState state,
            uint256 votingEnd,
            uint256 totalVotes,
            string[] memory choices,
            uint256[] memory voteCounts,
            uint256 winningChoiceIndex
        )
    {
        Proposal storage p = _proposals[proposalId];
        return (
            p.id,
            p.title,
            p.description,
            p.proposer,
            p.state,
            p.votingEnd,
            p.totalVotes,
            p.choices,
            p.voteCounts,
            p.winningChoiceIndex
        );
    }

    function getUserVoteInfo(uint256 proposalId, address user)
        public
        view
        returns (bool hasVoted, uint256 choice, uint256 votingPower)
    {
        Proposal storage p = _proposals[proposalId];
        require(p.id != 0, "Invalid Proposal");
        hasVoted = _proposals[proposalId].hasVoted[user];
        choice = _proposals[proposalId].userVote[user];

        if (hasVoted) {
            votingPower = p.userVotingPower[user];
        } else {
            votingPower = _stakingContract.getVotingPowerForProposal(user, proposalId);
        }
    }
}
