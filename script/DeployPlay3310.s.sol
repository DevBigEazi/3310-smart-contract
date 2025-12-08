// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

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
     * @dev Calculate the start of the current day 00:00 UTC
     * @return Day's timestamp at 00:00 UTC
     */
    function getDayStartTimestamp(
        uint256 _now
    ) internal pure returns (uint256) {
        // Remove time-of-day to get 00:00 UTC
        return (_now / 86400) * 86400;
    }

    function run() public {
        // ==================== ENVIRONMENT VARIABLES ====================
        address backendSigner = vm.envAddress("BACKEND_SIGNER_ADDRESS");
        address cUSD = vm.envAddress("CUSD_ADDRESS");

        // Validate required addresses
        require(backendSigner != address(0), "BACKEND_SIGNER_ADDRESS not set");
        require(cUSD != address(0), "CUSD_ADDRESS not set");

        // Calculate genesis timestamp (start of current day 00:00 UTC)
        uint256 genesisTimestamp = getDayStartTimestamp(block.timestamp);

        // ==================== DEPLOYMENT ====================
        console.log("\n=== Starting Play3310 Deployment ===");
        console.log("Backend Signer: %s", backendSigner);
        console.log("cUSD Address: %s", cUSD);
        console.log("Owner Address: %s", msg.sender);
        console.log(
            "Genesis Timestamp (Day Start 00:00 UTC): %d",
            genesisTimestamp
        );

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy implementation
        Play3310V1 implementation = new Play3310V1();
        console.log(
            "\n Implementation deployed at: %s",
            address(implementation)
        );

        // Deploy proxy with initialization
        Play3310Proxy proxy = new Play3310Proxy(
            address(implementation),
            cUSD,
            backendSigner,
            msg.sender,
            genesisTimestamp
        );
        console.log("Proxy deployed at: %s", address(proxy));

        vm.stopBroadcast();

        // ==================== VERIFICATION ====================
        console.log("\n=== Verifying Deployment ===");

        // Cast proxy to interface for verification
        Play3310V1 game = Play3310V1(address(proxy));

        // Check initialization
        uint256 dailyPool = game.dailyBasePool();
        uint256 minScore = game.minQualificationScore();
        address signerCheck = game.backendSigner();
        uint256 currentDay = game.getCurrentDay();

        console.log("\nContract State:");
        console.log(
            "  Daily Base Pool: %d wei (%.2f cUSD)",
            dailyPool,
            uint256(dailyPool) / 1e18
        );
        console.log("  Min Qualification Score: %d", minScore);
        console.log("  Backend Signer: %s", signerCheck);
        console.log("  Current Day: %d", currentDay);

        // Verify signer matches
        require(signerCheck == backendSigner, "Signer mismatch!");

        console.log("\n=== Deployment Complete ===");
        console.log("Proxy Address: %s", address(proxy));
        console.log("Implementation Address: %s", address(implementation));
        console.log("Owner: %s", msg.sender);
        console.log("Genesis Timestamp: %d", genesisTimestamp);

        // ==================== NEXT STEPS ====================
        console.log("\n=== Next Steps ===");
        console.log("1. Fund the contract with cUSD:");
        console.log(" cUSD.safeTransfer(proxyAddress, amount)");
        console.log("2. Verify on block explorer");
        console.log("3. Update frontend with proxy address");
    }
}
