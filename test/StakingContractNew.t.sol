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
}
