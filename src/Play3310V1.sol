// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Play3310V1
 * @dev Main game contract for 3310 - Real-time leaderboard with weekly rewards
 * @notice Supports real-time score submission with Top 10 leaderboard and reward escrow
 */
contract Play3310V1 is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using SafeERC20 for IERC20;

    // ==================== CUSTOM ERRORS ====================
    error InvalidSignature();
    error TransferFailed();
    error ScoreBelowQualification();
    error InvalidWeek();
    error WeekNotFinished();
    error NothingToDistribute();
    error AlreadyDistributed();
    error InsufficientBalance();
    error NoUnclaimedRewards();
    error InvalidClaimAmount();
    error InvalidCUSDAddress();
    error InvalidBackendSigner();
    error InvalidOwner();
    error InvalidGenesisTimestamp();
    error ScoreMustBePositive();
    error InvalidSignerAddress();
    error AmountMustBePositive();
    error InvalidRewardIndex();
    error RewardAlreadyClaimed();
    error GameCountMustBePositive();
    error NotCurrentWeek();
    error InsufficientContractBalance();
    error NoWinnersThisWeek();
    error InsufficientFunds();
    error ScoreCannotDecrease();
    error ScoreTooHigh();
    error GameCountCannotDecrease();

    // ==================== VERSION ====================
    uint256 public constant VERSION = 1;

    // ==================== STRUCTS ====================
    struct PlayerWeeklyScore {
        address player;
        uint256 score;              // Weekly accumulated score
        uint256 gameScore;          // Highest single game score
        uint256 gameCount;          // Total games played this week
        uint256 referralPoints;     // Referral points earned
        uint256 rank;               // Leaderboard rank (1-10)
    }

    struct AllTimeStats {
        uint256 highestGameScore;      // Highest single game all-time
        uint256 highestWeeklyScore;    // Highest weekly score all-time
        uint256 totalGamesPlayed;      // Total games across all weeks
        uint256 totalReferralPoints;   // Total referral points earned
        uint256 totalLifetimeScore;    // Total points across all weeks
    }

    struct WeeklyRewardPool {
        uint256 basePool;              // $5 base pool for the week
        uint256 rolloverAmount;        // Rolled over from previous week
        uint256 totalPool;             // basePool + rolloverAmount
        bool hasDistributed;           // Whether rewards have been distributed
    }

    struct UnclaimedReward {
        uint256 weekId;                // Week the reward was earned
        uint256 amount;                // Reward amount in wei
        bool claimed;                  // Whether this reward has been claimed
    }

    // ==================== STATE ====================
    IERC20 public cUSD;
    address public backendSigner;

    uint256 public weeklyBasePool;                  // $5 per week in wei
    uint256 public minQualificationScore;           // Default: 500
    uint256 public maxScore;                        // Maximum allowed score (anti-cheat)
    uint256 public genesisTimestamp;                // First Monday 00:00 UTC

    uint256[] public prizeDistribution;             // Basis points for each rank

    // Weekly leaderboards: weekId => PlayerWeeklyScore[]
    mapping(uint256 => PlayerWeeklyScore[]) public weeklyLeaderboards;

    // Weekly player scores for quick lookup: weekId => player => score
    mapping(uint256 => mapping(address => PlayerWeeklyScore)) public weeklyPlayerScores;

    // All-time stats for players
    mapping(address => AllTimeStats) public playerAllTimeStats;

    // Track weekly reward pools
    mapping(uint256 => WeeklyRewardPool) public weeklyRewardPools;

    // Track if week has been distributed
    mapping(uint256 => bool) private _isWeekDistributed;

    // Unclaimed rewards escrow: player => UnclaimedReward[]
    mapping(address => UnclaimedReward[]) public unclaimedRewards;

    // Total unclaimed amount per player (for quick lookups)
    mapping(address => uint256) public totalUnclaimedAmount;

    // P2: Store referral points on-chain
    mapping(address => uint256) public playerReferralPoints;

    // ==================== EVENTS ====================
    event ScoreSubmitted(
        address indexed player,
        uint256 indexed weekId,
        uint256 weeklyScore,
        uint256 gameScore,
        uint256 gameCount,
        uint256 rank
    );

    event LeaderboardUpdated(
        uint256 indexed weekId,
        uint256 topTenCount
    );

    event AllTimeStatsUpdated(
        address indexed player,
        uint256 highestGameScore,
        uint256 highestWeeklyScore
    );

    event RewardsDistributed(
        uint256 indexed weekId,
        uint256 totalDistributed,
        uint256 rolloverAmount
    );

    event RewardEscrowed(
        address indexed player,
        uint256 indexed weekId,
        uint256 amount
    );

    event RewardClaimed(
        address indexed player,
        uint256 totalAmount,
        uint256 weekCount
    );

    event MinQualificationScoreUpdated(uint256 newScore);

    event ContractUpgraded(address indexed newImplementation);

    event ReferralPointsUpdated(
        address indexed player,
        uint256 newPoints,
        uint256 delta
    );

    // ==================== MODIFIERS ====================
    modifier validWeek(uint256 _weekId) {
        if (_weekId == 0 || _weekId > getCurrentWeek()) revert InvalidWeek();
        _;
    }

    modifier onlyBackendSigner() {
        require(msg.sender == backendSigner, "Only backend signer");
        _;
    }

    // ==================== INITIALIZATION ====================
    /**
     * @dev Initialize the contract
     * @param _cUSD Address of cUSD token on Celo
     * @param _backendSigner Address authorized to sign scores
     * @param _initialOwner Address of contract owner
     * @param _genesisTimestamp Timestamp of first Monday 00:00 UTC
     */
    function initialize(
        address _cUSD,
        address _backendSigner,
        address _initialOwner,
        uint256 _genesisTimestamp
    ) public initializer {
        if (_cUSD == address(0)) revert InvalidCUSDAddress();
        if (_backendSigner == address(0)) revert InvalidBackendSigner();
        if (_initialOwner == address(0)) revert InvalidOwner();
        if (_genesisTimestamp == 0) revert InvalidGenesisTimestamp();

        __Ownable_init(_initialOwner);

        cUSD = IERC20(_cUSD);
        backendSigner = _backendSigner;
        weeklyBasePool = 5 ether;  // $5 in wei (assuming 18 decimals)
        minQualificationScore = 500;
        maxScore = 100000; // Maximum score limit
        genesisTimestamp = _genesisTimestamp;

        // Initialize prize distribution (basis points, total = 10000)
        prizeDistribution = [3000, 2000, 1500, 1000, 800, 340, 340, 340, 340, 340];
    }

    // ==================== ADMIN FUNCTIONS ====================
    /**
     * @dev Update minimum qualification score
     * @param _newScore New minimum score required
     */
    function setMinQualificationScore(uint256 _newScore) external onlyOwner {
        if (_newScore == 0) revert ScoreMustBePositive();
        minQualificationScore = _newScore;
        emit MinQualificationScoreUpdated(_newScore);
    }

    /**
     * @dev Update maximum score limit
     * @param _newMaxScore New maximum score
     */
    function setMaxScore(uint256 _newMaxScore) external onlyOwner {
        if (_newMaxScore == 0) revert ScoreMustBePositive();
        maxScore = _newMaxScore;
    }

    /**
     * @dev Update backend signer address
     * @param _newSigner New signer address
     */
    function setBackendSigner(address _newSigner) external onlyOwner {
        if (_newSigner == address(0)) revert InvalidSignerAddress();
        backendSigner = _newSigner;
    }

    /**
     * @dev Update weekly base pool amount
     * @param _newAmount New base pool in wei
     */
    function setWeeklyBasePool(uint256 _newAmount) external onlyOwner {
        if (_newAmount == 0) revert AmountMustBePositive();
        weeklyBasePool = _newAmount;
    }

    /**
     * @dev P2: Update referral points for a player (called by backend)
     * @param _player Player address
     * @param _points New total referral points
     */
    function updateReferralPoints(address _player, uint256 _points) external onlyBackendSigner {
        uint256 oldPoints = playerReferralPoints[_player];
        playerReferralPoints[_player] = _points;
        
        uint256 delta = _points > oldPoints ? _points - oldPoints : 0;
        
        emit ReferralPointsUpdated(_player, _points, delta);
    }

    /**
     * @dev Fund the contract for rewards
     * @param _amount Amount of cUSD to transfer
     */
    function fundRewardPool(uint256 _amount) external nonReentrant {
        if (_amount == 0) revert AmountMustBePositive();
        cUSD.safeTransferFrom(msg.sender, address(this), _amount);
    }

    /**
     * @dev Emergency withdraw - only owner
     * @param _amount Amount to withdraw
     */
    function emergencyWithdraw(uint256 _amount) external onlyOwner nonReentrant {
        if (_amount > cUSD.balanceOf(address(this))) revert InsufficientContractBalance();
        cUSD.safeTransfer(owner(), _amount);
    }

    // ==================== VIEW FUNCTIONS ====================
    /**
     * @dev Get current week number (1-based)
     */
    function getCurrentWeek() public view returns (uint256) {
        if (block.timestamp < genesisTimestamp) return 0;
        return (block.timestamp - genesisTimestamp) / 7 days + 1;
    }

    /**
     * @dev Get weekly leaderboard for a specific week
     * @param _weekId Week identifier
     */
    function getWeeklyLeaderboard(uint256 _weekId)
        external
        view
        validWeek(_weekId)
        returns (PlayerWeeklyScore[] memory)
    {
        return weeklyLeaderboards[_weekId];
    }

    /**
     * @dev P3: Get player's weekly stats
     * @param _weekId Week identifier
     * @param _player Player address
     */
    function getPlayerWeeklyStats(uint256 _weekId, address _player)
        external
        view
        validWeek(_weekId)
        returns (PlayerWeeklyScore memory)
    {
        return weeklyPlayerScores[_weekId][_player];
    }

    /**
     * @dev Get player's all-time stats
     * @param _player Player address
     */
    function getPlayerStats(address _player)
        external
        view
        returns (AllTimeStats memory)
    {
        return playerAllTimeStats[_player];
    }

    /**
     * @dev P2: Get player's on-chain referral points
     * @param _player Player address
     */
    function getReferralPoints(address _player) external view returns (uint256) {
        return playerReferralPoints[_player];
    }

    /**
     * @dev Get weekly reward pool info
     * @param _weekId Week identifier
     */
    function getWeeklyRewardPool(uint256 _weekId)
        external
        view
        validWeek(_weekId)
        returns (WeeklyRewardPool memory)
    {
        WeeklyRewardPool memory pool = weeklyRewardPools[_weekId];
        if (pool.basePool == 0) {
            // Initialize if not set
            pool.basePool = weeklyBasePool;
            if (_weekId > 1) {
                // Add rollover from previous week if available
                if (_isWeekDistributed[_weekId - 1]) {
                    pool.rolloverAmount = weeklyRewardPools[_weekId - 1].rolloverAmount;
                }
            }
            pool.totalPool = pool.basePool + pool.rolloverAmount;
        }
        return pool;
    }

    /**
     * @dev Get unclaimed rewards for a player
     * @param _player Player address
     */
    function getUnclaimedRewards(address _player)
        external
        view
        returns (UnclaimedReward[] memory)
    {
        return unclaimedRewards[_player];
    }

    /**
     * @dev Get total unclaimed amount for a player
     * @param _player Player address
     */
    function getTotalUnclaimedAmount(address _player)
        external
        view
        returns (uint256)
    {
        return totalUnclaimedAmount[_player];
    }

    /**
     * @dev Get contract version
     */
    function version() external pure returns (string memory) {
        return "1.0.0";
    }

    // ==================== LEADERBOARD FUNCTIONS ====================
    /**
     * @dev Internal function to compare two scores using tiebreaker rules
     * @notice Score already includes referral points
     * @return true if scoreA is better than scoreB
     */
    function _isBetterScore(
        uint256 scoreA,
        uint256 gameCountA,
        uint256 referralPointsA,
        uint256 scoreB,
        uint256 gameCountB,
        uint256 referralPointsB
    ) internal pure returns (bool) {
        // Primary: Highest score (already includes referral points)
        if (scoreA > scoreB) return true;
        if (scoreA < scoreB) return false;

        // Tied on score - now check tiebreakers
        
        // Tiebreaker 1: Fewest games played (more efficient)
        if (gameCountA < gameCountB) return true;
        if (gameCountA > gameCountB) return false;

        // Tiebreaker 2: Most referral points (as additional tiebreaker)
        if (referralPointsA > referralPointsB) return true;

        return false;
    }
    
    /**
     * @dev Submit score and update Top 10 leaderboard
     * @param _weekId Current week ID
     * @param _score Weekly accumulated score
     * @param _gameScore Highest single game score
     * @param _gameCount Total games played this week
     * @param _referralPoints Referral points earned
     * @param _signature Backend signature for verification
     */
    function submitScore(
        uint256 _weekId,
        uint256 _score,
        uint256 _gameScore,
        uint256 _gameCount,
        uint256 _referralPoints,
        bytes calldata _signature
    ) external {
        // Verify week is current
        if (_weekId != getCurrentWeek()) revert NotCurrentWeek();
        if (_score < minQualificationScore) revert ScoreBelowQualification();
        if (_gameCount == 0) revert GameCountMustBePositive();

        // Add upper bound validation
        if (_score > maxScore) revert ScoreTooHigh();
        if (_gameScore > maxScore) revert ScoreTooHigh();

        // Verify signature
        bytes32 messageHash = keccak256(
            abi.encodePacked(msg.sender, _weekId, _score, _gameScore, _gameCount, _referralPoints)
        );
        
        // Backend already uses signMessageSync which adds Ethereum prefix
        // So we recover directly without adding prefix again
        address signer = messageHash.toEthSignedMessageHash().recover(_signature);
        if (signer != backendSigner) revert InvalidSignature();

        // Get previous score if exists
        PlayerWeeklyScore memory prevScore = weeklyPlayerScores[_weekId][msg.sender];

        // Validate score can only increase (cumulative scoring)
        if (prevScore.score > 0) {
            if (_score < prevScore.score) revert ScoreCannotDecrease();
            if (_gameCount < prevScore.gameCount) revert GameCountCannotDecrease();
        }

        // Create player score entry
        PlayerWeeklyScore memory newScore = PlayerWeeklyScore({
            player: msg.sender,
            score: _score,
            gameScore: _gameScore,
            gameCount: _gameCount,
            referralPoints: _referralPoints,
            rank: 0
        });

        // Update all-time stats with delta
        _updateAllTimeStatsWithDelta(newScore, prevScore);

        // Update weekly mapping
        weeklyPlayerScores[_weekId][msg.sender] = newScore;

        // Update Top 10 leaderboard
        _updateTop10Leaderboard(_weekId, newScore);

        emit ScoreSubmitted(msg.sender, _weekId, _score, _gameScore, _gameCount, newScore.rank);
    }

    /**
     * @dev Internal: Update Top 10 leaderboard with new score
     */
    function _updateTop10Leaderboard(uint256 _weekId, PlayerWeeklyScore memory _newEntry) internal {
        PlayerWeeklyScore[] storage leaderboard = weeklyLeaderboards[_weekId];

        // 1. Find if player already exists
        int256 existingIndex = -1;
        for (uint256 i = 0; i < leaderboard.length; i++) {
            if (leaderboard[i].player == _newEntry.player) {
                existingIndex = int256(i);
                break;
            }
        }

        // 2. Remove existing entry if found
        if (existingIndex != -1) {
            for (uint256 i = uint256(existingIndex); i < leaderboard.length - 1; i++) {
                leaderboard[i] = leaderboard[i + 1];
            }
            leaderboard.pop();
        }

        // 3. If leaderboard is full and new score doesn't qualify, skip
        if (leaderboard.length >= 10) {
            PlayerWeeklyScore memory lastPlace = leaderboard[9];
            if (
                !_isBetterScore(
                    _newEntry.score,
                    _newEntry.gameCount,
                    _newEntry.referralPoints,
                    lastPlace.score,
                    lastPlace.gameCount,
                    lastPlace.referralPoints
                )
            ) {
                return;  // Not good enough for Top 10
            }
        }

        // 4. Find insertion point
        uint256 insertAt = leaderboard.length;
        for (uint256 i = 0; i < leaderboard.length; i++) {
            if (
                _isBetterScore(
                    _newEntry.score,
                    _newEntry.gameCount,
                    _newEntry.referralPoints,
                    leaderboard[i].score,
                    leaderboard[i].gameCount,
                    leaderboard[i].referralPoints
                )
            ) {
                insertAt = i;
                break;
            }
        }

        // 5. Insert and shift if position is valid
        if (insertAt < 10) {
            if (leaderboard.length < 10) {
                leaderboard.push(_newEntry);
            }

            // Shift entries to the right
            for (uint256 i = leaderboard.length - 1; i > insertAt; i--) {
                leaderboard[i] = leaderboard[i - 1];
            }

            leaderboard[insertAt] = _newEntry;

            // Update ranks for all entries
            for (uint256 i = 0; i < leaderboard.length; i++) {
                leaderboard[i].rank = i + 1;
            }

            emit LeaderboardUpdated(_weekId, leaderboard.length);
        }
    }

    /**
     * @dev Internal: Update all-time stats with delta from previous submission
     */
    function _updateAllTimeStatsWithDelta(
        PlayerWeeklyScore memory _newScore,
        PlayerWeeklyScore memory _prevScore
    ) internal {
        AllTimeStats storage stats = playerAllTimeStats[_newScore.player];

        // Update highest game score
        if (_newScore.gameScore > stats.highestGameScore) {
            stats.highestGameScore = _newScore.gameScore;
        }

        // Update highest weekly score
        if (_newScore.score > stats.highestWeeklyScore) {
            stats.highestWeeklyScore = _newScore.score;
        }

        // Calculate deltas (handling resubmissions)
        if (_newScore.gameCount > _prevScore.gameCount) {
            stats.totalGamesPlayed += (_newScore.gameCount - _prevScore.gameCount);
        }

        if (_newScore.referralPoints > _prevScore.referralPoints) {
            stats.totalReferralPoints += (_newScore.referralPoints - _prevScore.referralPoints);
        }

        if (_newScore.score > _prevScore.score) {
            stats.totalLifetimeScore += (_newScore.score - _prevScore.score);
        }

        emit AllTimeStatsUpdated(
            _newScore.player,
            stats.highestGameScore,
            stats.highestWeeklyScore
        );
    }

    // ==================== REWARD FUNCTIONS ====================
    /**
     * @dev Distribute rewards for a completed week (called by owner on Monday)
     * @param _weekId Week to distribute rewards for
     */
    function distributeRewards(uint256 _weekId) external onlyOwner nonReentrant validWeek(_weekId) {
        if (_weekId >= getCurrentWeek()) revert WeekNotFinished();
        if (_isWeekDistributed[_weekId]) revert AlreadyDistributed();

        PlayerWeeklyScore[] memory winners = weeklyLeaderboards[_weekId];
        if (winners.length == 0) revert NoWinnersThisWeek();

        // Get or calculate reward pool
        WeeklyRewardPool storage pool = weeklyRewardPools[_weekId];
        if (pool.basePool == 0) {
            pool.basePool = weeklyBasePool;
            if (_weekId > 1 && _isWeekDistributed[_weekId - 1]) {
                pool.rolloverAmount = weeklyRewardPools[_weekId - 1].rolloverAmount;
            }
            pool.totalPool = pool.basePool + pool.rolloverAmount;
        }

        // Verify sufficient balance
        if (cUSD.balanceOf(address(this)) < pool.totalPool) revert InsufficientContractBalance();

        uint256 distributedAmount = 0;
        uint256 rolloverForNextWeek = 0;

        // Distribute to Top 10 winners (only to qualified players)
        for (uint256 i = 0; i < winners.length && i < prizeDistribution.length; i++) {
            uint256 reward = (pool.totalPool * prizeDistribution[i]) / 10000;

            if (winners[i].score >= minQualificationScore) {
                // Place reward in escrow instead of transferring immediately
                _addToEscrow(winners[i].player, _weekId, reward);
                distributedAmount += reward;
            } else {
                // Should not happen if Top 10 is filtered correctly
                rolloverForNextWeek += reward;
            }
        }

        // Calculate rollover for unfilled ranks
        if (winners.length < 10) {
            for (uint256 i = winners.length; i < 10 && i < prizeDistribution.length; i++) {
                uint256 unclaimedReward = (pool.totalPool * prizeDistribution[i]) / 10000;
                rolloverForNextWeek += unclaimedReward;
            }
        }

        // Update state
        pool.hasDistributed = true;
        pool.rolloverAmount = rolloverForNextWeek;
        _isWeekDistributed[_weekId] = true;

        emit RewardsDistributed(_weekId, distributedAmount, rolloverForNextWeek);
    }

    /**
     * @dev Internal: Add reward amount to player's escrow
     * @param _player Player address
     * @param _weekId Week earned
     * @param _amount Reward amount
     */
    function _addToEscrow(address _player, uint256 _weekId, uint256 _amount) internal {
        unclaimedRewards[_player].push(UnclaimedReward({
            weekId: _weekId,
            amount: _amount,
            claimed: false
        }));
        totalUnclaimedAmount[_player] += _amount;
        emit RewardEscrowed(_player, _weekId, _amount);
    }

    /**
     * @dev Claim unclaimed rewards - can claim multiple weeks at once
     * @param _indices Array of indices of unclaimed rewards to claim (optional filter, if empty claims all)
     */
    function claimRewards(uint256[] calldata _indices) external nonReentrant {
        UnclaimedReward[] storage rewards = unclaimedRewards[msg.sender];
        if (rewards.length == 0) revert NoUnclaimedRewards();

        uint256 totalClaim = 0;
        uint256 claimedCount = 0;

        if (_indices.length == 0) {
            // Claim all unclaimed rewards
            for (uint256 i = 0; i < rewards.length; i++) {
                if (!rewards[i].claimed) {
                    totalClaim += rewards[i].amount;
                    rewards[i].claimed = true;
                    claimedCount++;
                }
            }
        } else {
            // Claim specific indices
            for (uint256 i = 0; i < _indices.length; i++) {
                uint256 idx = _indices[i];
                if (idx >= rewards.length) revert InvalidRewardIndex();
                if (rewards[idx].claimed) revert RewardAlreadyClaimed();
                
                totalClaim += rewards[idx].amount;
                rewards[idx].claimed = true;
                claimedCount++;
            }
        }

        if (totalClaim == 0) revert InvalidClaimAmount();
        if (cUSD.balanceOf(address(this)) < totalClaim) revert InsufficientContractBalance();

        totalUnclaimedAmount[msg.sender] -= totalClaim;
        cUSD.safeTransfer(msg.sender, totalClaim);

        emit RewardClaimed(msg.sender, totalClaim, claimedCount);
    }

    /**
     * @dev Get rollover amount for next week
     * @param _weekId Current week
     */
    function getRolloverAmount(uint256 _weekId) external view returns (uint256) {
        if (_isWeekDistributed[_weekId]) {
            return weeklyRewardPools[_weekId].rolloverAmount;
        }
        return 0;
    }

    // ==================== UPGRADE FUNCTIONS ====================
    /**
     * @dev Authorize upgrade to new implementation
     * @param _newImplementation Address of new implementation
     */
    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {
        emit ContractUpgraded(_newImplementation);
    }
}