// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
    address public backendSigner = address(2);
    address public player1 = address(3);
    address public player2 = address(4);

    uint256 public genesisTimestamp;

    function setUp() public {
        vm.startPrank(owner);

        // Set genesis to a Monday (e.g., 2025-11-17 00:00:00 UTC)
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

    function testTop10LeaderboardLogic() public {
        // Setup backend signer key
        uint256 backendPrivateKey = 0xA11CE;
        address backendSignerAddr = vm.addr(backendPrivateKey);
        
        vm.startPrank(owner);
        Play3310V1 impl = new Play3310V1();
        Play3310Proxy p = new Play3310Proxy(
            address(impl),
            address(cUSD),
            backendSignerAddr,
            owner,
            genesisTimestamp
        );
        Play3310V1 game = Play3310V1(address(p));
        vm.stopPrank();

        // Warp to Saturday Week 1
        vm.warp(genesisTimestamp + 5 days + 1 hours);
        uint256 weekId = 1;

        // Player A: 50 pts, 5 games, 10 ref (Rank 1)
        address playerA = address(10);
        {
            bytes memory sigA = _getSignature(backendPrivateKey, playerA, weekId, 50, 20, 5, 10);
            vm.prank(playerA);
            game.submitScore(weekId, 50, 20, 5, 10, sigA);
        }

        // Player B: 40 pts, 3 games, 5 ref (Rank 2)
        address playerB = address(11);
        {
            bytes memory sigB = _getSignature(backendPrivateKey, playerB, weekId, 40, 20, 3, 5);
            vm.prank(playerB);
            game.submitScore(weekId, 40, 20, 3, 5, sigB);
        }

        // Player C: 40 pts, 7 games, 8 ref (Rank 3)
        address playerC = address(12);
        {
            bytes memory sigC = _getSignature(backendPrivateKey, playerC, weekId, 40, 20, 7, 8);
            vm.prank(playerC);
            game.submitScore(weekId, 40, 20, 7, 8, sigC);
        }

        // Player D: 30 pts, 2 games, 3 ref (Rank 4)
        address playerD = address(13);
        {
            bytes memory sigD = _getSignature(backendPrivateKey, playerD, weekId, 30, 20, 2, 3);
            vm.prank(playerD);
            game.submitScore(weekId, 30, 20, 2, 3, sigD);
        }

        // Verify Leaderboard
        Play3310V1.PlayerWeeklyScore[] memory lb = game.getWeeklyLeaderboard(weekId);
        assertEq(lb.length, 4);
        
        // Rank 1: Player A (Highest Score)
        assertEq(lb[0].player, playerA);
        assertEq(lb[0].rank, 1);

        // Rank 2: Player B (40 pts, 3 games vs 7 games)
        assertEq(lb[1].player, playerB);
        assertEq(lb[1].rank, 2);

        // Rank 3: Player C (40 pts, 7 games)
        assertEq(lb[2].player, playerC);
        assertEq(lb[2].rank, 3);

        // Rank 4: Player D (Lowest Score)
        assertEq(lb[3].player, playerD);
        assertEq(lb[3].rank, 4);

        // Update Player D to beat Player A (New Score: 60)
        {
            bytes memory sigD2 = _getSignature(backendPrivateKey, playerD, weekId, 60, 30, 3, 3);
            vm.prank(playerD);
            game.submitScore(weekId, 60, 30, 3, 3, sigD2);
        }

        lb = game.getWeeklyLeaderboard(weekId);
        assertEq(lb[0].player, playerD); // New Rank 1
        assertEq(lb[1].player, playerA); // New Rank 2
    }

    function testSetMinQualificationScore() public {
        vm.startPrank(owner);
        assertEq(play3310.minQualificationScore(), 500);
        
        play3310.setMinQualificationScore(600);
        assertEq(play3310.minQualificationScore(), 600);
        vm.stopPrank();
    }

    function testSubmitScoreWithSignature() public {
        // Setup backend signer key
        uint256 backendPrivateKey = 0xA11CE;
        address backendSignerAddr = vm.addr(backendPrivateKey);
        
        // Re-deploy with known signer
        vm.startPrank(owner);
        Play3310V1 impl = new Play3310V1();
        Play3310Proxy p = new Play3310Proxy(
            address(impl),
            address(cUSD),
            backendSignerAddr,
            owner,
            genesisTimestamp
        );
        Play3310V1 game = Play3310V1(address(p));
        vm.stopPrank();

        // Warp to Saturday of Week 1
        // Genesis is Monday. Saturday is +5 days.
        vm.warp(genesisTimestamp + 5 days + 1 hours); 
        
        // Prepare score data
        uint256 weekId = 1;
        uint256 score = 100;
        uint256 gameScore = 50;
        uint256 gameCount = 2;
        uint256 referralPoints = 10;

        // First Submission
        bytes memory signature = _getSignature(backendPrivateKey, player1, weekId, score, gameScore, gameCount, referralPoints);

        vm.startPrank(player1);
        game.submitScore(weekId, score, gameScore, gameCount, referralPoints, signature);
        vm.stopPrank();

        // Verify updates
        (uint256 hgs, uint256 hws, uint256 gp, uint256 rp, uint256 tls) = game.playerAllTimeStats(player1);
        assertEq(hgs, 50, "Highest Game Score");
        assertEq(hws, 100, "Highest Weekly Score");
        assertEq(gp, 2, "Total Games Played");
        assertEq(rp, 10, "Total Referral Points");
        assertEq(tls, 100, "Total Lifetime Score");
    }

    function testSubmitScoreWithSignature_Update() public {
        // Setup backend signer key
        uint256 backendPrivateKey = 0xA11CE;
        address backendSignerAddr = vm.addr(backendPrivateKey);
        
        // Re-deploy with known signer
        vm.startPrank(owner);
        Play3310V1 impl = new Play3310V1();
        Play3310Proxy p = new Play3310Proxy(
            address(impl),
            address(cUSD),
            backendSignerAddr,
            owner,
            genesisTimestamp
        );
        Play3310V1 game = Play3310V1(address(p));
        vm.stopPrank();

        // Warp to Sunday of Week 1
        vm.warp(genesisTimestamp + 6 days + 23 hours);

        // Prepare score data
        uint256 weekId = 1;
        uint256 score = 100;
        uint256 gameScore = 50;
        uint256 gameCount = 2;
        uint256 referralPoints = 10;

        // First Submission
        bytes memory signature = _getSignature(backendPrivateKey, player1, weekId, score, gameScore, gameCount, referralPoints);

        vm.startPrank(player1);
        game.submitScore(weekId, score, gameScore, gameCount, referralPoints, signature);
        vm.stopPrank();

        // Second Submission (Update)
        score = 150; // +50
        gameScore = 60; // New high
        gameCount = 3; // +1
        referralPoints = 15; // +5

        signature = _getSignature(backendPrivateKey, player1, weekId, score, gameScore, gameCount, referralPoints);

        vm.startPrank(player1);
        game.submitScore(weekId, score, gameScore, gameCount, referralPoints, signature);
        vm.stopPrank();

        // Verify updates (deltas)
        (uint256 hgs, uint256 hws, uint256 gp, uint256 rp, uint256 tls) = game.playerAllTimeStats(player1);
        assertEq(hgs, 60, "Highest Game Score updated");
        assertEq(hws, 150, "Highest Weekly Score updated");
        assertEq(gp, 3, "Total Games Played updated");
        assertEq(rp, 15, "Total Referral Points updated");
        assertEq(tls, 150, "Total Lifetime Score updated (100 + 50)");
    }

    function testRewardDistribution() public {
        // Setup backend signer key
        uint256 backendPrivateKey = 0xA11CE;
        address backendSignerAddr = vm.addr(backendPrivateKey);
        
        vm.startPrank(owner);
        Play3310V1 impl = new Play3310V1();
        Play3310Proxy p = new Play3310Proxy(
            address(impl),
            address(cUSD),
            backendSignerAddr,
            owner,
            genesisTimestamp
        );
        Play3310V1 game = Play3310V1(address(p));
        
        // Fund the contract
        cUSD.approve(address(game), 1000 ether);
        game.fundPrizePool(100 ether);
        vm.stopPrank();

        // Warp to Saturday Week 1
        vm.warp(genesisTimestamp + 5 days + 1 hours);
        uint256 weekId = 1;

        // Player A: 600 pts (Qualified)
        address playerA = address(10);
        {
            bytes memory sigA = _getSignature(backendPrivateKey, playerA, weekId, 600, 20, 5, 10);
            vm.prank(playerA);
            game.submitScore(weekId, 600, 20, 5, 10, sigA);
        }

        // Player B: 400 pts (Not Qualified)
        address playerB = address(11);
        {
            bytes memory sigB = _getSignature(backendPrivateKey, playerB, weekId, 400, 20, 3, 5);
            vm.prank(playerB);
            game.submitScore(weekId, 400, 20, 3, 5, sigB);
        }

        // Warp to Week 2 (Monday)
        vm.warp(genesisTimestamp + 7 days + 1 hours);

        // Distribute Rewards
        uint256 initialBalanceA = cUSD.balanceOf(playerA);
        uint256 initialBalanceB = cUSD.balanceOf(playerB);
        
        vm.prank(owner);
        game.distributeRewards(weekId);

        // Verify Payouts
        // Total Pool: 5 cUSD (Base)
        // Rank 1 (Player A): 30% of 5 = 1.5 cUSD
        assertEq(cUSD.balanceOf(playerA) - initialBalanceA, 1.5 ether);
        
        // Rank 2 (Player B): Not qualified (< 500), so no payout.
        assertEq(cUSD.balanceOf(playerB) - initialBalanceB, 0);

        // Verify Rollover
        // Player A took 30%.
        // Player B (Rank 2) was disqualified.
        // Ranks 3-10 were empty.
        // Rollover = 70% of 5 = 3.5 cUSD
        // Wait, Player B is in the Top 10 list but disqualified by score check in distributeRewards?
        // Let's check logic:
        // distributeRewards iterates winners (Top 10).
        // Player A (Rank 1) -> Qualified -> Paid.
        // Player B (Rank 2) -> Not Qualified -> Rollover += Reward(Rank 2).
        // Ranks 3-10 -> Empty -> Rollover += Reward(Rank 3..10).
        
        // Rank 2 (20%) + Rank 3 (15%) + ... + Rank 10 (3.4%) = 70%
        // 70% of 5 = 3.5
        assertEq(game.unclaimedRollover(), 3.5 ether);
        assertEq(game.currentWeekPrizePool(), 5 ether + 3.5 ether);
    }

    function testSubmissionWindow() public {
        // Setup backend signer key
        uint256 backendPrivateKey = 0xA11CE;
        address backendSignerAddr = vm.addr(backendPrivateKey);
        
        vm.startPrank(owner);
        Play3310V1 impl = new Play3310V1();
        Play3310Proxy p = new Play3310Proxy(
            address(impl),
            address(cUSD),
            backendSignerAddr,
            owner,
            genesisTimestamp
        );
        Play3310V1 game = Play3310V1(address(p));
        vm.stopPrank();

        uint256 weekId = 1;
        
        // 1. Try submitting on Friday (Day 4) - Should Fail
        vm.warp(genesisTimestamp + 4 days);
        bytes memory signature = _getSignature(backendPrivateKey, player1, weekId, 100, 50, 2, 10);
        
        vm.startPrank(player1);
        vm.expectRevert(Play3310V1.NotSubmissionPeriod.selector);
        game.submitScore(weekId, 100, 50, 2, 10, signature);
        vm.stopPrank();

        // 2. Try submitting on Saturday (Day 5) - Should Succeed
        vm.warp(genesisTimestamp + 5 days);
        vm.startPrank(player1);
        game.submitScore(weekId, 100, 50, 2, 10, signature);
        vm.stopPrank();

        // 3. Try submitting for Week 2 during Week 1 - Should Fail
        // Still on Saturday Week 1
        bytes memory sigWeek2 = _getSignature(backendPrivateKey, player1, 2, 100, 50, 2, 10);
        vm.startPrank(player1);
        vm.expectRevert(Play3310V1.InvalidWeek.selector);
        game.submitScore(2, 100, 50, 2, 10, sigWeek2);
        vm.stopPrank();
    }

    function testPublicFunding() public {
        // Setup
        vm.startPrank(owner);
        Play3310V1 impl = new Play3310V1();
        Play3310Proxy p = new Play3310Proxy(
            address(impl),
            address(cUSD),
            backendSigner,
            owner,
            genesisTimestamp
        );
        Play3310V1 game = Play3310V1(address(p));
        vm.stopPrank();

        // Fund as a random user
        address randomUser = address(0x999);
        vm.deal(randomUser, 100 ether); // Not needed for ERC20 but good practice
        
        // Mint cUSD to random user
        MockCUSD(address(cUSD)).mint(randomUser, 50 ether);
        
        vm.startPrank(randomUser);
        cUSD.approve(address(game), 50 ether);
        game.fundPrizePool(50 ether);
        vm.stopPrank();

        assertEq(cUSD.balanceOf(address(game)), 50 ether);
    }

    function _getSignature(
        uint256 privateKey,
        address player,
        uint256 weekId,
        uint256 score,
        uint256 gameScore,
        uint256 gameCount,
        uint256 referralPoints
    ) internal pure returns (bytes memory) {
        bytes32 messageHash = keccak256(
            abi.encodePacked(player, weekId, score, gameScore, gameCount, referralPoints)
        );
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }
}
