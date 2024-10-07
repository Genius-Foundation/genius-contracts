// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UpgradeGeniusExecutorCore} from "./UpgradeGeniusExecutorCore.s.sol";

contract UpgradeBaseGeniusExecutor is UpgradeGeniusExecutorCore {
    address public constant GENIUS_VAULT =
        0x5B246B77A398E50d1647D85A6cfD2D6B8B57485f;
    address public constant PERMIT2 =
        0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function run() external {
        address[] memory authorizedTargets = new address[](3);
        authorizedTargets[0] = 0xeF4fB24aD0916217251F553c0596F8Edc630EB66;
        authorizedTargets[1] = 0x663DC15D3C1aC63ff12E45Ab68FeA3F0a883C251;
        authorizedTargets[2] = 0x19cEeAd7105607Cd444F5ad10dd51356436095a1;

        _run(GENIUS_VAULT, PERMIT2, authorizedTargets);
    }
}
