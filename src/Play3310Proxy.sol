// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./Play3310V1.sol";

/**
 * @title Play3310Proxy
 * @dev ERC1967 Proxy for Play3310 (UUPS pattern)
 * @notice Manages upgradeable proxy for Play3310V1
 */
contract Play3310Proxy is ERC1967Proxy {
    /**
     * @dev Constructor for Play3310Proxy
     * @param _implementation Address of initial implementation (Play3310V1)
     * @param _cUSD Address of cUSD token
     * @param _backendSigner Address of backend signer
     * @param _initialOwner Address of initial owner
     * @param _genesisTimestamp Timestamp of first Monday 00:00 UTC
     */
    constructor(
        address _implementation,
        address _cUSD,
        address _backendSigner,
        address _initialOwner,
        uint256 _genesisTimestamp
    )
        ERC1967Proxy(
            _implementation,
            abi.encodeWithSelector(
                Play3310V1.initialize.selector,
                _cUSD,
                _backendSigner,
                _initialOwner,
                _genesisTimestamp
            )
        )
    {
        require(_implementation != address(0), "Invalid implementation");
        require(_cUSD != address(0), "Invalid cUSD");
        require(_backendSigner != address(0), "Invalid backend signer");
        require(_initialOwner != address(0), "Invalid owner");
        require(_genesisTimestamp > 0, "Invalid genesis timestamp");
    }
}

/**
 * @title Play3310Factory
 * @dev Factory contract for deploying Play3310 instances with proxy
 * @notice Manages deployment and initialization of Play3310 games
 */
contract Play3310Factory {
    // ==================== EVENTS ====================
    event Play3310Deployed(
        address indexed proxy,
        address indexed implementation,
        address indexed owner,
        uint256 genesisTimestamp
    );

    event ImplementationDeployed(address indexed implementation);

    // ==================== STATE ====================
    address public lastDeployedProxy;
    address[] public allDeployedProxies;
    mapping(address => address) public proxyToImplementation;

    // ==================== FUNCTIONS ====================
    /**
     * @dev Deploy new Play3310 instance with proxy
     * @param _cUSD Address of cUSD token
     * @param _backendSigner Address of backend signer
     * @param _initialOwner Address of contract owner
     * @param _genesisTimestamp Timestamp of first Monday 00:00 UTC
     * @return proxy Address of deployed proxy
     */
    function deployPlay3310(
        address _cUSD,
        address _backendSigner,
        address _initialOwner,
        uint256 _genesisTimestamp
    ) external returns (address proxy) {
        require(_cUSD != address(0), "Invalid cUSD address");
        require(_backendSigner != address(0), "Invalid backend signer");
        require(_initialOwner != address(0), "Invalid owner");
        require(_genesisTimestamp > 0, "Invalid genesis timestamp");

        // Deploy implementation
        Play3310V1 implementation = new Play3310V1();
        emit ImplementationDeployed(address(implementation));

        // Deploy proxy
        Play3310Proxy _proxy = new Play3310Proxy(
            address(implementation),
            _cUSD,
            _backendSigner,
            _initialOwner,
            _genesisTimestamp
        );

        proxy = address(_proxy);

        // Track deployment
        lastDeployedProxy = proxy;
        allDeployedProxies.push(proxy);
        proxyToImplementation[proxy] = address(implementation);

        emit Play3310Deployed(proxy, address(implementation), _initialOwner, _genesisTimestamp);

        return proxy;
    }

    /**
     * @dev Get all deployed proxies
     */
    function getAllDeployedProxies() external view returns (address[] memory) {
        return allDeployedProxies;
    }

    /**
     * @dev Get number of deployed instances
     */
    function getDeploymentCount() external view returns (uint256) {
        return allDeployedProxies.length;
    }

    /**
     * @dev Get implementation address for a proxy
     * @param _proxy Address of proxy
     */
    function getImplementation(address _proxy) external view returns (address) {
        require(_proxy != address(0), "Invalid proxy address");
        return proxyToImplementation[_proxy];
    }
}