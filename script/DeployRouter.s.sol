// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {GeniusRouter} from "../../src/GeniusRouter.sol";
import {GeniusProxyCall} from "../../src/GeniusProxyCall.sol";
import {BaseScriptContext} from "./utils/BaseScriptContext.sol";
import {console} from "forge-std/Script.sol";

/**
 * @title DeployRouter
 * @dev Script to deploy GeniusRouter and configure permissions
 * Deployment command:
 * source .env && forge script script/deploy/DeployRouter.sol --rpc-url $<NETWORK>_RPC_URL --broadcast -vvvv --via-ir
 * Optionally specify environment: DEPLOY_ENV=STAGING forge script...
 */
contract DeployRouter is BaseScriptContext {
    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        // Get addresses for this network and environment
        address vaultAddress = getVaultAddress();
        address proxyCallAddress = getProxyCallAddress();
        address feeCollectorlAddress = getFeeCollectorAddress();

        // Deploy GeniusRouter implementation
        GeniusRouter geniusRouterImpl = new GeniusRouter();
        console.log("GeniusRouter implementation deployed at:", address(geniusRouterImpl));

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            GeniusRouter.initialize.selector,
            vm.envAddress("PERMIT2_ADDRESS"), // Permit2 (same on all chains)
            vaultAddress,
            proxyCallAddress,
            feeCollectorlAddress,
            owner // admin
        );

        // Deploy proxy
        ERC1967Proxy routerProxy = new ERC1967Proxy(
            address(geniusRouterImpl),
            initData
        );
        console.log("GeniusRouter proxy deployed at:", address(routerProxy));

        // Grant CALLER_ROLE to the router on ProxyCall contract
        GeniusProxyCall geniusProxyCall = GeniusProxyCall(
            payable(proxyCallAddress)
        );

        bytes32 CALLER_ROLE = keccak256("CALLER_ROLE");
        geniusProxyCall.grantRole(CALLER_ROLE, address(routerProxy));
        console.log("Granted CALLER_ROLE to GeniusRouter on ProxyCall");

        console.log("Router deployment complete");
        console.log(
            "IMPORTANT: Set ROUTER_%s_%s=%s in your .env file",
            network,
            deployEnv,
            address(routerProxy)
        );

        vm.stopBroadcast();
    }
} 
