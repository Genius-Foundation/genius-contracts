// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UpgradeGeniusExecutorCore} from "./UpgradeGeniusExecutorCore.s.sol";

contract UpgradeBscGeniusExecutor is UpgradeGeniusExecutorCore {
    address public constant GENIUS_VAULT =
        0x92Ca25e45a0Dcb2C5df1EC17B687A0A009Cb3E04;
    address public constant PERMIT2 =
        0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public constant STABLECOIN =
        0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;

    function run() external {
        address[] memory authorizedTargets = new address[](3);
        authorizedTargets[0] = 0xeF4fB24aD0916217251F553c0596F8Edc630EB66;
        authorizedTargets[1] = 0x663DC15D3C1aC63ff12E45Ab68FeA3F0a883C251;
        authorizedTargets[2] = 0x89b8AA89FDd0507a99d334CBe3C808fAFC7d850E;

        _run(GENIUS_VAULT, PERMIT2, STABLECOIN, authorizedTargets);
    }
}
