// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract TransferEth {
    function transferEth(address payable to) external payable {
        (bool success, ) = to.call{value: msg.value}("");
        require(success, "Transfer failed");
    }
}