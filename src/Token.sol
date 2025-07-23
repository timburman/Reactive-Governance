// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit, Nonces} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    /**
     * @dev The constructor now correctly initializes all necessary parent contracts.
     * - ERC20: Sets the token's name and symbol.
     * - ERC20Permit: Sets the EIP-712 domain name, which is used for permit signatures.
     * - Ownable: Sets the initial owner of the contract.
     * - ERC20Votes: Does not require arguments in its constructor.
     */
    constructor(address initialOwner) ERC20("MyToken", "MTK") ERC20Permit("MyToken") Ownable(initialOwner) {}

    /**
     * @dev Mints tokens to a specified address.
     * Restricted so that only the owner can call this function.
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    // The following functions are overrides required by Solidity's inheritance model.
    // They ensure that the logic from all parent contracts is correctly combined.
    // When a function is defined in multiple base contracts, the derived contract
    // must explicitly state which ones it is overriding.

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
