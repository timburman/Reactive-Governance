// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReactiveVoting} from "./ReactiveVotingAbstract.sol";

contract VotingContract is ReactiveVoting, Ownable {
    mapping(address => bool) internal _authorizedProposers;

    // -- Events --
    event ProposerAdded(address indexed proposer);
    event ProposerRemoved(address indexed proposer);

    // -- Modifiers --
    modifier onlyAuthorizedProposer() {
        _onlyAuthorizedProposer();
        _;
    }

    function _onlyAuthorizedProposer() internal view {
        require(
            _authorizedProposers[msg.sender] || msg.sender == owner(),
            "ASRVotingContract: Caller is not an authorized proposer"
        );
    }

    constructor(address initialOwner, address stakingContract) Ownable(initialOwner) ReactiveVoting(stakingContract) {}

    function createProposal(
        string memory title,
        string memory description,
        ProposalCategory category,
        ProposalType proposalType,
        string[] memory choices,
        bytes memory exectionData,
        address target,
        uint256 value
    ) public override onlyAuthorizedProposer returns (uint256) {
        return super.createProposal(title, description, category, proposalType, choices, exectionData, target, value);
    }

    function cancelProposal(uint256 proposalId) public override onlyAuthorizedProposer {
        super.cancelProposal(proposalId);
    }

    // -- Owner Calls --
    function addAuthorizedProposer(address proposer) external onlyOwner {
        require(proposer != address(0), "Invalid Proposer");
        _authorizedProposers[proposer] = true;
        emit ProposerAdded(proposer);
    }

    function removeAuthorizedProposer(address proposer) external onlyOwner {
        _authorizedProposers[proposer] = false;
        emit ProposerRemoved(proposer);
    }
}
