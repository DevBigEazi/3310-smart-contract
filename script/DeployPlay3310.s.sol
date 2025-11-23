// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Play3310V1.sol";
import "../src/Play3310Proxy.sol";

/**
 * @title DeployPlay3310
 * @dev Deployment script for Play3310 on Celo
 * @notice Deploy with: forge script script/DeployPlay3310.s.sol --rpc-url <RPC_URL> --account <ACCOUNT> --broadcast
 */
contract DeployPlay3310 is Script {
    // ==================== HELPER FUNCTIONS ====================
    /**
     * @dev Calculate the most recent Monday 00:00 UTC
     * @return Monday's timestamp at 00:00 UTC
     */
    function getMondayTimestamp(uint256 _now) internal pure returns (uint256) {
        // Days since Unix epoch (Jan 1, 1970 was Thursday)
        // 0 = Thursday, 1 = Friday, 2 = Saturday, 3 = Sunday, 4 = Monday
        uint256 daysSinceEpoch = _now / 86400;

        // Calculate current day of week (0 = Thursday)
        uint256 dayOfWeek = (daysSinceEpoch + 4) % 7;

        // Days to subtract to reach last Monday
        uint256 daysToMonday;
        if (dayOfWeek == 4) {
            // Today is Monday
            daysToMonday = 0;
        } else if (dayOfWeek < 4) {
            // Monday hasn't happened yet this week
            daysToMonday = dayOfWeek + 3;  // Go back to last Monday
        } else {
            // Monday already passed this week
            daysToMonday = dayOfWeek - 4;
        }

        // Get timestamp of the Monday and adjust to 00:00 UTC
        uint256 mondayTimestamp = _now - (daysToMonday * 86400);
        // Remove time-of-day to get 00:00 UTC
        mondayTimestamp = (mondayTimestamp / 86400) * 86400;

        return mondayTimestamp;
    }

    function run() public {
        // ==================== ENVIRONMENT VARIABLES ====================
        address backendSigner = vm.envAddress("BACKEND_SIGNER_ADDRESS");
        address cUSD = vm.envAddress("CUSD_ADDRESS");
        address owner = vm.envOr("OWNER_ADDRESS", msg.sender);

        // Validate required addresses
        require(backendSigner != address(0), "BACKEND_SIGNER_ADDRESS not set");
        require(cUSD != address(0), "CUSD_ADDRESS not set");

        // Calculate genesis timestamp (most recent Monday 00:00 UTC)
        uint256 genesisTimestamp = getMondayTimestamp(block.timestamp);

        // ==================== DEPLOYMENT ====================
        console.log("\n=== Starting Play3310 Deployment ===");
        console.log("Backend Signer: %s", backendSigner);
        console.log("cUSD Address: %s", cUSD);
        console.log("Owner Address: %s", owner);
        console.log("Genesis Timestamp (Monday 00:00 UTC): %d", genesisTimestamp);

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy implementation
        Play3310V1 implementation = new Play3310V1();
        console.log("\n Implementation deployed at: %s", address(implementation));

        // Deploy proxy with initialization
        Play3310Proxy proxy = new Play3310Proxy(
            address(implementation),
            cUSD,
            backendSigner,
            owner,
            genesisTimestamp
        );
        console.log("Proxy deployed at: %s", address(proxy));

        vm.stopBroadcast();

        // ==================== VERIFICATION ====================
        console.log("\n=== Verifying Deployment ===");

        // Cast proxy to interface for verification
        Play3310V1 game = Play3310V1(address(proxy));

        // Check initialization
        uint256 weeklyPool = game.weeklyBasePool();
        uint256 minScore = game.minQualificationScore();
        address signerCheck = game.backendSigner();
        uint256 currentWeek = game.getCurrentWeek();

        console.log("\nContract State:");
        console.log("  Weekly Base Pool: %d wei (%.2f cUSD)", weeklyPool, uint256(weeklyPool) / 1e18);
        console.log("  Min Qualification Score: %d", minScore);
        console.log("  Backend Signer: %s", signerCheck);
        console.log("  Current Week: %d", currentWeek);

        // Verify signer matches
        require(signerCheck == backendSigner, "Signer mismatch!");

        console.log("\n=== Deployment Complete ===");
        console.log("Proxy Address: %s", address(proxy));
        console.log("Implementation Address: %s", address(implementation));
        console.log("Owner: %s", owner);
        console.log("Genesis Timestamp: %d", genesisTimestamp);

        // ==================== NEXT STEPS ====================
        console.log("\n=== Next Steps ===");
        console.log("1. Fund the contract with cUSD:");
        console.log("   cUSD.transfer(proxyAddress, amount)");
        console.log("2. Verify on block explorer");
        console.log("3. Update frontend with proxy address");
    }
}