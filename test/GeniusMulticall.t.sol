// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";
import {GeniusMulticall} from "src/GeniusMulticall.sol";
import {TransferEth} from "test/utils/TransferEth.sol";

contract GeniusProxyCallTest is Test {
    GeniusMulticall public GENIUS_MULTICALL = new GeniusMulticall();
    TransferEth public TRANSFER_ETH = new TransferEth();
    address trader = makeAddr("trader");

    function setUp() public {
        // Fund the trader with 10 ether
        vm.deal(trader, 10 ether);
        vm.deal(address(TRANSFER_ETH), 10 ether);
    }

    function testNativeRefundMulticall() public {
        address[] memory targets = new address[](1);
        targets[0] = address(TRANSFER_ETH);

        uint256[] memory values = new uint256[](1);
        values[0] = 1 ether; // Provide value for transfer

        bytes[] memory dataArray = new bytes[](1);
        dataArray[0] = abi.encodeWithSelector(
            TRANSFER_ETH.transferEth.selector,
            payable(address(GENIUS_MULTICALL))
        );

        bytes memory transactions = _encodeTransactions(targets, values, dataArray);

        // Call with value
        GENIUS_MULTICALL.multiSend{value: 1 ether}(transactions);
    }


    function testNativeRefundTrader() public {
        address[] memory targets = new address[](1);
        targets[0] = address(TRANSFER_ETH);

        uint256[] memory values = new uint256[](1);
        values[0] = 1 ether; // Provide value for transfer

        bytes[] memory dataArray = new bytes[](1);
        dataArray[0] = abi.encodeWithSelector(
            TRANSFER_ETH.transferEth.selector,
            payable(trader)
        );

        bytes memory transactions = _encodeTransactions(targets, values, dataArray);

        // Call with value
        GENIUS_MULTICALL.multiSend{value: 1 ether}(transactions);
    }

    function _encodeTransactions(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory dataArray
    ) internal pure returns (bytes memory) {
        require(
            targets.length == values.length &&
                values.length == dataArray.length,
            "Array lengths must match"
        );

        bytes memory encoded = new bytes(0);

        for (uint i = 0; i < targets.length; i++) {
            encoded = abi.encodePacked(
                encoded,
                uint8(0), // operation (0 for call)
                targets[i],
                values[i],
                uint256(dataArray[i].length),
                dataArray[i]
            );
        }

        return encoded; // Return the raw transaction bytes
    }
}
