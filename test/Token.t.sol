// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, Vm} from "forge-std/Test.sol";
import {MyToken} from "../src/Token.sol";
import {console} from "forge-std/console.sol";

contract MyTokenTest is Test {
    MyToken public token;
    address public owner;
    address public user1;
    address public user2;

    uint256 constant INITIAL_MINT_AMOUNT = 1_000_000e18;

    function setUp() public {
        owner = address(this);
        // Create some test users
        user1 = vm.addr(1);
        user2 = vm.addr(2);

        // Deploy the token with the test contract as the owner
        token = new MyToken(owner);

        // Mint initial supply to user1
        vm.startPrank(owner);
        token.mint(user1, INITIAL_MINT_AMOUNT);
        vm.stopPrank();

        // Give user2 some tokens to test transfers from a non-owner
        vm.prank(user1);
        token.transfer(user2, 100e18);
    }

    // --- Gas Report for Successful Operations ---

    function testGas_Transfer_Success() public {
        vm.prank(user1);
        token.transfer(user2, 10e18);
    }

    function testGas_Approve_Success() public {
        vm.prank(user1);
        token.approve(user2, 50e18);
    }

    function testGas_TransferFrom_Success() public {
        // user1 approves user2 to spend tokens
        vm.prank(user1);
        token.approve(user2, 50e18);

        // user2 spends the allowance
        vm.prank(user2);
        token.transferFrom(user1, user2, 20e18);
    }

    function testGas_Delegate_FirstTime() public {
        // user1 delegates their voting power to themselves
        vm.prank(user1);
        token.delegate(user1);
    }

    function testGas_Delegate_ChangeDelegate() public {
        // First, delegate to user1
        vm.prank(user1);
        token.delegate(user1);

        // Then, change delegation to user2
        vm.prank(user1);
        token.delegate(user2);
    }

    function testGas_Mint_Success() public {
        vm.prank(owner);
        token.mint(user1, 1e18);
    }

    // --- Edge Case Scenarios ---

    function testGas_Transfer_FullBalance() public {
        uint256 balance = token.balanceOf(user2);
        vm.prank(user2);
        token.transfer(user1, balance);
    }

    function testGas_Transfer_ZeroTokens() public {
        vm.prank(user1);
        token.transfer(user2, 0);
    }

    function testGas_Approve_MaxUint() public {
        vm.prank(user1);
        token.approve(user2, type(uint256).max);
    }

    function testGas_Approve_ChangeValue() public {
        // First approval
        vm.prank(user1);
        token.approve(user2, 50e18);

        // Second approval to a different value
        vm.prank(user1);
        token.approve(user2, 100e18);
    }

    // --- Expected Revert Scenarios ---
    // These show the gas cost of failed transactions.

    function testRevert_Transfer_InsufficientBalance() public {
        vm.prank(user1);
        // user1 tries to send more than they have
        vm.expectRevert();
        token.transfer(user2, INITIAL_MINT_AMOUNT + 1);
    }

    function testRevert_TransferFrom_InsufficientAllowance() public {
        // user1 approves 50 tokens for user2
        vm.prank(user1);
        token.approve(user2, 50e18);

        // user2 tries to spend 51 tokens
        vm.prank(user2);
        vm.expectRevert();
        token.transferFrom(user1, owner, 51e18);
    }

    function testRevert_Mint_NotOwner() public {
        vm.prank(user1); // A non-owner tries to mint
        vm.expectRevert();
        token.mint(user1, 1e18);
    }
}
