// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title NFT Staking Contract
 * @dev This contract allows users to stake their NFTs and earn rewards over time based on defined piecewise reward intervals.
 */
contract NFTStaking is ERC20, Ownable {
    using Math for uint256;

    IERC721 public nftToken;
    uint256 public constant LOCK_PERIOD = 7 days;
    uint256 public constant SECONDS_PER_DAY = 86400;

    ////////////
    // STRUCT //
    ////////////
    struct Stake {
        uint256 tokenId;
        uint256 timestamp;
        uint256 lastClaimTimestamp;
        address owner;
    }

    struct PiecewiseInterval {
        uint256 start;
        uint256 end;
        int256 fixedValue; // Rewards in fixed intervals
        int256 variableBase; // Starting value in variable intervals
        bool isVariable;
    }

    mapping(uint256 => Stake) public vault;
    PiecewiseInterval[] public rewardIntervals;

    ////////////
    // EVENTS //
    ////////////
    event NFTStaked(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 timestamp
    );
    event NFTUnstaked(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 timestamp
    );
    event RewardsClaimed(address indexed owner, uint256 reward);

    /////////////////
    // CONSTRUCTOR //
    /////////////////
    /**
     * @notice Constructor to initialize the NFT staking contract
     * @param _nftToken Address of the NFT contract
     * @param _starts Array of starting days for reward intervals
     * @param _ends Array of ending days for reward intervals
     * @param _fixedValues Array of fixed reward values for intervals
     * @param _variableBases Array of variable base values for intervals
     * @param _isVariables Array indicating if intervals are variable or fixed
     */
    constructor(
        address _nftToken,
        uint256[4] memory _starts,
        uint256[4] memory _ends,
        int256[4] memory _fixedValues,
        int256[4] memory _variableBases,
        bool[4] memory _isVariables
    ) ERC20("Reward Token", "RWD") Ownable(msg.sender) {
        nftToken = IERC721(_nftToken);
        for (uint i = 0; i < 4; i++) {
            rewardIntervals.push(
                PiecewiseInterval(
                    _starts[i],
                    _ends[i],
                    _fixedValues[i],
                    _variableBases[i],
                    _isVariables[i]
                )
            );
        }
    }

    ///////////////////////
    // FUNCTIONS: setter //
    ///////////////////////
    /**
     * @notice Set reward intervals (only owner can call this)
     * @param _intervals Array of PiecewiseInterval structs to set new reward intervals
     */
    function setRewardIntervals(
        PiecewiseInterval[] memory _intervals
    ) public onlyOwner {
        require(_intervals.length > 0, "Invalid intervals length");
        delete rewardIntervals; // Sanity cleanup

        for (uint256 i = 0; i < _intervals.length; i++) {
            rewardIntervals.push(_intervals[i]);
        }
    }

    /**
     * @notice Stake an NFT to start earning rewards
     * @param _tokenId The ID of the NFT to stake
     */
    function stake(uint256 _tokenId) external {
        require(nftToken.ownerOf(_tokenId) == msg.sender, "Not the owner");
        require(vault[_tokenId].tokenId == 0, "Already staked");

        nftToken.transferFrom(msg.sender, address(this), _tokenId);
        vault[_tokenId] = Stake(
            _tokenId,
            block.timestamp,
            block.timestamp,
            msg.sender
        );

        emit NFTStaked(msg.sender, _tokenId, block.timestamp);
    }

    /**
     * @notice Unstake an NFT after the lock period has passed
     * @param _tokenId The ID of the NFT to unstake
     */
    function unstake(uint256 _tokenId) external {
        Stake memory staked = vault[_tokenId];
        require(staked.owner == msg.sender, "Not the owner");
        require(
            block.timestamp >= staked.timestamp + LOCK_PERIOD,
            "Still in lock period"
        );

        uint256 reward = calculateRewards(_tokenId);
        delete vault[_tokenId];
        nftToken.transferFrom(address(this), msg.sender, _tokenId);
        _mint(msg.sender, reward);

        emit NFTUnstaked(msg.sender, _tokenId, block.timestamp);
        emit RewardsClaimed(msg.sender, reward);
    }

    /**
     * @notice Calculate the total rewards for a staked NFT based on the staking duration and reward intervals
     * @param _tokenId The ID of the staked NFT
     * @return totalReward The total reward the user is entitled to
     */
    function calculateRewards(uint256 _tokenId) public view returns (uint256) {
        Stake memory staked = vault[_tokenId];
        if (staked.owner == address(0)) return 0;

        uint256 startDay = (staked.lastClaimTimestamp - staked.timestamp) /
            SECONDS_PER_DAY;
        uint256 endDay = (block.timestamp - staked.timestamp) / SECONDS_PER_DAY;
        uint256 totalReward = 0;

        for (uint256 i = 0; i < rewardIntervals.length; i++) {
            PiecewiseInterval memory interval = rewardIntervals[i];

            if (startDay >= interval.end) continue;
            if (endDay <= interval.start) break;

            uint256 intervalStartDay = Math.max(startDay, interval.start);
            uint256 intervalEndDay = Math.min(endDay, interval.end);
            uint256 daysInInterval = intervalEndDay - intervalStartDay;

            if (interval.isVariable) {
                int256 startValue = int256(intervalStartDay) *
                    interval.variableBase +
                    interval.fixedValue;
                int256 endValue = int256(intervalEndDay) *
                    interval.variableBase +
                    interval.fixedValue;
                int256 reward = ((startValue + endValue) *
                    int256(daysInInterval)) / 2;

                if (reward > 0) {
                    totalReward += uint256(reward);
                }
            } else {
                totalReward += daysInInterval * uint256(interval.fixedValue);
            }
        }

        return totalReward;
    }

    /**
     * @notice Claim rewards for a staked NFT
     * @param _tokenId The ID of the staked NFT
     */
    function claimRewards(uint256 _tokenId) external {
        Stake storage staked = vault[_tokenId];
        require(staked.owner == msg.sender, "Not the owner");

        uint256 reward = calculateRewards(_tokenId);
        require(reward > 0, "No rewards to claim");

        staked.lastClaimTimestamp = block.timestamp;
        _mint(msg.sender, reward);

        emit RewardsClaimed(msg.sender, reward);
    }

    function getRewardIntervalsLength() public view returns (uint256) {
        return rewardIntervals.length;
    }
}
