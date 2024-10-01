// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UpgradeGeniusExecutorCore} from "./UpgradeGeniusExecutorCore.s.sol";

contract UpgradePolygonGeniusExecutor is UpgradeGeniusExecutorCore {
    address public constant GENIUS_VAULT =
        0x5949EE17a674c0706b3364191B516fb87268A32a;
    address public constant PERMIT2 =
        0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public constant STABLECOIN =
        0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    function run() external {
        address[] memory authorizedTargets = new address[](3);
        authorizedTargets[0] = 0xeF4fB24aD0916217251F553c0596F8Edc630EB66;
        authorizedTargets[1] = 0x663DC15D3C1aC63ff12E45Ab68FeA3F0a883C251;
        authorizedTargets[2] = 0x4E3288c9ca110bCC82bf38F09A7b425c095d92Bf;
        _run(GENIUS_VAULT, PERMIT2, STABLECOIN, authorizedTargets);
    }
}
