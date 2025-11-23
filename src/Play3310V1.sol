// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

// ==================== CUSTOM ERRORS ====================
error InvalidSignature();
error TransferFailed();
error InvalidDistribution();
error ScoreBelowQualification();

/**
 * @title Play3310
 * @dev Upgradeable gaming reward distribution contract with UUPS pattern
 */
contract Play3310V1 is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // ==================== VERSION ====================
    uint256 public constant VERSION = 1;

    // ==================== STRUCTS ====================
    struct PlayerWeeklyScore {
        address player;
        uint256 score;
        uint256 gameScore;
        uint256 gameCount;
        uint256 referralPoints;
        uint256 rank;
    }

    struct AllTimeStats {
        uint256 highestGameScore;
        uint256 highestWeeklyScore;
        uint256 totalGamesPlayed;
        uint256 totalReferralPoints;
        uint256 totalLifetimeScore;
    }

    // ==================== STATE ====================
    IERC20 public cUSD;
    address public backendSigner;

    uint256 public weeklyPrizePool;
    uint256 public minQualificationScore;
    uint256 public currentWeekPrizePool;
    uint256 public unclaimedRollover;
    uint256 public genesisTimestamp;

    uint256[] public prizeDistribution;

    // Leaderboard State
    mapping(uint256 => PlayerWeeklyScore[]) public weeklyLeaderboards;
    mapping(address => AllTimeStats) public playerAllTimeStats;
    mapping(uint256 => mapping(address => PlayerWeeklyScore)) public weeklyPlayerScores;
  
    event ContractUpgraded(address indexed newImplementation, uint256 version);
    event WeeklyLeaderboardSubmitted(uint256 indexed weekId, uint256 playerCount);
    event AllTimeStatsUpdated(address indexed player, uint256 newHighGameScore, uint256 newHighWeeklyScore);
    event ScoreSubmitted(address indexed player, uint256 weekId, uint256 score);
    event MinQualificationScoreUpdated(uint256 newScore);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ==================== INITIALIZATION ====================
    /**
     * @dev Initialize the contract
     * @param _cUSD Address of cUSD token
     * @param _backendSigner Address of backend signer
     * @param _initialOwner Address of initial owner
     * @param _genesisTimestamp Timestamp of the first Monday 00:00 UTC
     */
    function initialize(
        address _cUSD,
        address _backendSigner,
        address _initialOwner,
        uint256 _genesisTimestamp
    ) public initializer {
        __Ownable_init(_initialOwner);

        cUSD = IERC20(_cUSD);
        backendSigner = _backendSigner;
        weeklyPrizePool = 5 ether;
        minQualificationScore = 500;
        currentWeekPrizePool = weeklyPrizePool;
        unclaimedRollover = 0;
        genesisTimestamp = _genesisTimestamp;

        // Initialize prize distribution
        prizeDistribution = [3000, 2000, 1500, 1000, 800, 340, 340, 340, 340, 340];
    }

    // ==================== ADMIN FUNCTIONS ====================
    /**
     * @dev Update the minimum qualification score
     * @param _newScore New minimum score
     */
    function setMinQualificationScore(uint256 _newScore) external onlyOwner {
        minQualificationScore = _newScore;
        emit MinQualificationScoreUpdated(_newScore);
    }

    /**
     * @dev Fund the prize pool
     * @param amount Amount of cUSD to deposit
     */
    function fundPrizePool(uint256 amount) external onlyOwner {
        require(cUSD.transferFrom(msg.sender, address(this), amount), "Transfer failed");
    }

    // ==================== VIEW FUNCTIONS ====================
    /**
     * @dev Get the current week ID (1-based)
     */
    function getCurrentWeek() public view returns (uint256) {
        if (block.timestamp < genesisTimestamp) return 0;
        return (block.timestamp - genesisTimestamp) / 7 days + 1;
    }

    /**
     * @dev Check if current time is within submission period (Saturday 00:00 - Sunday 23:59)
     */
    function isSubmissionPeriod() public view returns (bool) {
        if (block.timestamp < genesisTimestamp) return false;
        uint256 timeIntoWeek = (block.timestamp - genesisTimestamp) % 7 days;
        // Saturday starts at day 5 (5 * 24 hours)
        return timeIntoWeek >= 5 days;
    }

    // ==================== LEADERBOARD FUNCTIONS ====================
    
    /**
     * @dev Compare two scores based on tiebreaker rules
     * @return true if scoreA is better than scoreB
     */
    function _isBetterScore(
        uint256 scoreA, uint256 gameCountA, uint256 referralPointsA,
        uint256 scoreB, uint256 gameCountB, uint256 referralPointsB
    ) internal pure returns (bool) {
        if (scoreA > scoreB) return true;
        if (scoreA < scoreB) return false;
        
        // Tiebreaker 1: Fewest Games Played (Lower is better)
        if (gameCountA < gameCountB) return true;
        if (gameCountA > gameCountB) return false;

        // Tiebreaker 2: Referral Points (Higher is better)
        if (referralPointsA > referralPointsB) return true;
        
        return false;
    }

    /**
     * @dev Submit score with backend signature and update Top 10
     */
    function submitScore(
        uint256 weekId,
        uint256 score,
        uint256 gameScore,
        uint256 gameCount,
        uint256 referralPoints,
        bytes calldata signature
    ) external {
        require(isSubmissionPeriod(), "Not submission period");
        require(weekId == getCurrentWeek(), "Invalid week");

        // Verify signature
        bytes32 messageHash = keccak256(
            abi.encodePacked(msg.sender, weekId, score, gameScore, gameCount, referralPoints)
        );
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        
        if (ethSignedMessageHash.recover(signature) != backendSigner) {
            revert InvalidSignature();
        }

        PlayerWeeklyScore memory newScore = PlayerWeeklyScore({
            player: msg.sender,
            score: score,
            gameScore: gameScore,
            gameCount: gameCount,
            referralPoints: referralPoints,
            rank: 0 
        });

        PlayerWeeklyScore memory prevScore = weeklyPlayerScores[weekId][msg.sender];

        // Update All-Time Stats with deltas
        _updateAllTimeStatsWithDelta(newScore, prevScore);

        // Update Weekly Mapping
        weeklyPlayerScores[weekId][msg.sender] = newScore;

        // Update Top 10 Leaderboard
        _updateTop10(weekId, newScore);

        emit ScoreSubmitted(msg.sender, weekId, score);
    }

    function _updateTop10(uint256 weekId, PlayerWeeklyScore memory newEntry) internal {
        PlayerWeeklyScore[] storage leaderboard = weeklyLeaderboards[weekId];
        
        // 1. Check if player is already in the leaderboard
        int256 existingIndex = -1;
        for (uint256 i = 0; i < leaderboard.length; i++) {
            if (leaderboard[i].player == newEntry.player) {
                existingIndex = int256(i);
                break;
            }
        }

        // 2. Remove existing entry if found (we will re-insert)
        if (existingIndex != -1) {
            for (uint256 i = uint256(existingIndex); i < leaderboard.length - 1; i++) {
                leaderboard[i] = leaderboard[i + 1];
            }
            leaderboard.pop();
        }

        // 3. Find insertion point
        // We only care if the score qualifies for Top 10 (or if list is not full)
        // Optimization: If list is full (10) and new score is worse than last place, ignore.
        if (leaderboard.length == 10) {
            PlayerWeeklyScore memory last = leaderboard[9];
            if (!_isBetterScore(newEntry.score, newEntry.gameCount, newEntry.referralPoints, last.score, last.gameCount, last.referralPoints)) {
                return; // Not good enough for Top 10
            }
        }

        // Find position
        uint256 insertAt = leaderboard.length;
        for (uint256 i = 0; i < leaderboard.length; i++) {
            if (_isBetterScore(newEntry.score, newEntry.gameCount, newEntry.referralPoints, leaderboard[i].score, leaderboard[i].gameCount, leaderboard[i].referralPoints)) {
                insertAt = i;
                break;
            }
        }

        // Insert and shift
        if (insertAt < 10) {
            if (leaderboard.length < 10) {
                leaderboard.push(newEntry); // Expand size
            }
            
            // Shift right from insertAt
            for (uint256 i = leaderboard.length - 1; i > insertAt; i--) {
                leaderboard[i] = leaderboard[i - 1];
            }
            
            leaderboard[insertAt] = newEntry;
            
            // Update Ranks
            for(uint256 i = 0; i < leaderboard.length; i++) {
                leaderboard[i].rank = i + 1;
            }
        }
    }

    function _updateAllTimeStatsWithDelta(
        PlayerWeeklyScore memory newScore, 
        PlayerWeeklyScore memory prevScore
    ) internal {
        AllTimeStats storage stats = playerAllTimeStats[newScore.player];

        if (newScore.gameScore > stats.highestGameScore) {
            stats.highestGameScore = newScore.gameScore;
        }

        if (newScore.score > stats.highestWeeklyScore) {
            stats.highestWeeklyScore = newScore.score;
        }

        // Calculate deltas (assuming newScore is cumulative for the week)
        // If newScore < prevScore (should not happen in normal flow, but possible if reorg/bug), handle gracefully
        if (newScore.gameCount >= prevScore.gameCount) {
            stats.totalGamesPlayed += (newScore.gameCount - prevScore.gameCount);
        }
        
        if (newScore.referralPoints >= prevScore.referralPoints) {
            stats.totalReferralPoints += (newScore.referralPoints - prevScore.referralPoints);
        }

        if (newScore.score >= prevScore.score) {
            stats.totalLifetimeScore += (newScore.score - prevScore.score);
        }

        emit AllTimeStatsUpdated(newScore.player, stats.highestGameScore, stats.highestWeeklyScore);
    }

    // Kept for backward compatibility with previous step's internal function signature if needed, 
    // but we replaced usage.
    function _updateAllTimeStats(PlayerWeeklyScore calldata score) internal {
        // This was the naive implementation. We redirect to delta version with empty prev.
        PlayerWeeklyScore memory empty;
        _updateAllTimeStatsWithDelta(score, empty);
    }

    /**
     * @dev Get weekly leaderboard for a specific week
     * @param weekId The week identifier
     */
    function getWeeklyLeaderboard(uint256 weekId) external view returns (PlayerWeeklyScore[] memory) {
        return weeklyLeaderboards[weekId];
    }

    /**
     * @dev Authorize upgrade to new implementation
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {
        emit ContractUpgraded(newImplementation, VERSION);
    }

    /**
     * @dev Get contract version
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}