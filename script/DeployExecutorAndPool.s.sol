// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GeniusExecutor} from "../src/GeniusExecutor.sol";
import {GeniusPool} from "../src/GeniusPool.sol";

/**
 * @title DeployExecutorAndPool
 * @dev A contract for deploying the GeniusExecutor contract.
        Deployment commands:
        AVALANCHE: forge script script/DeployExecutorAndPool.s.sol:DeployExecutorAndPool --rpc-url $AVALANCHE_RPC_URL --broadcast --verify -vvvv --via-ir
        BASE: forge script script/DeployExecutorAndPool.s.sol:DeployExecutorAndPool --rpc-url $BASE_RPC_URL --broadcast --verify -vvvv --via-ir
        ARBITRUM: forge script script/DeployExecutorAndPool.s.sol:DeployExecutorAndPool --rpc-url $ARBITRUM_RPC_URL --broadcast --verify -vvvv --via-ir
 */
contract DeployExecutorAndPool is Script {

    address public immutable PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public immutable STABLECOIN = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public immutable DEPLOYER = 0x5CC11Ef1DE86c5E00259a463Ac3F3AE1A0fA2909;
    address public immutable STARGATE_ROUTER = 0x74491a521984292d22F34Dee51EdAc9B52671eFE;

    /**
     * @dev Executes the deployment of the GeniusVault contract.
     */

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.broadcast(deployerPrivateKey);

        GeniusPool geniusPool = new GeniusPool(PERMIT2, STARGATE_ROUTER, DEPLOYER);
        GeniusExecutor geniusExecutor = new GeniusExecutor(PERMIT2, address(geniusPool));

        console.log("Permit2Multicaller deployed at: ", address(geniusExecutor));
    }
}
