// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract ReactiveStaking is ReentrancyGuardUpgradeable {
    // -- State Variables --

    /// @notice The ERC20 token for staking
    IERC20 internal stakingToken;
    /// @notice The address of VotingContract, only authorized contract to manage proposals
    address internal _votingContract;

    // -- Staking Balances --
    mapping(address => uint256) private _balances;
    uint256 private _totalStaked;

    // -- Config --
    uint256 internal _cooldownPeriod;
    uint256 internal _minimumStakeAmount;
    uint256 internal _minimumUnstakeAmount;
    bool internal _emergencyMode;

    // -- Constants --
    uint256 public constant MAX_UNSTAKE_REQUESTS = 3;
    uint256 public constant MIN_COOLDOWN = 7 days;
    uint256 public constant MAX_COOLDOWN = 30 days;

    // -- Proposal State --
    bool internal _isProposalActive;
    uint256 internal _currentProposalPeriod;
    uint256 internal _activeProposalCount;
    uint256 internal _totalProposalCount;
    uint256 public constant MAX_ACTIVE_PROPOSAL = 3;
    uint256[] internal _activeProposalIds;
    mapping(uint256 => uint256) internal _activeProposalIndex;

    // -- Structs --
    struct UnstakeRequest {
        uint256 amount;
        uint256 requestTime;
    }

    struct ProposalDetails {
        bool active;
        uint256 reserved; // For Potential future use
    }

    // -- Mappings --
    mapping(uint256 => ProposalDetails) internal _proposalDetails;
    mapping(address => UnstakeRequest[]) internal _unstakeRequests;
    mapping(address => mapping(uint256 => uint256)) internal _preProposalBalance;
    mapping(address => mapping(uint256 => bool)) internal _userSnapshotTaken;

    // -- Events --
    event Staked(address indexed user, uint256 amount, uint256 newTotalStaked, uint256 newUserBalance);
    event UnstakeRequested(
        address indexed user, uint256 amount, uint256 requestTime, uint256 requestIndex, uint256 claimableAt
    );
    event UnstakeClaimed(address indexed user, uint256 amount, uint256 requestIndex);
    event BatchUnstakeClaimed(address indexed user, uint256 totalAmount, uint256 requestCount);
    event ProposalCreated(uint256 indexed proposalId);
    event ProposalEnded(uint256 indexed proposalId);
    event UserSnapshottedForProposal(address indexed user, uint256 balance, uint256 indexed proposalId);
    event VotingContractUpdated(address indexed newVotingContract);

    // -- Modifiers --
    modifier onlyVotingContract() {
        require(msg.sender == _votingContract, "Only Voting Contract");
        _;
    }

    /**
     * @dev Initializes the contract. To be called from the child contact's initializer
     */
    function _initializeReactiveStaking(
        address stakingTokenAddress,
        uint256 cooldown,
        uint256 minStake,
        uint256 minUnstake
    ) internal {
        require(stakingTokenAddress != address(0), "Invalid Token");
        require(cooldown >= MIN_COOLDOWN && cooldown <= MAX_COOLDOWN, "Cooldown out of range");
        __ReentrancyGuard_init();
        stakingToken = IERC20(stakingTokenAddress);
        _cooldownPeriod = cooldown;
        _minimumStakeAmount = minStake;
        _minimumUnstakeAmount = minUnstake;
    }

    // -- Public Interaction Staking Mechanism Functions --

    function stake(uint256 amount) public virtual nonReentrant {
        _stake(msg.sender, amount);
    }

    function unstake(uint256 amount) public virtual nonReentrant {
        _unstake(msg.sender, amount);
    }

    function claimUnstake(uint256 requestIndex) public virtual nonReentrant {
        _claimUnstake(msg.sender, requestIndex);
    }

    function claimAllReady() public virtual nonReentrant {
        UnstakeRequest[] storage requests = _unstakeRequests[msg.sender];
        require(requests.length > 0, "No unstake requests");

        uint256 totalAmount = 0;
        uint256 claimedCount = 0;

        for (int256 i = int256(requests.length) - 1; i >= 0; i++) {
            UnstakeRequest storage req = requests[uint256(i)];
            bool canClaim = _emergencyMode || (block.timestamp >= req.requestTime + _cooldownPeriod);

            if (canClaim) {
                totalAmount += req.amount;
                claimedCount++;
                _removeRequestByIndex(msg.sender, uint256(i));
            }
        }

        require(totalAmount > 0, "No Claimable requests");
        require(stakingToken.transfer(msg.sender, totalAmount), "Transfer Failed");

        emit BatchUnstakeClaimed(msg.sender, totalAmount, claimedCount);
    }

    // -- Internal Core Logic --
    function _stake(address user, uint256 amount) internal virtual {
        require(amount >= _minimumStakeAmount, "Amount below minimum");
        require(stakingToken.balanceOf(user) >= amount, "Insufficient token balance");
        require(stakingToken.allowance(user, address(this)) >= amount, "Insufficient allowance");

        _beforeTokenTransfer(user, address(this), amount);
        _snapshotIfRequired(user);

        require(stakingToken.transferFrom(user, address(this), amount), "Transfer failed");

        _balances[user] += amount;
        _totalStaked += amount;

        emit Staked(user, amount, _totalStaked, _balances[user]);
    }

    function _unstake(address user, uint256 amount) internal virtual {
        require(amount >= _minimumUnstakeAmount, "Amount below minimum");
        require(_balances[user] >= amount, "Insufficient staked");
        require(_unstakeRequests[user].length < MAX_UNSTAKE_REQUESTS, "Max unstake requests reached");

        _beforeTokenTransfer(user, address(0), amount);
        _snapshotIfRequired(user);

        _balances[user] -= amount;
        _totalStaked -= amount;

        _unstakeRequests[user].push(UnstakeRequest({amount: amount, requestTime: block.timestamp}));

        uint256 requestIndex = _unstakeRequests[user].length - 1;
        uint256 claimableAt = block.timestamp + _cooldownPeriod;

        emit UnstakeRequested(user, amount, block.timestamp, requestIndex, claimableAt);
    }

    function _claimUnstake(address user, uint256 requestIndex) internal virtual {
        require(requestIndex < _unstakeRequests[user].length, "Invalid request");
        UnstakeRequest storage req = _unstakeRequests[user][requestIndex];

        if (!_emergencyMode) {
            require(block.timestamp >= req.requestTime + _cooldownPeriod, "Cooldown not passed");
        }

        uint256 amount = req.amount;
        _removeRequestByIndex(user, requestIndex);
        require(stakingToken.transfer(user, amount), "Transfer failed");

        emit UnstakeClaimed(user, amount, requestIndex);
    }

    /// @notice Hook for child contracts
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}

    // -- Snaphot and Proposal Management --

    /**
     * @dev Internal function to perform the reactive snapshot
     */
    function _snapshotIfRequired(address user) internal {
        if (_isProposalActive) {
            for (uint256 i = 0; i < _activeProposalIds.length; i++) {
                uint256 proposalId = _activeProposalIds[i];
                if (!_userSnapshotTaken[user][proposalId]) {
                    uint256 currentBalance = _balances[user];
                    _preProposalBalance[user][proposalId] = currentBalance;
                    _userSnapshotTaken[user][proposalId] = true;
                    emit UserSnapshottedForProposal(user, currentBalance, proposalId);
                }
            }
        }
    }

    /**
     * @dev Called by the VotingContract to signal the start of a new proposal.
     */
    function createNewProposal(uint256 proposalId) external onlyVotingContract nonReentrant {
        require(proposalId > 0, "Invalid Proposal ID");
        require(!_proposalDetails[proposalId].active, "Proposal already active");
        require(_activeProposalCount < MAX_ACTIVE_PROPOSAL, "Too many active proposals");

        _totalProposalCount++;
        _isProposalActive = true;
        _activeProposalCount++;

        _proposalDetails[proposalId] = ProposalDetails({active: true, reserved: 0});

        _activeProposalIndex[proposalId] = _activeProposalIds.length;
        _activeProposalIds.push(proposalId);

        emit ProposalCreated(proposalId);
    }

    function endProposal(uint256 proposalId) external onlyVotingContract nonReentrant {
        require(_proposalDetails[proposalId].active, "Proposal not active");
        require(_activeProposalCount > 0, "No active Proposals");

        _proposalDetails[proposalId].active = false;
        _activeProposalCount--;

        uint256 indexToRemove = _activeProposalIndex[proposalId];
        uint256 lastProposalId = _activeProposalIds[_activeProposalIds.length - 1];

        _activeProposalIds[indexToRemove] = lastProposalId;
        _activeProposalIndex[lastProposalId] = indexToRemove;

        _activeProposalIds.pop();
        delete _activeProposalIndex[proposalId];

        if (_activeProposalCount == 0) {
            _isProposalActive = false;
        }

        emit ProposalEnded(proposalId);
    }

    // -- View Functions --
    function getVotingPowerForProposal(address user, uint256 proposalId) public view virtual returns (uint256) {
        require(proposalId > 0 && proposalId <= _totalProposalCount, "Invalid proposal ID");
        if (_userSnapshotTaken[user][proposalId]) {
            return _preProposalBalance[user][proposalId];
        }
        return _balances[user];
    }

    function getStakedAmount(address user) public view virtual returns (uint256) {
        return _balances[user];
    }

    function totalStaked() public view returns (uint256) {
        return _totalStaked;
    }

    function getActiveProposalIds() public view virtual returns (uint256[] memory) {
        return _activeProposalIds;
    }

    /**
     * @dev Need to be called by admin.
     * @notice Restriction needs to be added during child contract creation
     */
    function setVotingContract(address votingContractAddress) public virtual {
        _votingContract = votingContractAddress;
        emit VotingContractUpdated(votingContractAddress);
    }

    // -- Internal Helper

    function _removeRequestByIndex(address user, uint256 index) internal {
        UnstakeRequest[] storage requests = _unstakeRequests[user];
        require(index < requests.length, "Invalid Index");
        requests[index] = requests[requests.length - 1];
        requests.pop();
    }
}
