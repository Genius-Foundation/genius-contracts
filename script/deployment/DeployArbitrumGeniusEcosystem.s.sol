// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {GeniusExecutor} from "../../src/GeniusExecutor.sol";
import {GeniusPool} from "../../src/GeniusPool.sol";
import {GeniusVault} from "../../src/GeniusVault.sol";
import {GeniusActions} from "../../src/GeniusActions.sol";

/**
 * @title DeployArbitrumGeniusEcosystem
 * @dev A contract for deploying the GeniusExecutor contract.
        Deployment commands:
        `source .env` // Load environment variables
        ARBITRUM: forge script script/deployment/DeployArbitrumGeniusEcosystem.s.sol:DeployArbitrumGeniusEcosystem --rpc-url $ARBITRUM_RPC_URL --broadcast -vvvv --via-ir
 */
contract DeployArbitrumGeniusEcosystem is Script {
    bytes32 constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");
    
    address public constant stableAddress = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public constant bridgeAddress = 0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614;
    address public constant permit2Address = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address public constant owner = 0x5CC11Ef1DE86c5E00259a463Ac3F3AE1A0fA2909;
    // address public constant admin = 0x6192A053B05942e9D7EB98e3b2146283aD559e62;

    GeniusPool public geniusPool;
    GeniusVault public geniusVault;
    GeniusExecutor public geniusExecutor;
    GeniusActions public geniusActions;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // geniusActions = new GeniusActions(admin);
        // geniusVault = new GeniusVault(stableAddress);


        // geniusPool = new GeniusPool(
        //     stableAddress,
        //     bridgeAddress,
        //     owner
        // );

        // geniusExecutor = new GeniusExecutor(
        //     permit2Address,
        //     0x92Ca25e45a0Dcb2C5df1EC17B687A0A009Cb3E04,
        //     0x237008a4052209e97753e1c9a0a148a0796Ce632
        // );


        // Get an instance of the GeniusPool contract at 0xf79C2054Dcd781b19da5f58BB2F901db9c2bfAbC
        geniusPool = GeniusPool(0x92Ca25e45a0Dcb2C5df1EC17B687A0A009Cb3E04);
        geniusVault = GeniusVault(0x237008a4052209e97753e1c9a0a148a0796Ce632);
        geniusExecutor = GeniusExecutor(payable(0x3A12188Cb2e96b41dFB1D48Cf3fdE6cECa7DcFC1));

        // Initialize the contracts
        // geniusPool.initialize(address(geniusVault));
        // geniusVault.initialize(address(geniusPool));

        // // Add orchestrators
        // geniusPool.addOrchestrator(0x17cC1e3AF40C88B235d9837990B8ad4D7C06F5cc);
        // geniusPool.addOrchestrator(0x4102b4144e9EFb8Cb0D7dc4A3fD8E65E4A8b8fD0);
        // geniusPool.addOrchestrator(0x90B29aF53D2bBb878cAe1952B773A307330393ef);
        // geniusPool.addOrchestrator(0x7e5E0712c627746a918ae2015e5bfAB51c86dA26);
        geniusPool.grantRole(ORCHESTRATOR_ROLE, 0x5975fBa1186116168C479bb21Bb335f02D504CFB);


        // console.log("GeniusPool deployed at: ", address(geniusPool));
        // console.log("GeniusVault deployed at: ", address(geniusVault));
        // console.log("GeniusExecutor deployed at: ", address(geniusExecutor));
    }
}
