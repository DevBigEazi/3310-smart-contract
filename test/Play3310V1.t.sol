// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/Play3310V1.sol";
import "../src/Play3310Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockCUSD is ERC20 {
    constructor() ERC20("Celo Dollar", "cUSD") {
        _mint(msg.sender, 1000000 ether);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract Play3310V1Test is Test {
    Play3310V1 public implementation;
    Play3310Proxy public proxy;
    Play3310V1 public play3310;
    MockCUSD public cUSD;

    address public owner = address(1);
    uint256 public backendSignerKey = 0xB0B;
    address public backendSigner = vm.addr(backendSignerKey);
    address public player1 = address(3);
    address public player2 = address(4);
    address public player3 = address(5);

    uint256 public genesisTimestamp;

    function setUp() public {
        vm.startPrank(owner);

        // Set genesis to start of day 1 (e.g., 2025-11-17 00:00:00 UTC)
        genesisTimestamp = 1763337600;
        vm.warp(genesisTimestamp); // Start at genesis

        cUSD = new MockCUSD();
        implementation = new Play3310V1();

        // Deploy proxy which initializes the implementation
        proxy = new Play3310Proxy(
            address(implementation),
            address(cUSD),
            backendSigner,
            owner,
            genesisTimestamp
        );

        play3310 = Play3310V1(address(proxy));

        vm.stopPrank();
    }

    // ==================== HELPER FUNCTIONS ====================
    function signScore(
        address player,
        uint256 dayId,
        uint256 score,
        uint256 gameScore,
        uint256 gameCount,
        uint256 referralPoints
    ) internal view returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                player,
                dayId,
                score,
                gameScore,
                gameCount,
                referralPoints
            )
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            backendSignerKey,
            ethSignedMessageHash
        );
        return abi.encodePacked(r, s, v);
    }

    // ==================== INITIALIZATION & SETUP TESTS ====================
    function testInitialization() public view {
        assertEq(address(play3310.cUSD()), address(cUSD));
        assertEq(play3310.backendSigner(), backendSigner);
        assertEq(play3310.genesisTimestamp(), genesisTimestamp);
        assertEq(play3310.minQualificationScore(), 500);
        assertEq(play3310.dailyBasePool(), 5 ether);
        assertEq(play3310.VERSION(), 1);
    }

    function testInvalidInitialization_ZeroCUSD() public {
        vm.startPrank(owner);
        Play3310V1 impl = new Play3310V1();
        vm.expectRevert(Play3310V1.InvalidCUSDAddress.selector);
        new Play3310Proxy(
            address(impl),
            address(0),
            backendSigner,
            owner,
            genesisTimestamp
        );
        vm.stopPrank();
    }

    function testInvalidInitialization_ZeroBackendSigner() public {
        vm.startPrank(owner);
        Play3310V1 impl = new Play3310V1();
        vm.expectRevert(Play3310V1.InvalidBackendSigner.selector);
        new Play3310Proxy(
            address(impl),
            address(cUSD),
            address(0),
            owner,
            genesisTimestamp
        );
        vm.stopPrank();
    }

    function testInvalidInitialization_ZeroOwner() public {
        vm.startPrank(owner);
        Play3310V1 impl = new Play3310V1();
        vm.expectRevert(Play3310V1.InvalidOwner.selector);
        new Play3310Proxy(
            address(impl),
            address(cUSD),
            backendSigner,
            address(0),
            genesisTimestamp
        );
        vm.stopPrank();
    }

    function testInvalidInitialization_ZeroGenesisTimestamp() public {
        vm.startPrank(owner);
        Play3310V1 impl = new Play3310V1();
        vm.expectRevert(Play3310V1.InvalidGenesisTimestamp.selector);
        new Play3310Proxy(
            address(impl),
            address(cUSD),
            backendSigner,
            owner,
            0
        );
        vm.stopPrank();
    }

    // ==================== DAY CALCULATION TESTS ====================
    function testGetCurrentDay() public {
        // At genesis, should be day 1
        assertEq(play3310.getCurrentDay(), 1);

        // Advance 23 hours (still day 1)
        vm.warp(genesisTimestamp + 23 hours);
        assertEq(play3310.getCurrentDay(), 1);

        // Advance to start of day 2
        vm.warp(genesisTimestamp + 1 days);
        assertEq(play3310.getCurrentDay(), 2);

        // Advance to day 10
        vm.warp(genesisTimestamp + 9 days);
        assertEq(play3310.getCurrentDay(), 10);
    }

    function testGetCurrentDay_BeforeGenesis() public {
        vm.warp(genesisTimestamp - 1 days);
        assertEq(play3310.getCurrentDay(), 0);
    }

    // ==================== ADMIN FUNCTIONS TESTS ====================
    function testSetMinQualificationScore() public {
        vm.startPrank(owner);
        assertEq(play3310.minQualificationScore(), 500);

        play3310.setMinQualificationScore(600);
        assertEq(play3310.minQualificationScore(), 600);
        vm.stopPrank();
    }

    function testSetMinQualificationScore_InvalidZero() public {
        vm.startPrank(owner);
        vm.expectRevert(Play3310V1.ScoreMustBePositive.selector);
        play3310.setMinQualificationScore(0);
        vm.stopPrank();
    }

    function testSetMinQualificationScore_OnlyOwner() public {
        vm.startPrank(player1);
        vm.expectRevert();
        play3310.setMinQualificationScore(600);
        vm.stopPrank();
    }

    function testSetBackendSigner() public {
        address newSigner = address(99);
        vm.startPrank(owner);
        play3310.setBackendSigner(newSigner);
        assertEq(play3310.backendSigner(), newSigner);
        vm.stopPrank();
    }

    function testSetBackendSigner_InvalidZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(Play3310V1.InvalidSignerAddress.selector);
        play3310.setBackendSigner(address(0));
        vm.stopPrank();
    }

    function testSetBackendSigner_OnlyOwner() public {
        vm.startPrank(player1);
        vm.expectRevert();
        play3310.setBackendSigner(address(99));
        vm.stopPrank();
    }

    function testSetDailyBasePool() public {
        vm.startPrank(owner);
        play3310.setDailyBasePool(10 ether);
        assertEq(play3310.dailyBasePool(), 10 ether);
        vm.stopPrank();
    }

    function testSetDailyBasePool_InvalidZero() public {
        vm.startPrank(owner);
        vm.expectRevert(Play3310V1.AmountMustBePositive.selector);
        play3310.setDailyBasePool(0);
        vm.stopPrank();
    }

    function testSetDailyBasePool_OnlyOwner() public {
        vm.startPrank(player1);
        vm.expectRevert();
        play3310.setDailyBasePool(10 ether);
        vm.stopPrank();
    }

    function testFundRewardPool() public {
        address funder = address(0x999);
        cUSD.mint(funder, 100 ether);

        vm.startPrank(funder);
        cUSD.approve(address(play3310), 50 ether);
        play3310.fundRewardPool(50 ether);
        vm.stopPrank();

        assertEq(cUSD.balanceOf(address(play3310)), 50 ether);
    }

    function testFundRewardPool_InvalidZero() public {
        address funder = address(0x999);
        cUSD.mint(funder, 100 ether);

        vm.startPrank(funder);
        cUSD.approve(address(play3310), 50 ether);
        vm.expectRevert(Play3310V1.AmountMustBePositive.selector);
        play3310.fundRewardPool(0);
        vm.stopPrank();
    }

    function testEmergencyWithdraw() public {
        // Fund the contract
        vm.startPrank(owner);
        cUSD.approve(address(play3310), 100 ether);
        play3310.fundRewardPool(100 ether);

        uint256 balanceBefore = cUSD.balanceOf(owner);
        play3310.emergencyWithdraw(50 ether);
        uint256 balanceAfter = cUSD.balanceOf(owner);

        assertEq(balanceAfter - balanceBefore, 50 ether);
        assertEq(cUSD.balanceOf(address(play3310)), 50 ether);
        vm.stopPrank();
    }

    function testEmergencyWithdraw_InsufficientBalance() public {
        vm.startPrank(owner);
        vm.expectRevert(Play3310V1.InsufficientContractBalance.selector);
        play3310.emergencyWithdraw(100 ether);
        vm.stopPrank();
    }

    function testEmergencyWithdraw_OnlyOwner() public {
        vm.startPrank(player1);
        vm.expectRevert();
        play3310.emergencyWithdraw(1 ether);
        vm.stopPrank();
    }

    // ==================== SCORE SUBMISSION TESTS ====================
    function testSubmitScore() public {
        uint256 dayId = 1;
        uint256 score = 1000;
        uint256 gameScore = 500;
        uint256 gameCount = 2;
        uint256 referralPoints = 100;

        bytes memory signature = signScore(
            player1,
            dayId,
            score,
            gameScore,
            gameCount,
            referralPoints
        );

        vm.startPrank(player1);
        play3310.submitScore(
            dayId,
            score,
            gameScore,
            gameCount,
            referralPoints,
            signature
        );
        vm.stopPrank();

        // Verify score was recorded
        Play3310V1.PlayerDailyScore[] memory leaderboard = play3310
            .getDailyLeaderboard(dayId);
        assertEq(leaderboard.length, 1);
        assertEq(leaderboard[0].player, player1);
        assertEq(leaderboard[0].score, score);
    }

    function testSubmitScore_NotCurrentDay() public {
        uint256 dayId = 2; // Wrong day (current is 1)
        uint256 score = 1000;
        uint256 gameScore = 500;
        uint256 gameCount = 2;
        uint256 referralPoints = 100;

        bytes memory signature = signScore(
            player1,
            dayId,
            score,
            gameScore,
            gameCount,
            referralPoints
        );

        vm.startPrank(player1);
        vm.expectRevert(Play3310V1.NotCurrentDay.selector);
        play3310.submitScore(
            dayId,
            score,
            gameScore,
            gameCount,
            referralPoints,
            signature
        );
        vm.stopPrank();
    }

    function testSubmitScore_BelowQualification() public {
        uint256 dayId = 1;
        uint256 score = 100; // Below 500 qualification
        uint256 gameScore = 50;
        uint256 gameCount = 2;
        uint256 referralPoints = 0;

        bytes memory signature = signScore(
            player1,
            dayId,
            score,
            gameScore,
            gameCount,
            referralPoints
        );

        vm.startPrank(player1);
        vm.expectRevert(Play3310V1.ScoreBelowQualification.selector);
        play3310.submitScore(
            dayId,
            score,
            gameScore,
            gameCount,
            referralPoints,
            signature
        );
        vm.stopPrank();
    }

    function testSubmitScore_ZeroGameCount() public {
        uint256 dayId = 1;
        uint256 score = 1000;
        uint256 gameScore = 500;
        uint256 gameCount = 0; // Invalid
        uint256 referralPoints = 100;

        bytes memory signature = signScore(
            player1,
            dayId,
            score,
            gameScore,
            gameCount,
            referralPoints
        );

        vm.startPrank(player1);
        vm.expectRevert(Play3310V1.GameCountMustBePositive.selector);
        play3310.submitScore(
            dayId,
            score,
            gameScore,
            gameCount,
            referralPoints,
            signature
        );
        vm.stopPrank();
    }

    function testSubmitScore_InvalidSignature() public {
        uint256 dayId = 1;
        uint256 score = 1000;
        uint256 gameScore = 500;
        uint256 gameCount = 2;
        uint256 referralPoints = 100;

        // Create invalid signature
        bytes memory signature = new bytes(65);

        vm.startPrank(player1);
        vm.expectRevert(); // ECDSAInvalidSignature from OpenZeppelin
        play3310.submitScore(
            dayId,
            score,
            gameScore,
            gameCount,
            referralPoints,
            signature
        );
        vm.stopPrank();
    }

    function testSubmitScore_UpdateExisting() public {
        uint256 dayId = 1;

        // First submission
        bytes memory signature1 = signScore(player1, dayId, 1000, 500, 2, 100);
        vm.startPrank(player1);
        play3310.submitScore(dayId, 1000, 500, 2, 100, signature1);
        vm.stopPrank();

        // Second submission with higher score
        bytes memory signature2 = signScore(player1, dayId, 1500, 600, 3, 150);
        vm.startPrank(player1);
        play3310.submitScore(dayId, 1500, 600, 3, 150, signature2);
        vm.stopPrank();

        // Verify updated score
        Play3310V1.PlayerDailyScore[] memory leaderboard = play3310
            .getDailyLeaderboard(dayId);
        assertEq(leaderboard.length, 1);
        assertEq(leaderboard[0].score, 1500);
    }

    function testSubmitScore_Top10Leaderboard() public {
        uint256 dayId = 1;

        // Submit 12 scores
        for (uint256 i = 0; i < 12; i++) {
            address player = address(uint160(100 + i));
            uint256 score = 1000 + (i * 100);
            bytes memory signature = signScore(
                player,
                dayId,
                score,
                score,
                1,
                0
            );

            vm.startPrank(player);
            play3310.submitScore(dayId, score, score, 1, 0, signature);
            vm.stopPrank();
        }

        // Verify only top 10 are in leaderboard
        Play3310V1.PlayerDailyScore[] memory leaderboard = play3310
            .getDailyLeaderboard(dayId);
        assertEq(leaderboard.length, 10);

        // Verify they are sorted (highest first)
        assertEq(leaderboard[0].score, 2100); // Highest score
        assertEq(leaderboard[9].score, 1200); // 10th highest
    }

    function testSubmitScore_TiebreakerGameCount() public {
        uint256 dayId = 1;

        // Player1: score 1000, 5 games
        bytes memory sig1 = signScore(player1, dayId, 1000, 500, 5, 0);
        vm.startPrank(player1);
        play3310.submitScore(dayId, 1000, 500, 5, 0, sig1);
        vm.stopPrank();

        // Player2: score 1000, 3 games (should rank higher)
        bytes memory sig2 = signScore(player2, dayId, 1000, 500, 3, 0);
        vm.startPrank(player2);
        play3310.submitScore(dayId, 1000, 500, 3, 0, sig2);
        vm.stopPrank();

        Play3310V1.PlayerDailyScore[] memory leaderboard = play3310
            .getDailyLeaderboard(dayId);
        assertEq(leaderboard[0].player, player2); // Fewer games wins
        assertEq(leaderboard[1].player, player1);
    }

    function testSubmitScore_TiebreakerReferralPoints() public {
        uint256 dayId = 1;

        // Player1: score 1000, 3 games, 50 referral points
        bytes memory sig1 = signScore(player1, dayId, 1000, 500, 3, 50);
        vm.startPrank(player1);
        play3310.submitScore(dayId, 1000, 500, 3, 50, sig1);
        vm.stopPrank();

        // Player2: score 1000, 3 games, 100 referral points (should rank higher)
        bytes memory sig2 = signScore(player2, dayId, 1000, 500, 3, 100);
        vm.startPrank(player2);
        play3310.submitScore(dayId, 1000, 500, 3, 100, sig2);
        vm.stopPrank();

        Play3310V1.PlayerDailyScore[] memory leaderboard = play3310
            .getDailyLeaderboard(dayId);
        assertEq(leaderboard[0].player, player2); // More referral points wins
        assertEq(leaderboard[1].player, player1);
    }

    function testSubmitScore_TiebreakerEqual() public {
        // Test when all tiebreakers are equal
        uint256 dayId = 1;

        // Player1: score 1000, 3 games, 100 referral points
        bytes memory sig1 = signScore(player1, dayId, 1000, 500, 3, 100);
        vm.startPrank(player1);
        play3310.submitScore(dayId, 1000, 500, 3, 100, sig1);
        vm.stopPrank();

        // Player2: score 1000, 3 games, 100 referral points (exactly equal)
        bytes memory sig2 = signScore(player2, dayId, 1000, 500, 3, 100);
        vm.startPrank(player2);
        play3310.submitScore(dayId, 1000, 500, 3, 100, sig2);
        vm.stopPrank();

        // Player3: score 1000, 3 games, 50 referral points (lower referral points)
        bytes memory sig3 = signScore(player3, dayId, 1000, 500, 3, 50);
        vm.startPrank(player3);
        play3310.submitScore(dayId, 1000, 500, 3, 50, sig3);
        vm.stopPrank();

        Play3310V1.PlayerDailyScore[] memory leaderboard = play3310
            .getDailyLeaderboard(dayId);
        assertEq(leaderboard.length, 3);
        assertEq(leaderboard[2].player, player3); // Lowest referral points
    }

    // ==================== ALL-TIME STATS TESTS ====================
    function testAllTimeStats_Update() public {
        uint256 dayId = 1;
        bytes memory signature = signScore(player1, dayId, 1000, 500, 2, 100);

        vm.startPrank(player1);
        play3310.submitScore(dayId, 1000, 500, 2, 100, signature);
        vm.stopPrank();

        // Check all-time stats
        Play3310V1.AllTimeStats memory stats = play3310.getPlayerStats(player1);

        assertEq(stats.highestGameScore, 500);
        assertEq(stats.highestDailyScore, 1000);
        assertEq(stats.totalGamesPlayed, 2);
        assertEq(stats.totalReferralPoints, 100);
        assertEq(stats.totalLifetimeScore, 1000);
    }

    function testAllTimeStats_MultipleDays() public {
        // Day 1
        bytes memory sig1 = signScore(player1, 1, 1000, 500, 2, 100);
        vm.startPrank(player1);
        play3310.submitScore(1, 1000, 500, 2, 100, sig1);
        vm.stopPrank();

        // Day 2
        vm.warp(genesisTimestamp + 1 days);
        bytes memory sig2 = signScore(player1, 2, 1200, 600, 3, 150);
        vm.startPrank(player1);
        play3310.submitScore(2, 1200, 600, 3, 150, sig2);
        vm.stopPrank();

        // Check all-time stats
        Play3310V1.AllTimeStats memory stats = play3310.getPlayerStats(player1);

        assertEq(stats.highestGameScore, 600);
        assertEq(stats.highestDailyScore, 1200);
        assertEq(stats.totalGamesPlayed, 5); // 2 + 3
        assertEq(stats.totalReferralPoints, 250); // 100 + 150
        assertEq(stats.totalLifetimeScore, 2200); // 1000 + 1200
    }

    function testAllTimeStats_UpdateWithinDay() public {
        uint256 dayId = 1;

        // First submission
        bytes memory sig1 = signScore(player1, dayId, 1000, 500, 2, 100);
        vm.startPrank(player1);
        play3310.submitScore(dayId, 1000, 500, 2, 100, sig1);
        vm.stopPrank();

        // Second submission in same day (delta update)
        bytes memory sig2 = signScore(player1, dayId, 1500, 600, 4, 150);
        vm.startPrank(player1);
        play3310.submitScore(dayId, 1500, 600, 4, 150, sig2);
        vm.stopPrank();

        // Check all-time stats (should only count delta)
        Play3310V1.AllTimeStats memory stats = play3310.getPlayerStats(player1);

        assertEq(stats.highestGameScore, 600);
        assertEq(stats.highestDailyScore, 1500);
        assertEq(stats.totalGamesPlayed, 4);
        assertEq(stats.totalReferralPoints, 150);
        assertEq(stats.totalLifetimeScore, 1500);
    }

    // ==================== REWARD DISTRIBUTION TESTS ====================
    function testDistributeRewards() public {
        // Fund contract
        vm.startPrank(owner);
        cUSD.approve(address(play3310), 100 ether);
        play3310.fundRewardPool(100 ether);
        vm.stopPrank();

        // Submit scores in day 1
        for (uint256 i = 0; i < 5; i++) {
            address player = address(uint160(100 + i));
            uint256 score = 1000 + (i * 100);
            bytes memory signature = signScore(player, 1, score, score, 1, 0);

            vm.startPrank(player);
            play3310.submitScore(1, score, score, 1, 0, signature);
            vm.stopPrank();
        }

        // Move to day 2 to distribute day 1 rewards
        vm.warp(genesisTimestamp + 1 days);

        vm.startPrank(owner);
        play3310.distributeRewards(1);
        vm.stopPrank();

        // Verify distribution happened
        Play3310V1.DailyRewardPool memory pool = play3310.getDailyRewardPool(1);
        assertTrue(pool.hasDistributed);
    }

    function testDistributeRewards_DayNotFinished() public {
        // Try to distribute current day
        vm.startPrank(owner);
        vm.expectRevert(Play3310V1.DayNotFinished.selector);
        play3310.distributeRewards(1);
        vm.stopPrank();
    }

    function testDistributeRewards_AlreadyDistributed() public {
        // Fund contract
        vm.startPrank(owner);
        cUSD.approve(address(play3310), 100 ether);
        play3310.fundRewardPool(100 ether);
        vm.stopPrank();

        // Submit score in day 1
        bytes memory sig = signScore(player1, 1, 1000, 500, 1, 0);
        vm.startPrank(player1);
        play3310.submitScore(1, 1000, 500, 1, 0, sig);
        vm.stopPrank();

        // Move to day 2 and distribute
        vm.warp(genesisTimestamp + 1 days);
        vm.startPrank(owner);
        play3310.distributeRewards(1);

        // Try to distribute again
        vm.expectRevert(Play3310V1.AlreadyDistributed.selector);
        play3310.distributeRewards(1);
        vm.stopPrank();
    }

    function testDistributeRewards_NoWinners() public {
        // Move to day 2 without any submissions
        vm.warp(genesisTimestamp + 1 days);

        vm.startPrank(owner);
        vm.expectRevert(Play3310V1.NoWinnersThisDay.selector);
        play3310.distributeRewards(1);
        vm.stopPrank();
    }

    function testDistributeRewards_OnlyOwner() public {
        vm.warp(genesisTimestamp + 1 days);

        vm.startPrank(player1);
        vm.expectRevert();
        play3310.distributeRewards(1);
        vm.stopPrank();
    }

    function testDistributeRewards_InsufficientFunds() public {
        // Submit score but don't fund contract
        bytes memory sig = signScore(player1, 1, 1000, 500, 1, 0);
        vm.startPrank(player1);
        play3310.submitScore(1, 1000, 500, 1, 0, sig);
        vm.stopPrank();

        // Move to day 2 and try to distribute
        vm.warp(genesisTimestamp + 1 days);

        vm.startPrank(owner);
        vm.expectRevert(Play3310V1.InsufficientContractBalance.selector);
        play3310.distributeRewards(1);
        vm.stopPrank();
    }

    // ==================== CLAIM REWARDS TESTS ====================
    function testClaimRewards() public {
        // Fund contract and submit scores
        vm.startPrank(owner);
        cUSD.approve(address(play3310), 100 ether);
        play3310.fundRewardPool(100 ether);
        vm.stopPrank();

        bytes memory sig = signScore(player1, 1, 1000, 500, 1, 0);
        vm.startPrank(player1);
        play3310.submitScore(1, 1000, 500, 1, 0, sig);
        vm.stopPrank();

        // Distribute rewards
        vm.warp(genesisTimestamp + 1 days);
        vm.startPrank(owner);
        play3310.distributeRewards(1);
        vm.stopPrank();

        // Claim rewards
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;

        uint256 balanceBefore = cUSD.balanceOf(player1);
        vm.startPrank(player1);
        play3310.claimRewards(indices);
        vm.stopPrank();
        uint256 balanceAfter = cUSD.balanceOf(player1);

        assertTrue(balanceAfter > balanceBefore);
    }

    function testClaimRewards_NoUnclaimedRewards() public {
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;

        vm.startPrank(player1);
        vm.expectRevert(Play3310V1.NoUnclaimedRewards.selector);
        play3310.claimRewards(indices);
        vm.stopPrank();
    }

    function testClaimRewards_InvalidIndex() public {
        // Fund contract and submit scores
        vm.startPrank(owner);
        cUSD.approve(address(play3310), 100 ether);
        play3310.fundRewardPool(100 ether);
        vm.stopPrank();

        bytes memory sig = signScore(player1, 1, 1000, 500, 1, 0);
        vm.startPrank(player1);
        play3310.submitScore(1, 1000, 500, 1, 0, sig);
        vm.stopPrank();

        // Distribute rewards
        vm.warp(genesisTimestamp + 1 days);
        vm.startPrank(owner);
        play3310.distributeRewards(1);
        vm.stopPrank();

        // Try to claim with invalid index
        uint256[] memory indices = new uint256[](1);
        indices[0] = 999; // Invalid index

        vm.startPrank(player1);
        vm.expectRevert(Play3310V1.InvalidRewardIndex.selector);
        play3310.claimRewards(indices);
        vm.stopPrank();
    }

    function testClaimRewards_AlreadyClaimed() public {
        // Fund contract and submit scores
        vm.startPrank(owner);
        cUSD.approve(address(play3310), 100 ether);
        play3310.fundRewardPool(100 ether);
        vm.stopPrank();

        bytes memory sig = signScore(player1, 1, 1000, 500, 1, 0);
        vm.startPrank(player1);
        play3310.submitScore(1, 1000, 500, 1, 0, sig);
        vm.stopPrank();

        // Distribute rewards
        vm.warp(genesisTimestamp + 1 days);
        vm.startPrank(owner);
        play3310.distributeRewards(1);
        vm.stopPrank();

        // Claim rewards
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;

        vm.startPrank(player1);
        play3310.claimRewards(indices);

        // Try to claim again
        vm.expectRevert(Play3310V1.RewardAlreadyClaimed.selector);
        play3310.claimRewards(indices);
        vm.stopPrank();
    }

    // ==================== VIEW FUNCTION TESTS ====================
    function testGetDailyLeaderboard() public {
        // Submit some scores
        for (uint256 i = 0; i < 3; i++) {
            address player = address(uint160(100 + i));
            uint256 score = 1000 + (i * 100);
            bytes memory signature = signScore(player, 1, score, score, 1, 0);

            vm.startPrank(player);
            play3310.submitScore(1, score, score, 1, 0, signature);
            vm.stopPrank();
        }

        Play3310V1.PlayerDailyScore[] memory leaderboard = play3310
            .getDailyLeaderboard(1);
        assertEq(leaderboard.length, 3);
    }

    function testGetDailyLeaderboard_Empty() public view {
        Play3310V1.PlayerDailyScore[] memory leaderboard = play3310
            .getDailyLeaderboard(1);
        assertEq(leaderboard.length, 0);
    }

    function testGetDailyRewardPool() public view {
        Play3310V1.DailyRewardPool memory pool = play3310.getDailyRewardPool(1);
        assertEq(pool.basePool, 5 ether);
        assertEq(pool.rolloverAmount, 0);
        assertEq(pool.totalPool, 5 ether);
        assertFalse(pool.hasDistributed);
    }

    function testGetUnclaimedRewards() public view {
        Play3310V1.UnclaimedReward[] memory rewards = play3310
            .getUnclaimedRewards(player1);
        assertEq(rewards.length, 0);
    }

    function testGetTotalUnclaimedAmount() public view {
        uint256 total = play3310.getTotalUnclaimedAmount(player1);
        assertEq(total, 0);
    }

    // ==================== UPGRADE TESTS ====================
    function testUpgrade() public {
        // Deploy new implementation
        vm.startPrank(owner);
        Play3310V1 newImplementation = new Play3310V1();

        play3310.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();
    }

    function testUpgrade_OnlyOwner() public {
        Play3310V1 newImplementation = new Play3310V1();

        vm.startPrank(player1);
        vm.expectRevert();
        play3310.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();
    }

    // ==================== EDGE CASE TESTS ====================
    function testGetDailyLeaderboard_InvalidDay_Zero() public {
        vm.expectRevert(Play3310V1.InvalidDay.selector);
        play3310.getDailyLeaderboard(0);
    }

    function testGetDailyLeaderboard_InvalidDay_Future() public {
        vm.expectRevert(Play3310V1.InvalidDay.selector);
        play3310.getDailyLeaderboard(999);
    }

    function testGetDailyRewardPool_WithRollover() public {
        // Fund contract
        vm.startPrank(owner);
        cUSD.approve(address(play3310), 100 ether);
        play3310.fundRewardPool(100 ether);
        vm.stopPrank();

        // Submit scores in day 1 (only 3 players, so there will be rollover)
        for (uint256 i = 0; i < 3; i++) {
            address player = address(uint160(100 + i));
            uint256 score = 1000 + (i * 100);
            bytes memory signature = signScore(player, 1, score, score, 1, 0);

            vm.startPrank(player);
            play3310.submitScore(1, score, score, 1, 0, signature);
            vm.stopPrank();
        }

        // Move to day 2 and distribute day 1 rewards
        vm.warp(genesisTimestamp + 1 days);
        vm.startPrank(owner);
        play3310.distributeRewards(1);
        vm.stopPrank();

        // Check day 2 reward pool - should include rollover from day 1
        Play3310V1.DailyRewardPool memory pool = play3310.getDailyRewardPool(2);
        assertEq(pool.basePool, 5 ether);
        assertTrue(pool.rolloverAmount > 0); // Should have rollover from week 1
        assertEq(pool.totalPool, pool.basePool + pool.rolloverAmount);
    }

    function testVersion() public view {
        string memory ver = play3310.version();
        assertEq(ver, "1.0.0");
    }

    function testSubmitScore_WrongSigner() public {
        uint256 dayId = 1;
        uint256 score = 1000;
        uint256 gameScore = 500;
        uint256 gameCount = 2;
        uint256 referralPoints = 100;

        // Sign with a different private key
        uint256 wrongKey = 0xBAD;
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                player1,
                dayId,
                score,
                gameScore,
                gameCount,
                referralPoints
            )
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            wrongKey,
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.startPrank(player1);
        vm.expectRevert(Play3310V1.InvalidSignature.selector);
        play3310.submitScore(
            dayId,
            score,
            gameScore,
            gameCount,
            referralPoints,
            signature
        );
        vm.stopPrank();
    }

    function testSubmitScore_UpdateMiddleEntry() public {
        uint256 dayId = 1;

        // Submit 3 scores to create a leaderboard
        for (uint256 i = 0; i < 3; i++) {
            address player = address(uint160(100 + i));
            uint256 score = 1000 + (i * 100);
            bytes memory signature = signScore(
                player,
                dayId,
                score,
                score,
                1,
                0
            );

            vm.startPrank(player);
            play3310.submitScore(dayId, score, score, 1, 0, signature);
            vm.stopPrank();
        }

        // Update the middle entry (player at index 1)
        address middlePlayer = address(uint160(101));
        bytes memory newSig = signScore(middlePlayer, dayId, 1500, 1500, 1, 0);
        vm.startPrank(middlePlayer);
        play3310.submitScore(dayId, 1500, 1500, 1, 0, newSig);
        vm.stopPrank();

        // Verify the leaderboard is correctly updated
        Play3310V1.PlayerDailyScore[] memory leaderboard = play3310
            .getDailyLeaderboard(dayId);
        assertEq(leaderboard.length, 3);
        assertEq(leaderboard[0].player, middlePlayer); // Should now be first
        assertEq(leaderboard[0].score, 1500);
    }
}
