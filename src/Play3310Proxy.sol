// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./Play3310V1.sol";

/**
 * @title Play3310Proxy
 * @dev ERC1967 Proxy for Play3310 (UUPS pattern)
 * @notice Ownership and upgrades are managed by the implementation (Play3310V1)
 */
contract Play3310Proxy is ERC1967Proxy {
    constructor(
        address _implementation,
        address _cUSD,
        address _backendSigner,
        address _initialOwner
    )
        ERC1967Proxy(
            _implementation,
            abi.encodeWithSelector(
                Play3310V1.initialize.selector,
                _cUSD,
                _backendSigner,
                _initialOwner
            )
        )
    {}
}

/**
 * @title Play3310Factory
 * @dev Factory for deploying Play3310 with proxy
 */
contract Play3310Factory {
    event Play3310Deployed(
        address indexed proxy,
        address indexed implementation,
        address indexed owner
    );

    /**
     * @dev Deploy new Play3310 instance with proxy
     * @param _cUSD Address of cUSD token
     * @param _backendSigner Address of backend signer
     * @param _initialOwner Address of contract owner
     * @return proxy Address of the deployed proxy
     */
    function deployPlay3310(
        address _cUSD,
        address _backendSigner,
        address _initialOwner
    ) external returns (Play3310V1 proxy) {
        // Deploy implementation
        Play3310V1 implementation = new Play3310V1();

        // Deploy proxy pointing to the implementation
        Play3310Proxy _proxy = new Play3310Proxy(
            address(implementation),
            _cUSD,
            _backendSigner,
            _initialOwner
        );

        // Return proxy as Play3310V1 interface
        proxy = Play3310V1(address(_proxy));

        emit Play3310Deployed(address(_proxy), address(implementation), _initialOwner);
        return proxy;
    }
}