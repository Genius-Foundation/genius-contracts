// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {GeniusExecutor} from "../src/GeniusExecutor.sol";
import {GeniusPool} from "../src/GeniusPool.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {GeniusActions} from "../src/GeniusActions.sol";

/**
 * @title DeployGeniusEcosystem.s
 * @dev A contract for deploying the GeniusExecutor contract.
        Deployment commands:
        `source .env` // Load environment variables
        AVALANCHE: forge script script/DeployGeniusEcosystem.s.sol:DeployGeniusEcosystem --rpc-url $AVALANCHE_RPC_URL --broadcast --verify -vvvv --via-ir
        BASE: forge script script/DeployGeniusEcosystem.s.sol:DeployGeniusEcosystem --rpc-url $BASE_RPC_URL --broadcast --verify -vvvv --via-ir
 */
contract DeployGeniusEcosystem is Script {
    address public constant stableAddress = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address public constant bridgeAddress = 0x45A01E4e04F14f7A4a6702c74187c5F6222033cd;
    address public constant permit2Address = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address public constant owner = 0x5CC11Ef1DE86c5E00259a463Ac3F3AE1A0fA2909;
    address public constant admin = 0x6192A053B05942e9D7EB98e3b2146283aD559e62;

    GeniusPool public geniusPool;
    GeniusVault public geniusVault;
    GeniusExecutor public geniusExecutor;
    GeniusActions public geniusActions;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // geniusActions = new GeniusActions(admin);
        geniusPool = new GeniusPool(stableAddress, bridgeAddress, owner);
        geniusVault = new GeniusVault(stableAddress);
        geniusExecutor = new GeniusExecutor(permit2Address, address(geniusPool));

        geniusPool.initialize(address(geniusVault));
        geniusVault.initialize(address(geniusPool));

        geniusPool.addOrchestrator(0xa50b4307ee0bc9b6586e3A52A75A22F199d12E57);

        console.log("GeniusPool deployed at: ", address(geniusPool));
        console.log("GeniusVault deployed at: ", address(geniusVault));
        console.log("GeniusExecutor deployed at: ", address(geniusExecutor));
    }
}
