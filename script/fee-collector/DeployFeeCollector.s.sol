// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";

/**
 * @title DeployFeeCollector
 * @dev Script to deploy FeeCollector implementation and proxy
 * Deployment command:
 * source .env && forge script script/DeployFeeCollector.sol --rpc-url $BASE_RPC_URL --broadcast -vvvv --via-ir
 */
contract DeployFeeCollector is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address owner = 0x5CC11Ef1DE86c5E00259a463Ac3F3AE1A0fA2909;
        address stablecoin = vm.envAddress("STABLECOIN_BASE_DEV");

        address protocolFeeReceiver = owner;
        address lpFeeReceiver = owner;
        address operatorFeeReceiver = owner;

        vm.startBroadcast(deployerPrivateKey);

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
            "IMPORTANT: Set FEE_COLLECTOR_BASE_DEV=%s in your .env file",
            address(feeCollectorProxy)
        );

        vm.stopBroadcast();
    }
}
