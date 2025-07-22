// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract StakingContract is Initializable, ReentrancyGuardUpgradeable, IERC165 {

    // -- Stake Variables --
    IERC20 public stakingToken;
    address public owner;
    address public pendingOwner;
    uint256 public cooldownPeriod;
    uint256 public minimumStakeAmount;
    uint256 public minimumUnstakeAmount;
    bool public emergencyMode;

    uint256 public constant MAX_UNSTAKE_REQUESTS = 3;
    uint256 public constant MIN_COOLDOWN = 7 days;
    uint256 public constant MAX_COOLDOWN = 30 days;

    mapping(address => uint256) private _balances;
    uint256 public totalStaked;

    // Core proposal state
    bool public isProposalActive;
    uint256 public currentProposalPeriod;
    uint256 public activeProposalCount;
    uint256 public totalProposalCount;
    uint256 public constant MAX_ACTIVE_PROPOSALS = 3;

    // Unstake Requests
    struct UnstakeRequest {
        uint256 amount;
        uint256 requestTime;
    }

    // Proposal Details
    struct ProposalDetails {
        bool active;
        uint32 period;
        uint224 reserved;
    }

    mapping(uint256 => ProposalDetails) public proposalDetails;

    mapping(address => UnstakeRequest[]) public unstakeRequests;

    // Proposal-Specific snapshot storage
    mapping(address => mapping(uint256 => uint256)) public preProposalBalance; // user => proposalId => balance
    mapping(address => mapping(uint256 => bool)) public userSnapshotTaken; // user => proposalId => snapshotted

    // Period management
    mapping(uint256 => uint256) public proposalPeriodStartTime; // period => startTime
    mapping(uint256 => uint256[]) public proposalPeriodProposals; // period => proposalIds[]

    // Access control
    address public votingContract;
    mapping(address => bool) public authorizedAdmins;
    uint256 public adminCount;

    // -- Events --
    event Staked(address indexed user, uint256 amount, uint256 newTotalStaked, uint256 newUserBalance);

    event UnstakeRequested(
        address indexed user, uint256 amount, uint256 requestTime, uint256 requestIndex, uint256 claimableAt
    );

    event UnstakeClaimed(address indexed user, uint256 amount, uint256 requestIndex);

    event BatchUnstakeClaimed(address indexed user, uint256 totalAmount, uint256 requestCount);

    event CooldownPeriodUpdated(uint256 newCooldown);
    event MinimumAmountUpdated(uint256 minStake, uint256 minUnstake);
    event EmergencyModeUpdated(bool enabled);
    event OwnershipTransferred(address indexed previosOwner, address indexed newOwner);

    // Reactive Snapshot events
    event ProposalPeriodStarted(uint256 indexed proposalPeriod);
    event ProposalPeriodEnded(uint256 indexed proposalPeriod);
    event ProposalCreated(uint256 indexed proposalId, uint256 indexed period);
    event ProposalEnded(uint256 indexed proposalId);
    event UserSnapshottedForProposal(address indexed user, uint256 balance, uint256 indexed proposalId);
    event VotingContractUpdated(address indexed newVotingContract);
    event AdminAdded(address indexed newAdmin);
    event AdminRemoved(address indexed removedAdmin);

    // -- Mofifier --
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyVotingContract() {
        require(msg.sender == votingContract, "Only voting contract");
        _;
    }

    modifier onlyAuthorizedAdmin() {
        require(authorizedAdmins[msg.sender] || msg.sender == owner, "Not authorized");
        _;
    }

    // -- Initialization --
    function initialize(address _stakingToken, uint256 _cooldownPeriod, address _owner) public initializer {
        require(_stakingToken != address(0), "Invalid Token");
        require(_owner != address(0), "Invalid owner");
        require(_cooldownPeriod >= MIN_COOLDOWN && _cooldownPeriod <= MAX_COOLDOWN, "Cooldown out of range");

        __ReentrancyGuard_init();

        stakingToken = IERC20(_stakingToken);
        cooldownPeriod = _cooldownPeriod;
        owner = _owner;
        minimumStakeAmount = 1 ether;
        minimumUnstakeAmount = 1 ether;
        emergencyMode = false;

        // votingContract will be set later by owner
        isProposalActive = false;
        currentProposalPeriod = 0;
        activeProposalCount = 0;
        totalProposalCount = 0;
        adminCount = 0;
    }

    // -- Core Staking Logic --
    function stake(uint256 amount) external nonReentrant {
        require(amount >= minimumStakeAmount, "Amount below minimum");
        require(stakingToken.balanceOf(msg.sender) >= amount, "Insufficient token balance");
        require(stakingToken.allowance(msg.sender, address(this)) >= amount, "Insufficient allowance");

        if (isProposalActive) {
            uint256[] memory activeProposals = getActiveProposalIds();

            for (uint256 i = 0; i < activeProposals.length; i++) {
                uint256 proposalId = activeProposals[i];

                if (!userSnapshotTaken[msg.sender][proposalId]) {
                    preProposalBalance[msg.sender][proposalId] = _balances[msg.sender];
                    userSnapshotTaken[msg.sender][proposalId] = true;

                    emit UserSnapshottedForProposal(msg.sender, _balances[msg.sender], proposalId);
                }
            }
        }

        require(stakingToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        _balances[msg.sender] += amount;
        totalStaked += amount;

        emit Staked(msg.sender, amount, totalStaked, _balances[msg.sender]);
    }

    function unstake(uint256 amount) external nonReentrant {
        require(amount >= minimumUnstakeAmount, "Amount below minimum");
        require(_balances[msg.sender] >= amount, "Insufficient staked");
        require(unstakeRequests[msg.sender].length < MAX_UNSTAKE_REQUESTS, "Max unstake requests reached");

        if (isProposalActive) {
            uint256[] memory activeProposals = getActiveProposalIds();

            for (uint256 i = 0; i < activeProposals.length; i++) {
                uint256 proposalId = activeProposals[i];

                if (!userSnapshotTaken[msg.sender][proposalId]) {
                    preProposalBalance[msg.sender][proposalId] = _balances[msg.sender];
                    userSnapshotTaken[msg.sender][proposalId] = true;

                    emit UserSnapshottedForProposal(msg.sender, _balances[msg.sender], proposalId);
                }
            }
        }

        _balances[msg.sender] -= amount;
        totalStaked -= amount;

        unstakeRequests[msg.sender].push(UnstakeRequest({amount: amount, requestTime: block.timestamp}));

        uint256 requestIndex = unstakeRequests[msg.sender].length - 1;
        uint256 claimableAt = block.timestamp + cooldownPeriod;

        emit UnstakeRequested(msg.sender, amount, block.timestamp, requestIndex, claimableAt);
    }

    function claimUnstake(uint256 requestIndex) external nonReentrant {
        require(requestIndex < unstakeRequests[msg.sender].length, "Invalid request");

        UnstakeRequest storage req = unstakeRequests[msg.sender][requestIndex];

        if (!emergencyMode) {
            require(block.timestamp >= req.requestTime + cooldownPeriod, "Cooldown not passed");
        }

        uint256 amount = req.amount;

        _removeRequestByIndex(msg.sender, requestIndex);

        require(stakingToken.transfer(msg.sender, amount), "Transfer failed");

        emit UnstakeClaimed(msg.sender, amount, requestIndex);
    }

    function claimAllReady() external nonReentrant {
        UnstakeRequest[] storage requests = unstakeRequests[msg.sender];
        require(requests.length > 0, "No unstake requests");

        uint256 totalAmount = 0;
        uint256 claimedCount = 0;

        for (int256 i = int256(requests.length) - 1; i >= 0; i--) {
            UnstakeRequest storage req = requests[uint256(i)];

            bool canClaim = emergencyMode || (block.timestamp >= req.requestTime + cooldownPeriod);

            if (canClaim) {
                totalAmount += req.amount;
                claimedCount++;

                _removeRequestByIndex(msg.sender, uint256(i));
            }
        }

        require(totalAmount > 0, "No Claimable requests");
        require(stakingToken.transfer(msg.sender, totalAmount), "Transfer failed");

        emit BatchUnstakeClaimed(msg.sender, totalAmount, claimedCount);
    }

    // -- Internal Helper Functions --
    function _removeRequestByIndex(address user, uint256 index) internal {
        UnstakeRequest[] storage requests = unstakeRequests[user];
        require(index < requests.length, "Invalid index");

        requests[index] = requests[requests.length - 1];
        requests.pop();
    }

    //  -- View Functions --
    function getStakedAmount(address user) external view returns (uint256) {
        return _balances[user];
    }

    function getTotalStaked() external view returns (uint256) {
        return totalStaked;
    }

    function getVotingPowerForProposal(address user, uint256 proposalId) public view returns (uint256) {
        require(proposalId > 0 && proposalId <= totalProposalCount, "Invalid propsal ID");

        if (userSnapshotTaken[user][proposalId]) {
            return preProposalBalance[user][proposalId];
        }

        return _balances[user];
    }

    function getVotingPower(address user) external view returns (uint256) {
        if (!isProposalActive) {
            return _balances[user];
        }

        uint256[] memory activeProposals = getActiveProposalIds();
        if (activeProposals.length == 0) {
            return _balances[user];
        }

        uint256 latestProposal = activeProposals[activeProposals.length - 1];
        return getVotingPowerForProposal(user, latestProposal);
    }

    function getUnstakeRequests(address user)
        external
        view
        returns (uint256[] memory amounts, uint256[] memory requestTimes, uint256[] memory claimableTimes)
    {
        UnstakeRequest[] storage requests = unstakeRequests[user];
        uint256 length = requests.length;

        amounts = new uint256[](length);
        requestTimes = new uint256[](length);
        claimableTimes = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            amounts[i] = requests[i].amount;
            requestTimes[i] = requests[i].requestTime;
            claimableTimes[i] = requests[i].requestTime + cooldownPeriod;
        }
    }

    function getUnstakeRequestsPaginated(address user, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory amounts, uint256[] memory requestTimes, uint256[] memory claimableTimes)
    {
        UnstakeRequest[] memory requests = unstakeRequests[user];
        uint256 totalRequests = requests.length;

        if (offset >= totalRequests) {
            return (new uint256[](0), new uint256[](0), new uint256[](0));
        }

        uint256 end = offset + limit;
        if (end > totalRequests) {
            end = totalRequests;
        }

        uint256 length = end - offset;
        amounts = new uint256[](length);
        requestTimes = new uint256[](length);
        claimableTimes = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            uint256 requestIndex = offset + i;
            amounts[i] = requests[requestIndex].amount;
            requestTimes[i] = requests[requestIndex].requestTime;
            claimableTimes[i] = requests[requestIndex].requestTime + cooldownPeriod;
        }
    }

    function getPendingUnstakeCount(address user) external view returns (uint256) {
        return unstakeRequests[user].length;
    }

    function getTotalPendingUnstake(address user) external view returns (uint256) {
        UnstakeRequest[] memory requests = unstakeRequests[user];
        uint256 total = 0;

        for (uint256 i = 0; i < requests.length; i++) {
            total += requests[i].amount;
        }

        return total;
    }

    function getClaimableRequests(address user)
        external
        view
        returns (uint256[] memory requestIndices, uint256[] memory amounts)
    {
        UnstakeRequest[] storage requests = unstakeRequests[user];
        uint256 claimableCount = 0;

        for (uint256 i = 0; i < requests.length; i++) {
            if (emergencyMode || (block.timestamp >= requests[i].requestTime + cooldownPeriod)) {
                claimableCount++;
            }
        }

        requestIndices = new uint256[](claimableCount);
        amounts = new uint256[](claimableCount);
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < requests.length; i++) {
            if (emergencyMode || (block.timestamp >= requests[i].requestTime + cooldownPeriod)) {
                requestIndices[currentIndex] = i;
                amounts[currentIndex] = requests[i].amount;
                currentIndex++;
            }
        }
    }

    function getNextClaimableTime(address user) external view returns (uint256) {
        if (emergencyMode) return block.timestamp;

        UnstakeRequest[] storage requests = unstakeRequests[user];
        uint256 earliestTime = type(uint256).max;

        for (uint256 i = 0; i < requests.length; i++) {
            uint256 claimableAt = requests[i].requestTime + cooldownPeriod;
            if (claimableAt < earliestTime) {
                earliestTime = claimableAt;
            }
        }

        return earliestTime == type(uint256).max ? 0 : earliestTime;
    }

    function getTotalUnstakeRequests(address user) external view returns (uint256) {
        return unstakeRequests[user].length;
    }

    function getActiveProposalIds() public view returns (uint256[] memory activeProposals) {
        if (!isProposalActive) {
            return new uint256[](0);
        }

        uint256[] memory periodProposals = proposalPeriodProposals[currentProposalPeriod];
        uint256 activeCount = 0;

        for (uint256 i = 0; i < periodProposals.length; i++) {
            if (proposalDetails[periodProposals[i]].active) {
                activeCount++;
            }
        }

        activeProposals = new uint256[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < periodProposals.length; i++) {
            if (proposalDetails[periodProposals[i]].active) {
                activeProposals[index] = periodProposals[i];
                index++;
            }
        }
    }

    // Reactive Snapshot view

    function isUserSnapshottedForProposal(address user, uint256 proposalId) external view returns (bool) {
        return userSnapshotTaken[user][proposalId];
    }

    function getProposalInfo(uint256 proposalId) external view returns (bool active, uint256 period) {
        ProposalDetails memory details = proposalDetails[proposalId];
        return (details.active, uint256(details.period));
    }

    function getProposalPeriodInfo()
        external
        view
        returns (bool active, uint256 period, uint256 activeCount, uint256 startTime, uint256[] memory proposalIds)
    {
        active = isProposalActive;
        period = currentProposalPeriod;
        activeCount = activeProposalCount;
        startTime = proposalPeriodStartTime[currentProposalPeriod];
        proposalIds = proposalPeriodProposals[currentProposalPeriod];
    }

    function hasActiveProposals() external view returns (bool) {
        return isProposalActive;
    }

    // -- Owner Functions --

    function setCooldownPeriod(uint256 newCooldown) external onlyOwner {
        require(newCooldown >= MIN_COOLDOWN && newCooldown <= MAX_COOLDOWN, "Cooldown out of range");
        cooldownPeriod = newCooldown;
        emit CooldownPeriodUpdated(newCooldown);
    }

    function setMinimumAmounts(uint256 minStake, uint256 minUnstake) external onlyOwner {
        require(minStake > 0 && minUnstake > 0, "Amounts must be greater than zero");
        minimumStakeAmount = minStake;
        minimumUnstakeAmount = minUnstake;
        emit MinimumAmountUpdated(minStake, minUnstake);
    }

    function setEmergencyMode(bool enabled) external onlyOwner {
        emergencyMode = enabled;
        emit EmergencyModeUpdated(enabled);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid new owner");
        pendingOwner = newOwner;
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "Not pending owner");
        owner = pendingOwner;
        pendingOwner = address(0);

        emit OwnershipTransferred(owner, pendingOwner);
    }

    function setVotingContract(address _votingContract) external onlyOwner {
        require(_votingContract != address(0), "Invalid voting contract");
        votingContract = _votingContract;
        emit VotingContractUpdated(_votingContract);
    }

    function createNewProposal(uint256 proposalId) external onlyVotingContract nonReentrant returns (uint256 period) {
        require(proposalId > 0, "Invalid proposal ID");
        require(!proposalDetails[proposalId].active, "Proposal already active");
        require(activeProposalCount < MAX_ACTIVE_PROPOSALS, "Too many active proposals");

        totalProposalCount++;

        if (!isProposalActive) {
            currentProposalPeriod++;
            isProposalActive = true;
            proposalPeriodStartTime[currentProposalPeriod] = block.timestamp;
            activeProposalCount = 1;

            emit ProposalPeriodStarted(currentProposalPeriod);
        } else {
            activeProposalCount++;
        }

        proposalDetails[proposalId] =
            ProposalDetails({active: true, period: uint32(currentProposalPeriod), reserved: 0});

        proposalPeriodProposals[currentProposalPeriod].push(proposalId);

        emit ProposalCreated(proposalId, currentProposalPeriod);

        return currentProposalPeriod;
    }

    function endProposal(uint256 proposalId) external onlyVotingContract {
        require(proposalDetails[proposalId].active, "Proposal not active");
        require(activeProposalCount > 0, "No active proposals");

        proposalDetails[proposalId].active = false;
        activeProposalCount--;

        if (activeProposalCount == 0) {
            isProposalActive = false;
            emit ProposalPeriodEnded(currentProposalPeriod);
        }

        emit ProposalEnded(proposalId);
    }

    // Admin functions
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

    // Interface Support
    function supportsInterface(bytes4 interfaceId) public pure override returns(bool) {
        return interfaceId == type(IERC165).interfaceId;
    }

}