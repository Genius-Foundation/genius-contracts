// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UpgradeGeniusExecutorCore} from "./UpgradeGeniusExecutorCore.s.sol";

contract UpgradeEthereumGeniusExecutor is UpgradeGeniusExecutorCore {
    address public constant GENIUS_VAULT =
        0x9a49a950607FE4FeaAD4b7CdC205eb13CAf0D32f;
    address public constant PERMIT2 =
        0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public constant STABLECOIN =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function run() external {
        address[] memory authorizedTargets = new address[](3);
        authorizedTargets[0] = 0xeF4fB24aD0916217251F553c0596F8Edc630EB66;
        authorizedTargets[1] = 0x663DC15D3C1aC63ff12E45Ab68FeA3F0a883C251;
        authorizedTargets[2] = 0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559;

        _run(GENIUS_VAULT, PERMIT2, STABLECOIN, authorizedTargets);
    }
}
