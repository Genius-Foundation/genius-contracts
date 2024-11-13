// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/GeniusActions.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract GeniusActionsHandler is Test {
    GeniusActions public geniusActions;

    // Ghost variables for tracking state
    mapping(bytes32 => bool) public knownLabels;
    mapping(bytes32 => bool) public knownHashes;
    mapping(uint256 => bool) public knownIds;
    uint256 public totalActions;
    mapping(address => bool) public knownOrchestrators;
    mapping(bytes32 => bool) public knownCommitHashes;

    // Track active and inactive actions
    mapping(bytes32 => bool) public actionStatus;

    // Fixed size arrays for actors
    address[3] public admins;
    address[3] public sentinels;
    address[3] public orchestrators;
    uint256 public constant NUM_ACTORS = 3;

    // IPFS hash prefix for creating valid IPFS hashes
    string constant IPFS_PREFIX =
        "QmWmyoMoctfbAaiEs2G46gpeUmhqFRDW6KWo64y5r581Vz";

    constructor(GeniusActions _geniusActions) {
        geniusActions = _geniusActions;

        // Setup test actors
        for (uint i = 0; i < NUM_ACTORS; i++) {
            admins[i] = makeAddr(string.concat("admin", vm.toString(i)));
            sentinels[i] = makeAddr(string.concat("sentinel", vm.toString(i)));
            orchestrators[i] = makeAddr(
                string.concat("orchestrator", vm.toString(i))
            );
        }
    }

    // Modifiers to handle actor selection
    modifier useAdmin(uint256 actorSeed) {
        address admin = admins[bound(actorSeed, 0, NUM_ACTORS - 1)];
        vm.startPrank(admin);
        _;
        vm.stopPrank();
    }

    modifier useSentinel(uint256 actorSeed) {
        address sentinel = sentinels[bound(actorSeed, 0, NUM_ACTORS - 1)];
        vm.startPrank(sentinel);
        _;
        vm.stopPrank();
    }

    // Helper to generate valid IPFS hash
    function generateIpfsHash(
        uint256 seed
    ) internal pure returns (string memory) {
        return string.concat(IPFS_PREFIX, vm.toString(seed));
    }

    // Bounded action functions
    function addAction(
        bytes32 actionLabel,
        uint256 ipfsHashSeed,
        uint256 adminSeed
    ) external useAdmin(adminSeed) {
        // Generate a valid IPFS hash
        string memory ipfsHash = generateIpfsHash(ipfsHashSeed);
        bytes32 actionHash = geniusActions.getActionHashFromIpfsHash(ipfsHash);

        // Skip if label or hash already exists
        if (knownLabels[actionLabel] || knownHashes[actionHash]) return;

        try geniusActions.addAction(actionLabel, ipfsHash) {
            knownLabels[actionLabel] = true;
            knownHashes[actionHash] = true;
            actionStatus[actionLabel] = true; // New actions are active by default
            totalActions++;
            knownIds[totalActions] = true;
        } catch {}
    }

    function updateActionStatus(
        bytes32 actionLabel,
        bool active,
        uint256 adminSeed
    ) external useAdmin(adminSeed) {
        if (!knownLabels[actionLabel]) return;

        try geniusActions.updateActionStatusByLabel(actionLabel, active) {
            actionStatus[actionLabel] = active;
        } catch {}
    }

    function setOrchestratorAuthorized(
        uint256 orchestratorSeed,
        bool authorized,
        uint256 adminSeed
    ) external useAdmin(adminSeed) {
        address orchestrator = orchestrators[
            bound(orchestratorSeed, 0, NUM_ACTORS - 1)
        ];

        try geniusActions.setOrchestratorAuthorized(orchestrator, authorized) {
            knownOrchestrators[orchestrator] = authorized;
        } catch {}
    }

    function setCommitHashAuthorized(
        bytes32 commitHash,
        bool authorized,
        uint256 adminSeed
    ) external useAdmin(adminSeed) {
        try geniusActions.setCommitHashAuthorized(commitHash, authorized) {
            knownCommitHashes[commitHash] = authorized;
        } catch {}
    }

    function emergencyDisableAction(
        bytes32 actionLabel,
        uint256 sentinelSeed
    ) external useSentinel(sentinelSeed) {
        if (!knownLabels[actionLabel]) return;

        try geniusActions.emergencyDisableActionByLabel(actionLabel) {
            actionStatus[actionLabel] = false;
        } catch {}
    }

    function getKnownActionLabels() external view returns (bytes32[] memory) {
        bytes32[] memory labels = new bytes32[](totalActions);
        uint256 index = 0;
        for (uint256 i = 1; i <= totalActions; i++) {
            bytes32 label = bytes32(i);
            if (knownLabels[label]) {
                labels[index] = label;
                index++;
            }
        }
        return labels;
    }
}

contract GeniusActionsFuzzTest is Test {
    GeniusActions public geniusActions;
    GeniusActionsHandler public handler;

    function setUp() public {
        // Deploy with initial admin as this contract
        geniusActions = new GeniusActions(address(this));
        handler = new GeniusActionsHandler(geniusActions);

        // Target only the handler contract
        targetContract(address(handler));

        // Setup roles for handler's actors
        for (uint i = 0; i < handler.NUM_ACTORS(); i++) {
            address admin = handler.admins(i);
            address sentinel = handler.sentinels(i);

            geniusActions.grantRole(geniusActions.DEFAULT_ADMIN_ROLE(), admin);
            geniusActions.grantRole(geniusActions.SENTINEL_ROLE(), sentinel);
        }
    }

    // Invariant 1: Action statuses should match between handler and contract
    function invariant_actionStatusConsistency() public {
        bytes32[] memory knownLabels = handler.getKnownActionLabels();
        for (uint i = 0; i < knownLabels.length; i++) {
            if (knownLabels[i] != bytes32(0)) {
                GeniusActions.Action memory action = geniusActions
                    .getActionByActionLabel(knownLabels[i]);
                assertEq(action.active, handler.actionStatus(knownLabels[i]));
            }
        }
    }

    // Invariant 2: Every known label should point to a valid action
    function invariant_labelPointsToValidAction() public {
        bytes32[] memory knownLabels = handler.getKnownActionLabels();
        for (uint i = 0; i < knownLabels.length; i++) {
            if (knownLabels[i] != bytes32(0)) {
                GeniusActions.Action memory action = geniusActions
                    .getActionByActionLabel(knownLabels[i]);
                assertTrue(bytes(action.ipfsHash).length > 0);
            }
        }
    }

    // Invariant 3: Orchestrator authorization status should match handler's record
    function invariant_orchestratorAuthorizationConsistency() public {
        for (uint i = 0; i < handler.NUM_ACTORS(); i++) {
            address orchestrator = handler.orchestrators(i);
            assertEq(
                geniusActions.isAuthorizedOrchestrator(orchestrator),
                handler.knownOrchestrators(orchestrator)
            );
        }
    }

    // Invariant 4: Commit hash authorization status should match handler's record
    function invariant_commitHashAuthorizationConsistency() public {
        bytes32[] memory testHashes = new bytes32[](3);
        for (uint i = 0; i < testHashes.length; i++) {
            testHashes[i] = keccak256(abi.encodePacked(i));
            assertEq(
                geniusActions.isAuthorizedCommitHash(testHashes[i]),
                handler.knownCommitHashes(testHashes[i])
            );
        }
    }

    // Invariant 5: Emergency disabled actions should always be inactive
    function invariant_emergencyDisabledActionsStayInactive() public {
        bytes32[] memory knownLabels = handler.getKnownActionLabels();
        for (uint i = 0; i < knownLabels.length; i++) {
            if (knownLabels[i] != bytes32(0)) {
                GeniusActions.Action memory action = geniusActions
                    .getActionByActionLabel(knownLabels[i]);
                if (!handler.actionStatus(knownLabels[i])) {
                    assertTrue(!action.active);
                }
            }
        }
    }

    // Invariant 6: Action hash and label mappings should remain consistent
    function invariant_hashLabelConsistency() public {
        bytes32[] memory knownLabels = handler.getKnownActionLabels();
        for (uint i = 0; i < knownLabels.length; i++) {
            if (knownLabels[i] != bytes32(0)) {
                GeniusActions.Action memory action = geniusActions
                    .getActionByActionLabel(knownLabels[i]);
                bytes32 hash = geniusActions.getActionHashFromIpfsHash(
                    action.ipfsHash
                );
                GeniusActions.Action memory actionByHash = geniusActions
                    .getActionByActionHash(hash);
                assertEq(
                    keccak256(abi.encodePacked(action.ipfsHash)),
                    keccak256(abi.encodePacked(actionByHash.ipfsHash))
                );
            }
        }
    }

    function invariant_callSummary() public view {
        console.log("Total actions created:", handler.totalActions());
    }
}
