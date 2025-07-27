// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {GeniusProxyCall} from "../../src/GeniusProxyCall.sol";
import {GeniusVault} from "../../src/GeniusVault.sol";
import {GeniusRouter} from "../../src/GeniusRouter.sol";
import {GeniusGasTank} from "../../src/GeniusGasTank.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {MerkleDistributor} from "../../src/distributor/MerkleDistributor.sol";

/**
 * @title DeployPolygonGeniusEcosystem
 * @dev A contract for deploying the GeniusExecutor contract.
        Deployment commands:
        `source .env` // Load environment variables
        POLYGON: forge script script/deployment/DeployPolygonGeniusEcosystem.s.sol:DeployPolygonGeniusEcosystem --rpc-url $POLYGON_RPC_URL --broadcast -vvvv --via-ir
 */
contract DeployGeniusEcosystemCore is Script {
    bytes32 constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");

    GeniusVault public geniusVault;
    GeniusRouter public geniusRouter;
    GeniusGasTank public geniusGasTank;
    GeniusProxyCall public geniusProxyCall;
    MerkleDistributor public merkleDistributor;
    FeeCollector public feeCollector;

    function _run(
        address _permit2Address,
        address _stableAddress,
        address _priceFeed,
        uint256 _priceFeedHeartbeat,
        address _owner,
        uint256[] memory targetNetworks,
        uint256[] memory minFeeAmounts,
        uint256[] memory bpsThresholds,
        uint256[] memory bpsFees,
        uint256 insuranceFee,
        uint256 maxOrderSize
    ) internal {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // geniusActions = new GeniusActions(admin);

        geniusProxyCall = new GeniusProxyCall(_owner, new address[](0));

        GeniusVault implementation = new GeniusVault();

        bytes memory data = abi.encodeWithSelector(
            GeniusVault.initialize.selector,
            _stableAddress,
            _owner,
            address(geniusProxyCall),
            7_500,
            _priceFeed,
            _priceFeedHeartbeat,
            99_000_000,
            101_000_000,
            maxOrderSize
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        geniusVault = GeniusVault(address(proxy));

        // Deploy FeeCollector implementation
        FeeCollector feeCollectorImpl = new FeeCollector();

        address protocolFeeReceiver = _owner;
        address lpFeeReceiver = _owner;
        address operatorFeeReceiver = _owner;

        // Prepare initialization data
        bytes memory feeCollectorInitData = abi.encodeWithSelector(
            FeeCollector.initialize.selector,
            _owner, // admin address
            _stableAddress, // stablecoin address
            3000, // 30% protocol fee
            protocolFeeReceiver,
            lpFeeReceiver,
            operatorFeeReceiver
        );

        // Deploy proxy
        ERC1967Proxy feeCollectorProxy = new ERC1967Proxy(
            address(feeCollectorImpl),
            feeCollectorInitData
        );
        feeCollector = FeeCollector(address(feeCollectorProxy));

        geniusRouter = new GeniusRouter(
            _permit2Address,
            address(geniusVault),
            address(geniusProxyCall),
            address(feeCollectorProxy) // Assuming feeCollector is set up elsewhere
        );

        geniusGasTank = new GeniusGasTank(
            _owner,
            payable(_owner),
            _permit2Address,
            address(geniusProxyCall)
        );

        // Deploy the implementation contract
        MerkleDistributor merkleDistributorImpl = new MerkleDistributor();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            MerkleDistributor.initialize.selector,
            _owner
        );

        // Deploy the proxy contract
        ERC1967Proxy merkleDistributorProxy = new ERC1967Proxy(
            address(merkleDistributorImpl),
            initData
        );

        // Cast the proxy to MerkleDistributor for verification
        merkleDistributor = MerkleDistributor(address(merkleDistributorProxy));

        feeCollector.grantRole(feeCollector.DISTRIBUTOR_ROLE(), address(merkleDistributor));
        merkleDistributor.grantRole(merkleDistributor.DISTRIBUTOR_ROLE(), address(feeCollector));

        feeCollector.setFeeTiers(bpsThresholds, bpsFees);

        uint256[] memory insuranceThresholdAmounts = new uint256[](1);
        uint256[] memory insuranceFees = new uint256[](1);
        insuranceFees[0] = insuranceFee;
        feeCollector.setInsuranceFeeTiers(
            insuranceThresholdAmounts,
            insuranceFees
        );

        for (uint256 i = 0; i < targetNetworks.length; i++) {
            if (targetNetworks[i] == block.chainid) {
                continue; // Skip current chain
            }
            feeCollector.setTargetChainMinFee(targetNetworks[i], minFeeAmounts[i]);
        }

        geniusVault.setChainStablecoinDecimals(10, 6);
        geniusVault.setChainStablecoinDecimals(1, 6);
        geniusVault.setChainStablecoinDecimals(8453, 6);
        geniusVault.setChainStablecoinDecimals(42161, 6);
        geniusVault.setChainStablecoinDecimals(43114, 6);
        geniusVault.setChainStablecoinDecimals(56, 18);
        geniusVault.setChainStablecoinDecimals(1399811149, 6);
        geniusVault.setChainStablecoinDecimals(146, 6);
        geniusVault.setChainStablecoinDecimals(137, 6);

        geniusProxyCall.grantRole(
            keccak256("CALLER_ROLE"),
            address(geniusVault)
        );
        geniusProxyCall.grantRole(
            keccak256("CALLER_ROLE"),
            address(geniusRouter)
        );
        geniusProxyCall.grantRole(
            keccak256("CALLER_ROLE"),
            address(geniusGasTank)
        );

        console.log("GeniusProxyCall deployed at: ", address(geniusProxyCall));
        console.log("GeniusVault deployed at: ", address(geniusVault));
        console.log("GeniusRouter deployed at: ", address(geniusRouter));
        console.log("GeniusGasTank deployed at: ", address(geniusGasTank));
        console.log("FeeCollector deployed at: ", address(feeCollector));
        console.log("MerkleDistributor deployed at: ", address(merkleDistributor));
    }
}
