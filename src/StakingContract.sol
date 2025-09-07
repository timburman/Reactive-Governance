// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./ReactiveStakingAbstract.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract StakingContract is Initializable, ReactiveStaking, OwnableUpgradeable {
    // constructor() {
    //     _disableInitializers();
    // }

    function initialize(
        address initialOwner,
        address stakingTokenAddress,
        uint256 cooldown,
        uint256 minStake,
        uint256 minUnstake
    ) public initializer {
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        _initializeReactiveStaking(stakingTokenAddress, cooldown, minStake, minUnstake);
    }

    function setVotingContract(address votingContractAddress) public override onlyOwner {
        super.setVotingContract(votingContractAddress);
    }

    function setCooldownPeriod(uint256 cooldown) public override onlyOwner {
        super.setCooldownPeriod(cooldown);
    }

    function setEmergencyMode(bool enabled) public override onlyOwner {
        super.setEmergencyMode(enabled);
    }
}
