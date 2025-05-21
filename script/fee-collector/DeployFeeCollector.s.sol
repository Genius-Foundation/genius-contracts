// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {BaseScriptContext} from "../utils/BaseScriptContext.sol";
import {console} from "forge-std/Script.sol";

/**
 * @title DeployFeeCollector
 * @dev Script to deploy FeeCollector implementation and proxy
 * Deployment command:
 * source .env && forge script script/deploy/DeployFeeCollector.sol --rpc-url $<NETWORK>_RPC_URL --broadcast -vvvv --via-ir
 * Optionally specify environment: DEPLOY_ENV=STAGING forge script...
 */
contract DeployFeeCollector is BaseScriptContext {
    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        // Get the stablecoin address for this network and environment
        address stablecoin = getStablecoinAddress();

        address protocolFeeReceiver = owner;
        address lpFeeReceiver = owner;
        address operatorFeeReceiver = owner;

        // Deploy FeeCollector implementation
        FeeCollector feeCollectorImpl = new FeeCollector();
        console.log(
            "FeeCollector implementation deployed at:",
            address(feeCollectorImpl)
        );

        // Prepare initialization data
        bytes memory feeCollectorInitData = abi.encodeWithSelector(
            FeeCollector.initialize.selector,
            owner, // admin address
            stablecoin, // stablecoin address
            1000, // 10% protocol fee
            protocolFeeReceiver,
            lpFeeReceiver,
            operatorFeeReceiver
        );

        // Deploy proxy
        ERC1967Proxy feeCollectorProxy = new ERC1967Proxy(
            address(feeCollectorImpl),
            feeCollectorInitData
        );
        console.log(
            "FeeCollector proxy deployed at:",
            address(feeCollectorProxy)
        );

        console.log("FeeCollector deployment complete");
        console.log(
            "IMPORTANT: Set FEE_COLLECTOR_%s_%s=%s in your .env file",
            network,
            deployEnv,
            address(feeCollectorProxy)
        );

        vm.stopBroadcast();
    }
}
