// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReactiveStaking} from "./ReactiveStakingAbstract.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract StakingContract is ReactiveStaking, Ownable {
    constructor(
        address initialOwner,
        address stakingTokenAddress,
        uint256 cooldown,
        uint256 minStake,
        uint256 minUnstake
    ) Ownable(initialOwner) ReactiveStaking(stakingTokenAddress, cooldown, minStake, minUnstake) {}

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
