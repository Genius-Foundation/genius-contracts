// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GeniusVault} from "../../src/GeniusVault.sol";
import {GeniusPool} from "../../src/GeniusPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
/**
 * @title AdjustThreshold
 * @dev A contract for deploying the GeniusVault contract.
        Deployment command: 
        AVALANCHE: forge script script/utility/AdjustThreshold.s.sol:AdjustThreshold --rpc-url $AVALANCHE_RPC_URL --broadcast --verify -vvvv --via-ir
        BASE: forge script script/utility/AdjustThreshold.s.sol:AdjustThreshold --rpc-url $BASE_RPC_URL --broadcast --verify -vvvv --via-ir
        ARBITRUM: forge script script/utility/AdjustThreshold.s.sol:AdjustThreshold --rpc-url $ARBITRUM_RPC_URL --broadcast --verify -vvvv --via-ir
        OPTIMISM: forge script script/utility/AdjustThreshold.s.sol:AdjustThreshold --rpc-url $OPTIMISM_RPC_URL --broadcast --verify -vvvv --via-ir
        FANTOM: forge script script/utility/AdjustThreshold.s.sol:AdjustThreshold --rpc-url $FANTOM_RPC_URL --broadcast --verify -vvvv --via-ir
        POLYGON: forge script script/utility/AdjustThreshold.s.sol:AdjustThreshold --rpc-url $POLYGON_RPC_URL --broadcast --verify -vvvv --via-ir
        BSC: forge script script/utility/AdjustThreshold.s.sol:AdjustThreshold --rpc-url $BSC_RPC_URL --broadcast --verify -vvvv --via-ir
 */
contract AdjustThreshold is Script {

    /**
     * @dev Executes the deployment of the GeniusVault contract.
     */

    function run() external {

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        GeniusPool geniusPool = GeniusPool(0xBD1B1e1f33f89D4beCd0E5c6D3E88bd447992134);

        geniusPool.setRebalanceThreshold(75);

        console.log("Rebalance threshold adjusted to 75");

    }
}