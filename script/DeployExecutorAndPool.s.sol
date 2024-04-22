// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {GeniusExecutor} from "../src/GeniusExecutor.sol";
import {GeniusPool} from "../src/GeniusPool.sol";

/**
 * @title DeployGeniusExecutor
 * @dev A contract for deploying the GeniusExecutor contract.
        Deployment commands:
        AVALANCHE: forge script script/DeployGeniusExecutor.s.sol:DeployGeniusExecutor --rpc-url $AVALANCHE_RPC_URL --broadcast --verify -vvvv --via-ir
        BASE: forge script script/DeployGeniusExecutor.s.sol:DeployGeniusExecutor --rpc-url $BASE_RPC_URL --broadcast --verify -vvvv --via-ir
 */
contract DeployGeniusExecutor is Script {

    address public immutable PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public immutable STABLECOIN = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public immutable DEPLOYER = 0x5CC11Ef1DE86c5E00259a463Ac3F3AE1A0fA2909;

    /**
     * @dev Executes the deployment of the GeniusVault contract.
     */

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.broadcast(deployerPrivateKey);

        GeniusPool geniusPool = new GeniusPool(PERMIT2, DEPLOYER);
        GeniusExecutor geniusExecutor = new GeniusExecutor(PERMIT2, address(geniusPool));

        console.log("Permit2Multicaller deployed at: ", address(geniusExecutor));
    }
}
