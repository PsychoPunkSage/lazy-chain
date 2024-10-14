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

        uint256[4] memory starts = [uint256(0), 7, 14, 21];
        uint256[4] memory ends = [uint256(7), 14, 21, 28];
        int256[4] memory fixedValues = [int256(7), 0, 14, 0];
        int256[4] memory variableBases = [int256(0), 1, 0, 1];
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

        (
            uint256 tokenId,
            uint256 timestamp,
            uint256 lastClaimTimestamp,
            address stakeOwner
        ) = stakingContract.vault(1);
        assertEq(tokenId, 1);
        assertEq(stakeOwner, user1);
        assertEq(timestamp, lastClaimTimestamp);
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
        uint256 initialBalance = stakingContract.balanceOf(user1);
        stakingContract.unstake(1);

        (uint256 tokenId, , , ) = stakingContract.vault(1);
        assertEq(tokenId, 0);
        assertEq(nftToken.ownerOf(1), user1);
        assertGt(stakingContract.balanceOf(user1), initialBalance);

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
        assertEq(rewards, 96); // 7*7 + 0.5(7+12)5

        uint256 initialBalance = stakingContract.balanceOf(user1);
        stakingContract.claimRewards(1);
        uint256 finalBalance = stakingContract.balanceOf(user1);
        assertEq(finalBalance - initialBalance, 96);

        vm.stopPrank();
    }

    function testRewardsAfter25Days() public {
        vm.startPrank(user1);
        stakingContract.stake(1);

        vm.warp(block.timestamp + 25 days);

        uint256 rewards = stakingContract.calculateRewards(1);
        assertEq(rewards, 312); // 49 + 73.5 + 14*7 + 0.5(21 + 25)4 = 312

        uint256 initialBalance = stakingContract.balanceOf(user1);
        stakingContract.claimRewards(1);
        uint256 finalBalance = stakingContract.balanceOf(user1);
        assertEq(finalBalance - initialBalance, 312);

        vm.stopPrank();
    }

    function testMultipleClaimsWithinPeriod() public {
        vm.startPrank(user1);
        stakingContract.stake(1);

        // Claim after 10 days
        vm.warp(block.timestamp + 10 days);
        uint256 firstReward = stakingContract.calculateRewards(1);
        stakingContract.claimRewards(1);

        // Claim after another 5 days (total 15 days)
        vm.warp(block.timestamp + 5 days);
        uint256 secondReward = stakingContract.calculateRewards(1);
        stakingContract.claimRewards(1);

        // Total rewards should be the same as if claimed once after 15 days
        vm.warp(block.timestamp - 15 days);
        stakingContract.stake(2);
        vm.warp(block.timestamp + 15 days);
        uint256 totalReward = stakingContract.calculateRewards(2);

        assertEq(firstReward + secondReward, totalReward);

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
