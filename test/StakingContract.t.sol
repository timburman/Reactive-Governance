// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/StakingContract.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract StakingContractTest is Test {
    StakingContract public staking;
    StakingContract public stakingImpl;
    ERC20Mock public token;
    ProxyAdmin public proxyAdmin;

    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    uint256 public constant INITIAL_BALANCE = 100000 ether;
    uint256 public constant COOLDOWN_PERIOD = 7 days;

    event Staked(address indexed user, uint256 amount, uint256 newTotalStaked, uint256 newUserBalance);
    event UnstakeRequested(
        address indexed user, uint256 amount, uint256 requestTime, uint256 requestIndex, uint256 claimableAt
    );
    event UnstakeClaimed(address indexed user, uint256 amount, uint256 originalRequestIndex);
    event BatchUnstakeClaimed(address indexed user, uint256 totalAmount, uint256 requestCount);
    event CooldownPeriodUpdated(uint256 newCooldown);

    function setUp() public {
        token = new ERC20Mock();
        proxyAdmin = new ProxyAdmin(owner);
        stakingImpl = new StakingContract();

        bytes memory initData =
            abi.encodeWithSelector(StakingContract.initialize.selector, address(token), COOLDOWN_PERIOD, owner);

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(stakingImpl), address(proxyAdmin), initData);
        staking = StakingContract(address(proxy));

        vm.startPrank(owner);
        token.mint(owner, 100_000 ether);
        token.mint(user1, 10000 ether);
        token.mint(user2, 20000 ether);
        token.mint(user3, 30000 ether);
        vm.stopPrank();

        vm.prank(user1);
        token.approve(address(staking), type(uint256).max);
        vm.prank(user2);
        token.approve(address(staking), type(uint256).max);
        vm.prank(user3);
        token.approve(address(staking), type(uint256).max);
    }

    function test_initialize_success() public view {
        assertEq(address(staking.stakingToken()), address(token));
        assertEq(staking.owner(), owner);
        assertEq(staking.cooldownPeriod(), COOLDOWN_PERIOD);
        assertEq(staking.minimumStakeAmount(), 1 ether);
        assertEq(staking.minimumUnstakeAmount(), 1 ether);
        assertFalse(staking.emergencyMode());
    }

    function testInitializeInvalidToken() public {
        StakingContract newImpl = new StakingContract();

        vm.expectRevert("Invalid Token");
        newImpl.initialize(address(0), COOLDOWN_PERIOD, owner);
    }

    function testInitializeInvalidOwner() public {
        StakingContract newImpl = new StakingContract();

        vm.expectRevert("Invalid owner");
        newImpl.initialize(address(token), COOLDOWN_PERIOD, address(0));
    }

    function testInitializeInvallidCooldown() public {
        StakingContract newImpl = new StakingContract();

        vm.expectRevert("Cooldown out of range");
        newImpl.initialize(address(token), 6 days, owner);

        vm.expectRevert("Cooldown out of range");
        newImpl.initialize(address(token), 31 days, owner);
    }

    // -- Staking Tests --
    function testStakeSuccess() public {
        uint256 stakeAmount = 1000 ether;

        vm.expectEmit(true, true, true, true);
        emit Staked(user1, stakeAmount, stakeAmount, stakeAmount);

        vm.prank(user1);
        staking.stake(stakeAmount);

        assertEq(staking.getStakedAmount(user1), stakeAmount);
        assertEq(staking.getTotalStaked(), stakeAmount);
        assertEq(staking.getVotingPower(user1), stakeAmount);
        assertEq(token.balanceOf(user1), 9000 ether);
    }

    function testStakeMultipleUsers() public {
        uint256 stakeAmount1 = 1000 ether;
        uint256 stakeAmount2 = 2000 ether;

        vm.prank(user1);
        staking.stake(stakeAmount1);

        vm.prank(user2);
        staking.stake(stakeAmount2);

        assertEq(staking.getStakedAmount(user1), stakeAmount1);
        assertEq(staking.getStakedAmount(user2), stakeAmount2);
        assertEq(staking.getTotalStaked(), stakeAmount1 + stakeAmount2);
    }

    function testStakeBelowMinimum() public {
        vm.prank(user1);

        vm.expectRevert("Amount below minimum");
        staking.stake(0.5 ether);
    }

    function testStakeInsufficientBalance() public {
        uint256 stakeAmount = 100000 ether; // More than user1's balance

        vm.prank(user1);
        vm.expectRevert("Insufficient token balance");
        staking.stake(stakeAmount);
    }

    function testStakeInsufficientAllowance() public {
        address newUser = address(0x707);

        vm.prank(owner);
        token.transfer(newUser, 1000 ether);

        vm.prank(newUser);
        vm.expectRevert("Insufficient allowance");
        staking.stake(1000 ether);
    }

    // -- Unstake Tests --

    function testUnstakeSuccess() public {
        uint256 stakeAmount = 1000 ether;
        uint256 unstakeAmount = 500 ether;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.expectEmit(true, true, true, true);
        emit UnstakeRequested(user1, unstakeAmount, block.timestamp, 0, block.timestamp + COOLDOWN_PERIOD);

        vm.prank(user1);
        staking.unstake(unstakeAmount);

        assertEq(staking.getStakedAmount(user1), stakeAmount - unstakeAmount);
        assertEq(staking.getTotalStaked(), stakeAmount - unstakeAmount);
        assertEq(staking.getPendingUnstakeCount(user1), 1);
        assertEq(staking.getTotalPendingUnstake(user1), unstakeAmount);
    }

    function testUnstakeMultipleRequests() public {
        uint256 stakeAmount = 3000 ether;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.prank(user1);
        staking.unstake(500 ether);

        vm.prank(user1);
        staking.unstake(700 ether);

        vm.prank(user1);
        staking.unstake(800 ether);

        assertEq(staking.getPendingUnstakeCount(user1), 3);
        assertEq(staking.getTotalPendingUnstake(user1), 2000 ether);
        assertEq(staking.getStakedAmount(user1), 1000 ether);
    }

    function testUnstakeMaxRequestsReached() public {
        uint256 stakeAmount = 3000 ether;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.prank(user1);
        staking.unstake(500 ether);
        vm.prank(user1);
        staking.unstake(500 ether);
        vm.prank(user1);
        staking.unstake(500 ether);

        vm.prank(user1);
        vm.expectRevert("Max unstake requests reached");
        staking.unstake(500 ether);
    }

    function testUnstakeInsufficientStaked() public {
        vm.prank(user1);
        vm.expectRevert("Insufficient staked");
        staking.unstake(100 ether);
    }

    function unstakeBelowMinimum() public {
        vm.prank(user1);
        staking.stake(2 ether);

        vm.prank(user1);
        vm.expectRevert("Amount below minimum");
        staking.unstake(0.5 ether);
    }

    // -- Claim Tests --

    function testClaimUnstakeBeforeCooldownFails() public {
        uint256 stakeAmount = 1000 ether;
        uint256 unstakeAmount = 500 ether;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.prank(user1);
        staking.unstake(unstakeAmount);

        vm.prank(user1);
        vm.expectRevert("Cooldown not passed");
        staking.claimUnstake(0);
    }

    function testClaimUnstakeAfterCooldownSuccess() public {
        uint256 stakeAmount = 1000 ether;
        uint256 unstakeAmount = 500 ether;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.prank(user1);
        staking.unstake(unstakeAmount);

        skip(COOLDOWN_PERIOD + 1 seconds);

        uint256 balanceBefore = token.balanceOf(user1);

        vm.expectEmit(true, true, true, true);
        emit UnstakeClaimed(user1, unstakeAmount, 0);

        vm.prank(user1);
        staking.claimUnstake(0);

        assertEq(token.balanceOf(user1), balanceBefore + unstakeAmount);
        assertEq(staking.getPendingUnstakeCount(user1), 0);
        assertEq(staking.getTotalPendingUnstake(user1), 0);
    }

    function testClaimUnstakeInvalidRequest() public {
        vm.prank(user1);
        vm.expectRevert("Invalid request");
        staking.claimUnstake(1);
    }

    function testclaimAllReadySuccess() public {
        uint256 stakeAmount = 3000 ether;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.prank(user1);
        staking.unstake(1000 ether);

        vm.prank(user1);
        staking.unstake(1000 ether);

        vm.prank(user1);
        staking.unstake(1000 ether);

        skip(COOLDOWN_PERIOD + 1 seconds);

        uint256 balanceBefore = token.balanceOf(user1);

        vm.expectEmit(true, true, true, true);
        emit BatchUnstakeClaimed(user1, 3000 ether, 3);

        vm.prank(user1);
        staking.claimAllReady();

        assertEq(token.balanceOf(user1), balanceBefore + 3000 ether);
        assertEq(staking.getPendingUnstakeCount(user1), 0);
    }

    function testClaimAllReadyPartial() public {
        uint256 stakeAmount = 3000 ether;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.prank(user1);
        staking.unstake(1000 ether);

        skip(4 days);

        vm.prank(user1);
        staking.unstake(500 ether);

        skip(4 days);

        uint256 balanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        staking.claimAllReady();

        assertEq(token.balanceOf(user1), balanceBefore + 1000 ether);
        assertEq(staking.getPendingUnstakeCount(user1), 1);
        assertEq(staking.getTotalPendingUnstake(user1), 500 ether);
    }

    function testClaimAllReadyNoRequests() public {
        vm.prank(user1);
        vm.expectRevert("No unstake requests");
        staking.claimAllReady();
    }

    // -- Emergency Mode Tests --
    function testEmergencyModeInstantClaim() public {
        uint256 stakeAmount = 1000 ether;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.prank(owner);
        staking.setEmergencyMode(true);

        vm.prank(user1);
        staking.unstake(500 ether);

        vm.prank(user1);
        staking.claimUnstake(0);

        assertEq(staking.getPendingUnstakeCount(user1), 0);
    }

    // -- View Function Tests --

    function testGetUnstakeRequests() public {
        uint256 stakeAmount = 1000 ether;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.prank(user1);
        staking.unstake(500 ether);
        vm.prank(user1);
        staking.unstake(300 ether);

        (uint256[] memory amounts, uint256[] memory requestTimes, uint256[] memory claimableTimes) =
            staking.getUnstakeRequests(user1);

        assertEq(amounts.length, 2);
        assertEq(amounts[0], 500 ether);
        assertEq(amounts[1], 300 ether);
        assertEq(claimableTimes[0], requestTimes[0] + COOLDOWN_PERIOD);
    }

    function test_getUnstakeRequestsPaginated() public {
        uint256 stakeAmount = 3000 * 10 ** 18;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.prank(user1);
        staking.unstake(500 * 10 ** 18);
        vm.prank(user1);
        staking.unstake(700 * 10 ** 18);
        vm.prank(user1);
        staking.unstake(800 * 10 ** 18);

        (uint256[] memory amounts1,,) = staking.getUnstakeRequestsPaginated(user1, 0, 2);
        assertEq(amounts1.length, 2);
        assertEq(amounts1[0], 500 * 10 ** 18);
        assertEq(amounts1[1], 700 * 10 ** 18);

        (uint256[] memory amounts2,,) = staking.getUnstakeRequestsPaginated(user1, 2, 2);
        assertEq(amounts2.length, 1);
        assertEq(amounts2[0], 800 * 10 ** 18);

        (uint256[] memory amounts3,,) = staking.getUnstakeRequestsPaginated(user1, 5, 2);
        assertEq(amounts3.length, 0);
    }

    function test_getClaimableRequests() public {
        uint256 stakeAmount = 2000 * 10 ** 18;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.prank(user1);
        staking.unstake(500 * 10 ** 18);

        skip(4 days);
        vm.prank(user1);
        staking.unstake(700 * 10 ** 18);

        // Fast forward to make first claimable
        skip(4 days);

        (uint256[] memory indices, uint256[] memory amounts) = staking.getClaimableRequests(user1);

        assertEq(indices.length, 1);
        assertEq(indices[0], 0);
        assertEq(amounts[0], 500 * 10 ** 18);
    }

    // -- Admin Functions Tests --

    function testSetCooldownPeriodSuccess() public {
        uint256 cooldown = 10 days;

        vm.expectEmit(true, true, true, true);
        emit CooldownPeriodUpdated(cooldown);

        vm.prank(owner);
        staking.setCooldownPeriod(cooldown);

        assertEq(staking.cooldownPeriod(), cooldown);
    }

    function testSetCooldownOutNotOwner() public {
        vm.prank(user1);
        vm.expectRevert("Not owner");
        staking.setCooldownPeriod(10 days);
    }

    function testSetCooldownOutOfRange() public {
        vm.prank(owner);
        vm.expectRevert("Cooldown out of range");
        staking.setCooldownPeriod(6 days);

        vm.prank(owner);
        vm.expectRevert("Cooldown out of range");
        staking.setCooldownPeriod(31 days);
    }

    function testSetMinimumAmounts() public {
        vm.prank(owner);
        staking.setMinimumAmounts(100 ether, 50 ether);

        assertEq(staking.minimumStakeAmount(), 100 ether);
        assertEq(staking.minimumUnstakeAmount(), 50 ether);
    }

    function testOwnershipTransfer() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        staking.transferOwnership(newOwner);

        assertEq(staking.pendingOwner(), newOwner);
        assertEq(staking.owner(), owner);

        vm.prank(newOwner);
        staking.acceptOwnership();

        assertEq(staking.owner(), newOwner);
        assertEq(staking.pendingOwner(), address(0));
    }

    // -- Security Tests --

    function testReentrancyProtection() public pure {
        // place holder
        assertTrue(true);
    }

    function testArrayShiftingCorrectness() public {
        uint256 stakeAmount = 3000 ether;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.prank(user1);
        staking.unstake(500 ether);

        vm.prank(user1);
        staking.unstake(700 ether);

        vm.prank(user1);
        staking.unstake(1000 ether);

        skip(COOLDOWN_PERIOD + 1 seconds);

        vm.prank(user1);
        staking.claimUnstake(1);

        assertEq(staking.getPendingUnstakeCount(user1), 2);

        (uint256[] memory amounts,,) = staking.getUnstakeRequests(user1);

        assertEq(amounts[0], 500 ether);
        assertEq(amounts[1], 1000 ether);
    }

    // -- Gas Optimization Tests --

    // -- Interface Tests --
    function testSupportsInterface() public view {
        assertTrue(staking.supportsInterface(type(IERC165).interfaceId));
    }
}
