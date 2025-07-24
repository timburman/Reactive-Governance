// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./StakingContract.sol";

contract VotingContract is Initializable, ReentrancyGuardUpgradeable, IERC165 {
    // -- State Variables --
    StakingContract public stakingContract;
    address public owner;
    address public pendingOwner;
    address public proposalManager;

    uint256 public proposalCounter;
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant GRACE_PERIOD = 14 days;

    uint256 public constant MAX_ACTIVE_PROPOSALS = 3;
    uint256 public activeProposalCount;

    // -- Authorization --
    mapping(address => bool) public authorizedAdmins;
    uint256 public adminCount;
    mapping(address => bool) public authorizedProposers;

    address public safeAddress;

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
        // Timing
        uint256 creationTime;
        uint256 votingEnd;
        uint256 executionTime;
        uint256 gracePeriodEnd;
        // Snapshot details
        uint256 snapshotPeriod;
        // Voting details
        string[] choices;
        uint256 totalVotes;
        uint256[] voteCounts;
        // State
        ProposalState state;
        // requirements
        uint256 quorumRequired;
        uint256 approvalRequired;
        bytes executionData;
        address target;
        uint256 value;
        mapping(address => bool) hasVoted;
        mapping(address => uint256) userVote;
    }

    // -- Mappings --
    mapping(uint256 => Proposal) public proposals;
    mapping(ProposalCategory => ProposalRequirements) public categoryRequirements;

    // -- Events --
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string title,
        ProposalCategory category,
        ProposalType proposalType,
        uint256 startTime,
        uint256 endTime,
        uint256 period
    );
    event VoteCast(address indexed voter, uint256 indexed proposalId, uint256 choiceIndex, uint256 votingPower);
    event ProposalCancelled(uint256 indexed proposalId, address indexed canceller);
    event ProposalExecuted(uint256 indexed proposalId, address indexed executor);
    event ProposalResolved(uint256 proposalId, ProposalState state, uint256 choiceIndex);
    event ProposerAdded(address indexed proposer);
    event ProposerRemoved(address indexed proposer);
    event ProposerManagerUpdated(address indexed newManager);
    event CategoryRequirementsUpdated(ProposalCategory indexed category);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event SafeExecutionAttempted(address target, uint256 value, bytes data);
    event AdminAdded(address indexed newAdmin);
    event AdminRemoved(address indexed admin);
    event SafeAddressUpdated(address indexed safeAddress);

    // -- Modifiers --
    modifier onlyOwner() {
        require(msg.sender == owner, "VotingContract: Caller is not the owner");
        _;
    }

    modifier onlyAuthorizedProposer() {
        require(
            authorizedProposers[msg.sender] || msg.sender == owner,
            "VotingContract: Caller is not an authorized proposer"
        );
        _;
    }

    modifier onlyAuthorizedAdmin() {
        require(authorizedAdmins[msg.sender] || msg.sender == owner, "Not authorized");
        _;
    }

    modifier proposalExists(uint256 proposalId) {
        require(proposalId > 0 && proposalId <= proposalCounter, "Invalid proposal");
        _;
    }

    modifier activeProposalLimit() {
        require(activeProposalCount < MAX_ACTIVE_PROPOSALS, "Too many active proposals");
        _;
    }

    // -- Initializer --
    function initialize(address _stakingContract, address _proposalManager, address _owner) public initializer {
        require(_stakingContract != address(0), "VotingContract: Staking contract address cannot be zero");
        require(_proposalManager != address(0), "VotingContract: Proposal manager address cannot be zero");
        require(_owner != address(0), "VotingContract: Owner address cannot be zero");

        __ReentrancyGuard_init();

        stakingContract = StakingContract(_stakingContract);
        proposalManager = _proposalManager;
        owner = _owner;
        activeProposalCount = 0;
        adminCount = 0;

        _setDefaultRequirements();
    }

    function _setDefaultRequirements() internal {
        categoryRequirements[ProposalCategory.PARAMETER_CHANGE] =
            ProposalRequirements({quorumPercentage: 10, approvalThreshold: 51, executionDelay: 7 days});
        categoryRequirements[ProposalCategory.TREASURY_ACTION] =
            ProposalRequirements({quorumPercentage: 15, approvalThreshold: 60, executionDelay: 14 days});
        categoryRequirements[ProposalCategory.EMERGENCY_ACTION] =
            ProposalRequirements({quorumPercentage: 20, approvalThreshold: 75, executionDelay: 1 days});
        categoryRequirements[ProposalCategory.GOVERNANCE_CHANGE] =
            ProposalRequirements({quorumPercentage: 25, approvalThreshold: 80, executionDelay: 21 days});
    }

    // -- Proposal Creation --
    function createProposal(
        string memory title,
        string memory description,
        ProposalCategory category,
        ProposalType proposalType,
        string[] memory choices,
        bytes memory executionData,
        address target,
        uint256 value
    ) external onlyAuthorizedProposer activeProposalLimit nonReentrant returns (uint256) {
        require(bytes(title).length > 0, "Title required");
        require(bytes(description).length > 0, "Description required");

        if (proposalType == ProposalType.BINARY) {
            require(choices.length == 0, "Binary proposals don't need choices");
        } else {
            require(choices.length > 2 && choices.length <= 10, "Invalid choice count");
        }

        proposalCounter++;
        uint256 proposalId = proposalCounter;

        uint256 period = stakingContract.createNewProposal(proposalId);
        activeProposalCount++;

        ProposalRequirements memory reqs = categoryRequirements[category];
        uint256 votingEnd = block.timestamp + VOTING_PERIOD;
        uint256 executionDelay = votingEnd + reqs.executionDelay;

        Proposal storage proposal = proposals[proposalId];
        proposal.id = proposalId;
        proposal.title = title;
        proposal.description = description;
        proposal.proposer = msg.sender;
        proposal.category = category;
        proposal.proposalType = proposalType;
        proposal.creationTime = block.timestamp;
        proposal.votingEnd = votingEnd;
        proposal.executionTime = executionDelay;
        proposal.gracePeriodEnd = executionDelay + GRACE_PERIOD;
        proposal.state = ProposalState.ACTIVE;
        proposal.quorumRequired = reqs.quorumPercentage * 100;
        proposal.approvalRequired = reqs.approvalThreshold;
        proposal.totalVotes = 0;
        proposal.executionData = executionData;
        proposal.target = target;
        proposal.value = value;
        proposal.snapshotPeriod = period;

        if (proposalType == ProposalType.BINARY) {
            proposal.choices.push("For");
            proposal.choices.push("Against");
            proposal.choices.push("Abstain");
            proposal.voteCounts = new uint256[](3);
        } else {
            proposal.choices = choices;
            proposal.voteCounts = new uint256[](choices.length);
        }

        emit ProposalCreated(proposalId, msg.sender, title, category, proposalType, block.timestamp, votingEnd, period);
        return proposalId;
    }

    // -- Voting --
    function vote(uint256 proposalId, uint256 choiceIndex) external proposalExists(proposalId) nonReentrant {
        Proposal storage proposal = proposals[proposalId];

        require(proposal.state == ProposalState.ACTIVE, "Proposal not active");
        require(block.timestamp <= proposal.votingEnd, "Voting period ended");
        require(!proposal.hasVoted[msg.sender], "Already voted");
        require(choiceIndex < proposal.choices.length, "Invalid choice");

        uint256 votingPower = stakingContract.getVotingPowerForProposal(msg.sender, proposalId);
        require(votingPower > 0, "No voting power");

        proposal.hasVoted[msg.sender] = true;
        proposal.userVote[msg.sender] = choiceIndex;
        proposal.voteCounts[choiceIndex] += votingPower;
        proposal.totalVotes += votingPower;

        emit VoteCast(msg.sender, proposalId, choiceIndex, votingPower);
    }

    // -- Proposal Resolution & Execution --
    function resolveProposal(uint256 proposalId) external proposalExists(proposalId) {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.state == ProposalState.ACTIVE, "Proposal not active");
        require(block.timestamp > proposal.votingEnd, "Voting still active");

        _resolve(proposalId);
    }

    function _resolve(uint256 proposalId) internal {
        Proposal storage proposal = proposals[proposalId];

        stakingContract.endProposal(proposalId);
        activeProposalCount--;

        uint256 totalStaked = stakingContract.totalStaked();
        uint256 quorumRequired = (totalStaked * proposal.quorumRequired) / 10000;

        if (proposal.totalVotes < quorumRequired) {
            proposal.state = ProposalState.DEFEATED;
            emit ProposalResolved(proposalId, ProposalState.DEFEATED, 0);
            return;
        }

        if (proposal.proposalType == ProposalType.BINARY) {
            uint256 forVotes = proposal.voteCounts[0];
            uint256 againstVotes = proposal.voteCounts[1];
            uint256 totalCastedVotes = forVotes + againstVotes; // Abstain votes are not counted for approval

            if (totalCastedVotes == 0) {
                // Avoid division by zero
                proposal.state = ProposalState.DEFEATED;
                emit ProposalResolved(proposalId, ProposalState.DEFEATED, 1);
                return;
            }

            uint256 approvalPercentage = (forVotes * 100) / totalCastedVotes;

            if (approvalPercentage >= proposal.approvalRequired) {
                proposal.state = ProposalState.SUCCEEDED;
                emit ProposalResolved(proposalId, ProposalState.SUCCEEDED, 0);
            } else {
                proposal.state = ProposalState.DEFEATED;
                emit ProposalResolved(proposalId, ProposalState.DEFEATED, 1);
            }
        } else {
            // For multi-choice, the highest voted option wins.
            uint256 winningChoice = 0;
            uint256 maxVotes = 0;
            for (uint256 i = 0; i < proposal.voteCounts.length; i++) {
                if (proposal.voteCounts[i] > maxVotes) {
                    maxVotes = proposal.voteCounts[i];
                    winningChoice = i;
                }
            }
            proposal.state = ProposalState.SUCCEEDED;
            emit ProposalResolved(proposalId, ProposalState.SUCCEEDED, winningChoice);
        }
    }

    function executeProposal(uint256 proposalId) external proposalExists(proposalId) onlyAuthorizedAdmin {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.state == ProposalState.SUCCEEDED, "Proposal not passed");
        require(block.timestamp >= proposal.executionTime, "Execution delay not met");
        require(block.timestamp <= proposal.gracePeriodEnd, "Grace period expired");

        proposal.state = ProposalState.EXECUTED;

        if (safeAddress != address(0) && proposal.executionData.length > 0) {
            _executeViaSafe(proposal.target, proposal.value, proposal.executionData);
        }

        emit ProposalExecuted(proposalId, msg.sender);
    }

    function _executeViaSafe(address target, uint256 value, bytes memory data) internal {
        require(safeAddress != address(0), "Safe not configured");
        // Placeholder for Safe execution logic
        emit SafeExecutionAttempted(target, value, data);
    }

    // -- Admin Functions --
    function addAdmin(address newAdmin) external onlyOwner {
        require(newAdmin != address(0), "Invalid admin");
        require(!authorizedAdmins[newAdmin], "Already admin");
        authorizedAdmins[newAdmin] = true;
        adminCount++;
        emit AdminAdded(newAdmin);
    }

    function removeAdmin(address admin) external onlyOwner {
        require(authorizedAdmins[admin], "Not an admin");
        require(adminCount > 1, "Cannot remove last admin");
        authorizedAdmins[admin] = false;
        adminCount--;
        emit AdminRemoved(admin);
    }

    function setSafeAddress(address _safeAddress) external onlyOwner {
        safeAddress = _safeAddress;
        emit SafeAddressUpdated(_safeAddress);
    }

    function addAuthorizedProposer(address proposer) external onlyAuthorizedAdmin {
        require(proposer != address(0), "Invalid proposer");
        authorizedProposers[proposer] = true;
        emit ProposerAdded(proposer);
    }

    function removeAuthorizedProposer(address proposer) external onlyAuthorizedAdmin {
        authorizedProposers[proposer] = false;
        emit ProposerRemoved(proposer);
    }

    function cancelProposal(uint256 proposalId) external proposalExists(proposalId) onlyAuthorizedAdmin {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.state == ProposalState.ACTIVE, "Proposal not active");

        proposal.state = ProposalState.CANCELLED;
        stakingContract.endProposal(proposalId);
        activeProposalCount--;

        emit ProposalCancelled(proposalId, msg.sender);
    }

    // -- View functions --
    function getProposalDetails(uint256 proposalId)
        external
        view
        proposalExists(proposalId)
        returns (
            string memory title,
            string memory description,
            address proposer,
            ProposalState state,
            uint256 votingEnd,
            uint256 totalVotes,
            string[] memory choices,
            uint256[] memory voteCounts
        )
    {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.title,
            proposal.description,
            proposal.proposer,
            proposal.state,
            proposal.votingEnd,
            proposal.totalVotes,
            proposal.choices,
            proposal.voteCounts
        );
    }

    function getUserVoteInfo(uint256 proposalId, address user)
        external
        view
        proposalExists(proposalId)
        returns (bool hasVoted, uint256 votedChoice, uint256 votingPower)
    {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.hasVoted[user],
            proposal.userVote[user],
            stakingContract.getVotingPowerForProposal(user, proposalId)
        );
    }

    // -- Interface Support --
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}
