// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {GeniusGasTank} from "../../src/GeniusGasTank.sol";

contract AddEthereumTargets is Script {
    bytes32 public constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");

    function run() external {
        address[] memory targets = new address[](6);
        targets[0] = 0x7D0CcAa3Fac1e5A943c5168b6CEd828691b46B36;
        targets[1] = 0x40aA958dd87FC8305b97f2BA922CDdCa374bcD7f;
        targets[2] = 0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559;
        targets[3] = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5;
        // Fee collection
        targets[4] = 0x5D7932C58484F90BCEf550aEf8a48b10BAFF39Dc;
        targets[5] = 0xcb1178A50a01147949c883432aee904Eb7788015;

        address[] memory orchestrators = new address[](10);
        orchestrators[0] = 0x17cC1e3AF40C88B235d9837990B8ad4D7C06F5cc;
        orchestrators[1] = 0x4102b4144e9EFb8Cb0D7dc4A3fD8E65E4A8b8fD0;
        orchestrators[2] = 0x90B29aF53D2bBb878cAe1952B773A307330393ef;
        orchestrators[3] = 0x7e5E0712c627746a918ae2015e5bfAB51c86dA26;
        orchestrators[4] = 0x5975fBa1186116168C479bb21Bb335f02D504CFB;
        orchestrators[5] = 0x17cC1e3AF40C88B235d9837990B8ad4D7C06F5cc;
        orchestrators[6] = 0x4102b4144e9EFb8Cb0D7dc4A3fD8E65E4A8b8fD0;
        orchestrators[7] = 0x90B29aF53D2bBb878cAe1952B773A307330393ef;
        orchestrators[8] = 0x7e5E0712c627746a918ae2015e5bfAB51c86dA26;
        orchestrators[9] = 0x5975fBa1186116168C479bb21Bb335f02D504CFB;

        GeniusGasTank geniusGasTank = GeniusGasTank(
            payable(0x39A32f31726950C550441EAe5bc290A6581FDEe3)
        );

        console.log(
            "Deployer private key: %s",
            vm.envUint("DEPLOYER_PRIVATE_KEY")
        );
        console.log(
            "Checking if has role: %s",
            geniusGasTank.hasRole(
                0x00,
                0x5CC11Ef1DE86c5E00259a463Ac3F3AE1A0fA2909
            )
        );
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        bool hasAdminRole = geniusGasTank.hasRole(
            0x00,
            0x5CC11Ef1DE86c5E00259a463Ac3F3AE1A0fA2909
        );
        console.log("Has admin role: %s", hasAdminRole);

        // Add all of the targets
        for (uint256 i; i < targets.length; i++) {
            geniusGasTank.setAllowedTarget(targets[i], true);
        }

        // Add all of the orchestrators
        for (uint256 i; i < orchestrators.length; i++) {
            if (!geniusGasTank.hasRole(ORCHESTRATOR_ROLE, orchestrators[i])) {
                geniusGasTank.grantRole(ORCHESTRATOR_ROLE, orchestrators[i]);
            } else {
                console.log("Orchestrator already added: %s", orchestrators[i]);
            }
        }

        vm.stopBroadcast();
    }
}
