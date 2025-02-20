// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GeniusGenericBundler} from "../src/GeniusGenericBundler.sol";

/**
 * @title DeployGeniusGenericBundler
 * @dev A contract for deploying the GeniusGenericBundler contract.
 *      Deployment commands:
 *      `source .env` // Load environment variables
 *      POLYGON: source .env; forge script script/DeployGeniusGenericBundler.s.sol:DeployGeniusGenericBundler --rpc-url $AVALANCHE_RPC_URL --broadcast -vvvv --via-ir
 */
contract DeployGeniusGenericBundler is Script {
    GeniusGenericBundler public geniusGenericBundler;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = 0x5CC11Ef1DE86c5E00259a463Ac3F3AE1A0fA2909;


        vm.startBroadcast(deployerPrivateKey);

        geniusGenericBundler = new GeniusGenericBundler(
            deployer,
            payable(deployer),
            0x000000000022D473030F116dDEE9F6B43aC78BA3
        );

        console.log("GeniusMulticall deployed at: ", address(geniusGenericBundler));

        vm.stopBroadcast();
    }
}
