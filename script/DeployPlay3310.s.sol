// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Play3310V1.sol";
import "../src/Play3310Proxy.sol";

/**
 * @title DeployPlay3310
 * @dev Deployment script for Play3310
 * @notice Uses msg.sender (from --account flag) instead of private key
 */
contract DeployPlay3310 is Script {

    function setUp() public {
    }

    function run() public {
        address backendSigner = vm.envAddress("BACKEND_SIGNER_ADDRESS");
        address cUSD = vm.envAddress("CUSD_ADDRESS");

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy implementation
        Play3310V1 implementation = new Play3310V1();
        console.log("Implementation deployed at: %s", address(implementation));

        // Deploy proxy with initialization
        Play3310Proxy proxy = new Play3310Proxy(
            address(implementation),
            cUSD,
            backendSigner,
            msg.sender
        );
        console.log("Proxy deployed at: %s", address(proxy));

        // Cast proxy to interface for interaction
        Play3310V1 game = Play3310V1(address(proxy));

        // Verify initialization
        console.log("Weekly prize pool: %s", game.weeklyPrizePool());
        console.log("Min qualification score: %d", game.minQualificationScore());

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
        console.log("Proxy Address: %s", address(proxy));
        console.log("Implementation Address: %s", address(implementation));
    }
}