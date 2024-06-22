// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GeniusVault} from "../../src/GeniusVault.sol";
import {GeniusPool} from "../../src/GeniusPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
/**
 * @title StakeInitialLiquidity
 * @dev A contract for deploying the GeniusVault contract.
        Deployment command: 
        AVALANCHE: forge script script/utility/StakeInitialLiquidity.s.sol:StakeInitialLiquidity --rpc-url $AVALANCHE_RPC_URL --broadcast --verify -vvvv --via-ir
        BASE: forge script script/utility/StakeInitialLiquidity.s.sol:StakeInitialLiquidity --rpc-url $BASE_RPC_URL --broadcast --verify -vvvv --via-ir
        ARBITRUM: forge script script/utility/StakeInitialLiquidity.s.sol:StakeInitialLiquidity --rpc-url $ARBITRUM_RPC_URL --broadcast --verify -vvvv --via-ir
        OPTIMISM: forge script script/utility/StakeInitialLiquidity.s.sol:StakeInitialLiquidity --rpc-url $OPTIMISM_RPC_URL --broadcast --verify -vvvv --via-ir
        FANTOM: forge script script/utility/StakeInitialLiquidity.s.sol:StakeInitialLiquidity --rpc-url $FANTOM_RPC_URL --broadcast --verify -vvvv --via-ir
        POLYGON: forge script script/utility/StakeInitialLiquidity.s.sol:StakeInitialLiquidity --rpc-url $POLYGON_RPC_URL --broadcast --verify -vvvv --via-ir
        BSC: forge script script/utility/StakeInitialLiquidity.s.sol:StakeInitialLiquidity --rpc-url $BSC_RPC_URL --broadcast --verify -vvvv --via-ir
 */
contract StakeInitialLiquidity is Script {

    /**
     * @dev Executes the deployment of the GeniusVault contract.
     */

    function run() external {
        uint256 stakerPrivateKey = vm.envUint("STAKER_PRIVATE_KEY");
        vm.startBroadcast(stakerPrivateKey);

        GeniusVault geniusVault = GeniusVault(0xDCF998011dcAab9B8C1Ea5B34f1b6c7bAF59d4C0);

        // Add orchestrator
        IERC20 stablecoin = IERC20(0x28a92dde19D9989F39A49905d7C9C2FAc7799bDf);

        stablecoin.approve(address(geniusVault), 200000000);
        geniusVault.deposit(200000000, 0x2Cd60849380319b59e180BC2137352C6dF838A33);

        console.log("Initial liquidity staked in GeniusVault");


        // uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        // vm.startBroadcast(deployerPrivateKey);

        // // Adjust threshold to 75
        // geniusPool.setRebalanceThreshold(75);

        // console.log("Rebalance threshold adjusted to 75");

    }
}