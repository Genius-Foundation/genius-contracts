// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {GeniusVault} from "../../src/GeniusVault.sol";

contract UpdateMaxOrderAmount is Script {
    GeniusVault public geniusVault;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Replace with your deployed vault address
        geniusVault = GeniusVault(0xA3372621d29e65fb1853BbeF2D78f63db135A2c2);

        // Set the max order amount
        // Note: Adjust this value based on your stablecoin's decimals
        // For a 6-decimal stablecoin like USDC:
        // 1,000,000 = $1 (6 decimals)
        // 1,000,000,000 = $1,000 (6 decimals)
        // 1,000,000,000,000 = $1,000,000 (6 decimals)
        uint256 newMaxOrderAmount = 100000000; // $10,000 with 6 decimals

        // Get the current max order amount
        uint256 currentMaxOrderAmount = geniusVault.maxOrderAmount();

        // Only update if the value is different
        if (currentMaxOrderAmount != newMaxOrderAmount) {
            console.log(
                "Updating max order amount from",
                currentMaxOrderAmount,
                "to",
                newMaxOrderAmount
            );

            geniusVault.setMaxOrderAmount(newMaxOrderAmount);

            // Verify the update was successful
            uint256 updatedMaxOrderAmount = geniusVault.maxOrderAmount();
            console.log("New max order amount set to:", updatedMaxOrderAmount);
        } else {
            console.log(
                "Max order amount already set to the desired value:",
                currentMaxOrderAmount
            );
        }

        vm.stopBroadcast();
    }
}
