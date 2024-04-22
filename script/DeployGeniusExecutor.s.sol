// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GeniusExecutor} from "../src/GeniusExecutor.sol";

/**
 * @title DeployGeniusExecutor
 * @dev A contract for deploying the GeniusExecutor contract.
        Deployment commands:
        AVALANCHE: forge script script/DeployGeniusExecutor.s.sol:DeployGeniusExecutor --rpc-url $AVALANCHE_RPC_URL --broadcast --verify -vvvv --via-ir
        BASE: forge script script/DeployGeniusExecutor.s.sol:DeployGeniusExecutor --rpc-url $BASE_RPC_URL --broadcast --verify -vvvv --via-ir
 */
contract DeployGeniusExecutor is Script {

    /**
     * @dev Executes the deployment of the GeniusVault contract.
     */

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.broadcast(deployerPrivateKey);

        GeniusExecutor geniusExecutor = new GeniusExecutor(
            0x000000000022D473030F116dDEE9F6B43aC78BA3,
            0x74491a521984292d22F34Dee51EdAc9B52671eFE

        );

        console.log("Permit2Multicaller deployed at: ", address(geniusExecutor));
    }
}
