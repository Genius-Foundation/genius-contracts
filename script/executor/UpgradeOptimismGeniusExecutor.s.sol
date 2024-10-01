// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UpgradeGeniusExecutorCore} from "./UpgradeGeniusExecutorCore.s.sol";

contract UpgradeOptimismGeniusExecutor is UpgradeGeniusExecutorCore {
    address public constant GENIUS_VAULT =
        0x1F2824dF56eBB0aC9D02395a923d12D773e38dF8;
    address public constant PERMIT2 =
        0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public constant STABLECOIN =
        0x7F5c764cBc14f9669B88837ca1490cCa17c31607;

    function run() external {
        address[] memory authorizedTargets = new address[](3);
        authorizedTargets[0] = 0xeF4fB24aD0916217251F553c0596F8Edc630EB66;
        authorizedTargets[1] = 0x663DC15D3C1aC63ff12E45Ab68FeA3F0a883C251;
        authorizedTargets[2] = 0xCa423977156BB05b13A2BA3b76Bc5419E2fE9680;

        _run(GENIUS_VAULT, PERMIT2, STABLECOIN, authorizedTargets);
    }
}
