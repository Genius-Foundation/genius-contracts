// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import { GeniusSwapRouter } from "../../src/GeniusSwapRouter.sol";

/**
 Need:
 1. ethereum
 2. sonic
 3. hyper

 * @title DeployGeniusSwapRouter
 * @notice Script to deploy the GeniusSwapRouter contract
 *
 * @dev example: forge script script/deployment/DeployGeniusSwapRouter.s.sol \               
  --rpc-url <url> \
  --private-key $SWAPROUTER_DEPLOYER_PRIVATE_KEY \
  --broadcast
 */
contract DeployGeniusSwapRouter is Script {
    function run() public {
        address feeCollector = vm.envAddress("SWAPROUTER_FEE_COLLECTOR_ADDRESS");
        address swapRouterAdmin = vm.envAddress("SWAPROUTER_ADMIN_ADDRESS");
        vm.startBroadcast();
        GeniusSwapRouter router = new GeniusSwapRouter(swapRouterAdmin, feeCollector);
        vm.stopBroadcast();
        console.log("GeniusSwapRouter deployed at:", address(router));
    }
}