// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Permit2Multicaller} from "../src/Permit2Multicaller.sol";

/**
 * @title DeployGenDeployPermit2Multicaller
 * @dev A contract for deploying the Permit2Multicaller contract.
        Deployment commands:
        AVALANCHE: forge script script/DeployPermit2Multicaller.s.sol:DeployPermit2Multicaller --rpc-url $AVALANCHE_RPC_URL --broadcast --verify -vvvv --via-ir
        BASE: forge script script/DeployPermit2Multicaller.s.sol:DeployPermit2Multicaller --rpc-url $BASE_RPC_URL --broadcast --verify -vvvv --via-ir
 */
contract DeployPermit2Multicaller is Script {

    /**
     * @dev Executes the deployment of the GeniusVault contract.
     */

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.broadcast(deployerPrivateKey);

        Permit2Multicaller permit2Multicaller = new Permit2Multicaller(
            0x000000000022D473030F116dDEE9F6B43aC78BA3,
            0x91Fd82B9326BB22F81B3E7B8C2001C42269f52Fa

        );

        console.log("Permit2Multicaller deployed at: ", address(permit2Multicaller));
    }
}
