// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {NFTStaking} from "../src/stake.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockNFT is ERC721 {
    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

contract NFTStakingTest is Test {
    MockNFT nftToken;
    NFTStaking stakingContract;
    address owner;
    address user1;

    function setUp() public {
        owner = address(this);
        user1 = address(0x123);
        nftToken = new MockNFT();

        // Set up the piecewise intervals as per the contract requirements
        uint256[4] memory starts = [uint256(0), 7, 14, 21];
        uint256[4] memory ends = [uint256(7), 14, 21, 28];
        uint256[4] memory fixedValues = [uint256(7), 0, 14, 0];
        uint256[4] memory variableBases = [uint256(0), 7, 0, 21];
        bool[4] memory isVariables = [false, true, false, true];

        stakingContract = new NFTStaking(
            address(nftToken),
            starts,
            ends,
            fixedValues,
            variableBases,
            isVariables
        );

        nftToken.mint(user1, 1);
        nftToken.mint(user1, 2);

        vm.startPrank(user1);
        nftToken.approve(address(stakingContract), 1);
        nftToken.approve(address(stakingContract), 2);
        vm.stopPrank();
    }

    function testStakeNFT() public {
        vm.startPrank(user1);
        stakingContract.stake(1);

        (uint256 tokenId, , address stakeOwner) = stakingContract.vault(1);
        assertEq(tokenId, 1);
        assertEq(stakeOwner, user1);
        assertEq(nftToken.ownerOf(1), address(stakingContract));

        vm.stopPrank();
    }

    function testUnstakeNFTBeforeLockPeriodFails() public {
        vm.startPrank(user1);
        stakingContract.stake(1);

        vm.warp(block.timestamp + 6 days);
        vm.expectRevert("Still in lock period");
        stakingContract.unstake(1);

        vm.stopPrank();
    }

    function testUnstakeNFTAfterLockPeriod() public {
        vm.startPrank(user1);
        stakingContract.stake(1);

        vm.warp(block.timestamp + 7 days);
        stakingContract.unstake(1);

        (uint256 tokenId, , ) = stakingContract.vault(1);
        assertEq(tokenId, 0);
        assertEq(nftToken.ownerOf(1), user1);

        vm.stopPrank();
    }

    function testRewardsAfter7Days() public {
        vm.startPrank(user1);
        stakingContract.stake(1);

        vm.warp(block.timestamp + 7 days);

        uint256 rewards = stakingContract.calculateRewards(1);
        assertEq(rewards, 49); // 7 * 7

        uint256 initialBalance = stakingContract.balanceOf(user1);
        stakingContract.claimRewards(1);
        uint256 finalBalance = stakingContract.balanceOf(user1);
        assertEq(finalBalance - initialBalance, 49);

        vm.stopPrank();
    }

    function testRewardsAfter12Days() public {
        vm.startPrank(user1);
        stakingContract.stake(1);

        vm.warp(block.timestamp + 12 days);

        uint256 rewards = stakingContract.calculateRewards(1);
        assertEq(rewards, 94); // 7*7 + (8+9+10+11+12)

        uint256 initialBalance = stakingContract.balanceOf(user1);
        stakingContract.claimRewards(1);
        uint256 finalBalance = stakingContract.balanceOf(user1);
        assertEq(finalBalance - initialBalance, 94);

        vm.stopPrank();
    }

    function testRewardsAfter17Days() public {
        vm.startPrank(user1);
        stakingContract.stake(1);

        vm.warp(block.timestamp + 17 days);

        uint256 rewards = stakingContract.calculateRewards(1);
        assertEq(rewards, 161); // 49 + (8+9+10+11+12+13+14) + 14*3

        uint256 initialBalance = stakingContract.balanceOf(user1);
        stakingContract.claimRewards(1);
        uint256 finalBalance = stakingContract.balanceOf(user1);
        assertEq(finalBalance - initialBalance, 161);

        vm.stopPrank();
    }

    function testRewardsAfter25Days() public {
        vm.startPrank(user1);
        stakingContract.stake(1);

        vm.warp(block.timestamp + 25 days);

        uint256 rewards = stakingContract.calculateRewards(1);
        assertEq(rewards, 273); // 49 + 77 + 14*7 + (22+23+24+25)

        uint256 initialBalance = stakingContract.balanceOf(user1);
        stakingContract.claimRewards(1);
        uint256 finalBalance = stakingContract.balanceOf(user1);
        assertEq(finalBalance - initialBalance, 273);

        vm.stopPrank();
    }

    function testStakingMultipleNFTs() public {
        vm.startPrank(user1);

        stakingContract.stake(1);
        stakingContract.stake(2);

        vm.warp(block.timestamp + 10 days);

        uint256 rewards1 = stakingContract.calculateRewards(1);
        uint256 rewards2 = stakingContract.calculateRewards(2);
        assertEq(rewards1, 83); // 49 (first interval) + (8+9+10)
        assertEq(rewards2, 83);

        uint256 initialBalance = stakingContract.balanceOf(user1);
        stakingContract.claimRewards(1);
        stakingContract.claimRewards(2);
        uint256 finalBalance = stakingContract.balanceOf(user1);
        assertEq(finalBalance - initialBalance, 166);

        vm.stopPrank();
    }

    function testResetRewardsAfterClaim() public {
        vm.startPrank(user1);
        stakingContract.stake(1);

        // vm.warp(block.timestamp + 10 days);
        // stakingContract.claimRewards(1);

        // vm.warp(block.timestamp + 5 days);
        // uint256 rewards = stakingContract.calculateRewards(1);
        // assertEq(rewards, 64); // (11+12+13+14+14)

        vm.warp(block.timestamp + 15 days);
        uint256 rewards = stakingContract.calculateRewards(1);
        assertEq(rewards, 126); // (7*5 + 8+9+10+11+12+13+14+ 14)

        vm.stopPrank();
    }
}

/*

0  - 7  : 7
7  - 14 : x
14 - 21 : 14
21 - 28 : x -7

10 days:
> 49 + (8 + 9 + 10) : 62

15 days:
> 62 + (11 + 12 + 13 + 14 + 14) : 62 + 64

*/
