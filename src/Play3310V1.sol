// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// ==================== CUSTOM ERRORS ====================
error InvalidSignature();
error TransferFailed();
error InvalidDistribution();

/**
 * @title Play3310
 * @dev Upgradeable gaming reward distribution contract with UUPS pattern
 */
contract Play3310V1 is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard {
    // ==================== VERSION ====================
    uint256 public constant VERSION = 1;

    // ==================== STATE ====================
    IERC20 public cUSD;
    address public backendSigner;

    uint256 public weeklyPrizePool;
    uint256 public minQualificationScore;
    uint256 public currentWeekPrizePool;
    uint256 public unclaimedRollover;

    uint256[] public prizeDistribution;
  
    event ContractUpgraded(address indexed newImplementation, uint256 version);

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
     */
    function initialize(
        address _cUSD,
        address _backendSigner,
        address _initialOwner
    ) public initializer {
        __Ownable_init(_initialOwner);

        cUSD = IERC20(_cUSD);
        backendSigner = _backendSigner;
        weeklyPrizePool = 5 ether;
        minQualificationScore = 500;
        currentWeekPrizePool = weeklyPrizePool;
        unclaimedRollover = 0;

        // Initialize prize distribution
        prizeDistribution = [3000, 2000, 1500, 1000, 800, 340, 340, 340, 340, 340];
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