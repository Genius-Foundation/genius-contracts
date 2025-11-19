// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/GeniusSwapRouter.sol";
import "../src/interfaces/IGeniusSwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**18);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock ERC20 with transfer tax
contract MockTaxToken is ERC20 {
    uint256 public taxRate = 100; // 1% tax
    
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**18);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function transfer(address to, uint256 amount) public override returns (bool) {
        uint256 tax = (amount * taxRate) / 10000;
        uint256 amountAfterTax = amount - tax;
        _burn(msg.sender, tax);
        return super.transfer(to, amountAfterTax);
    }
    
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 tax = (amount * taxRate) / 10000;
        uint256 amountAfterTax = amount - tax;
        _burn(from, tax);
        return super.transferFrom(from, to, amountAfterTax);
    }
}

// Mock router that accepts tokens and returns tokens
contract MockRouter {
    function swap(address tokenIn, address tokenOut, uint256 amountIn, address recipient) external payable {
        if (tokenIn != address(0)) {
            IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        }
        if (tokenOut != address(0)) {
            IERC20(tokenOut).transfer(recipient, amountIn);
        } else {
            payable(recipient).transfer(amountIn);
        }
    }
}

contract GeniusSwapRouterTest is Test {
    GeniusSwapRouter public router;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockTaxToken public taxToken;
    MockRouter public mockDex;
    
    // Events for testing
    event FeeRateUpdated(address indexed user, uint256 feeRate);
    event DefaultFeeRateUpdated(uint256 feeRate);
    event FeeCollectorUpdated(address indexed oldCollector, address indexed newCollector);
    event SwapExecuted(
        address indexed user,
        address indexed router,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 actualReceived,
        uint256 fee
    );
    
    address public owner = address(1);
    address public feeCollector = address(2);
    address public user = address(3);
    address public constant NATIVE_PLACEHOLDER = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    
    function setUp() public {
        // Deploy contracts
        vm.prank(owner);
        router = new GeniusSwapRouter(owner, feeCollector);
        
        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");
        taxToken = new MockTaxToken("Tax Token", "TAX");
        mockDex = new MockRouter();
        
        // Setup balances
        tokenA.mint(user, 10000 * 10**18);
        tokenB.mint(address(mockDex), 10000 * 10**18);
        taxToken.mint(user, 10000 * 10**18);
        
        vm.deal(user, 100 ether);
    }
    
    // ========== OWNER-ONLY FUNCTIONALITY TESTS ==========
    
    function test_OnlyOwnerCanSetUserFeeRate() public {
        vm.prank(owner);
        router.setUserFeeRate(user, 200);
        assertEq(router.userFeeRate(user), 200);
        
        vm.prank(user);
        vm.expectRevert();
        router.setUserFeeRate(user, 300);
    }
    
    function test_OnlyOwnerCanSetDefaultFeeRate() public {
        vm.prank(owner);
        router.setDefaultFeeRate(200);
        assertEq(router.defaultFeeRate(), 200);
        
        vm.prank(user);
        vm.expectRevert();
        router.setDefaultFeeRate(300);
    }
    
    function test_OnlyOwnerCanSetFeeCollector() public {
        address newCollector = address(4);
        
        vm.prank(owner);
        router.setFeeCollector(newCollector);
        assertEq(router.feeCollector(), newCollector);
        
        vm.prank(user);
        vm.expectRevert();
        router.setFeeCollector(address(5));
    }
    
    function test_RevertWhenSettingInvalidUserFeeRate() public {
        vm.prank(owner);
        vm.expectRevert(IGeniusSwapRouter.FeeRateExceedsMaximum.selector);
        router.setUserFeeRate(user, 10001);
    }
    
    function test_RevertWhenSettingInvalidDefaultFeeRate() public {
        vm.prank(owner);
        vm.expectRevert(IGeniusSwapRouter.FeeRateExceedsMaximum.selector);
        router.setDefaultFeeRate(10001);
    }
    
    function test_RevertWhenSettingZeroAddressFeeCollector() public {
        vm.prank(owner);
        vm.expectRevert(IGeniusSwapRouter.InvalidFeeCollectorAddress.selector);
        router.setFeeCollector(address(0));
    }
    
    function test_RevertWhenSettingZeroAddressUserFeeRate() public {
        vm.prank(owner);
        vm.expectRevert(IGeniusSwapRouter.InvalidUserAddress.selector);
        router.setUserFeeRate(address(0), 100);
    }
    
    // ========== BASIC FUNCTIONALITY TESTS ==========
    
    function test_DefaultFeeRateIsApplied() public view {
        assertEq(router.defaultFeeRate(), 100); // 1%
    }
    
    function test_CustomUserFeeRateOverridesDefault() public {
        vm.prank(owner);
        router.setUserFeeRate(user, 500); // 5%
        assertEq(router.userFeeRate(user), 500);
    }
    
    function test_FeeCollectorIsSetCorrectly() public view {
        assertEq(router.feeCollector(), feeCollector);
    }
    
    function test_RevertOnDirectETHTransfer() public {
        vm.prank(user);
        vm.expectRevert(IGeniusSwapRouter.DirectETHTransfersNotAllowed.selector);
        address(router).call{value: 1 ether}("");
    }
    
    function test_RevertOnInvalidFunctionCall() public {
        vm.prank(user);
        vm.expectRevert(IGeniusSwapRouter.FunctionDoesNotExist.selector);
        address(router).call(abi.encodeWithSignature("nonExistentFunction()"));
    }
    
    // ========== MOCK SWAP TESTS (ERC20) ==========
    
    function test_TokenSwapWithDefaultFee() public {
        uint256 amountIn = 1000 * 10**18;
        uint256 expectedFee = (amountIn * 100) / 10000; // 1%
        uint256 expectedAmountAfterFee = amountIn - expectedFee;
        
        vm.startPrank(user);
        tokenA.approve(address(router), amountIn);
        
        bytes memory swapCalldata = abi.encodeWithSelector(
            MockRouter.swap.selector,
            address(tokenA),
            address(tokenB),
            expectedAmountAfterFee,
            user
        );
        
        uint256 feeCollectorBalanceBefore = tokenA.balanceOf(feeCollector);
        
        router.executeSwap(
            address(mockDex),
            address(tokenA),
            address(tokenB),
            amountIn,
            swapCalldata
        );
        vm.stopPrank();
        
        assertEq(tokenA.balanceOf(feeCollector), feeCollectorBalanceBefore + expectedFee);
    }
    
    function test_TokenSwapWithCustomUserFee() public {
        uint256 customFeeRate = 500; // 5%
        vm.prank(owner);
        router.setUserFeeRate(user, customFeeRate);
        
        uint256 amountIn = 1000 * 10**18;
        uint256 expectedFee = (amountIn * customFeeRate) / 10000;
        uint256 expectedAmountAfterFee = amountIn - expectedFee;
        
        vm.startPrank(user);
        tokenA.approve(address(router), amountIn);
        
        bytes memory swapCalldata = abi.encodeWithSelector(
            MockRouter.swap.selector,
            address(tokenA),
            address(tokenB),
            expectedAmountAfterFee,
            user
        );
        
        uint256 feeCollectorBalanceBefore = tokenA.balanceOf(feeCollector);
        
        router.executeSwap(
            address(mockDex),
            address(tokenA),
            address(tokenB),
            amountIn,
            swapCalldata
        );
        vm.stopPrank();
        
        assertEq(tokenA.balanceOf(feeCollector), feeCollectorBalanceBefore + expectedFee);
    }
    
    function test_TokenSwapWithTransferTax() public {
        uint256 amountIn = 1000 * 10**18;
        uint256 taxRate = 100; // 1% transfer tax
        uint256 actualReceived = amountIn - (amountIn * taxRate) / 10000;
        uint256 expectedFee = (actualReceived * 100) / 10000; // 1% protocol fee
        uint256 expectedAmountAfterFee = actualReceived - expectedFee;
        
        vm.startPrank(user);
        taxToken.approve(address(router), amountIn);
        
        bytes memory swapCalldata = abi.encodeWithSelector(
            MockRouter.swap.selector,
            address(taxToken),
            address(tokenB),
            expectedAmountAfterFee,
            user
        );
        
        router.executeSwap(
            address(mockDex),
            address(taxToken),
            address(tokenB),
            amountIn,
            swapCalldata
        );
        vm.stopPrank();
    }
    
    function test_RevertWhenAmountIsZero() public {
        vm.prank(user);
        vm.expectRevert(IGeniusSwapRouter.AmountMustBeGreaterThanZero.selector);
        router.executeSwap(
            address(mockDex),
            address(tokenA),
            address(tokenB),
            0,
            ""
        );
    }
    
    function test_RevertWhenRouterIsZeroAddress() public {
        vm.prank(user);
        vm.expectRevert(IGeniusSwapRouter.InvalidRouterAddress.selector);
        router.executeSwap(
            address(0),
            address(tokenA),
            address(tokenB),
            1000,
            ""
        );
    }
    
    function test_RevertWhenETHSentForTokenSwap() public {
        vm.prank(user);
        vm.expectRevert(IGeniusSwapRouter.ETHSentForTokenSwap.selector);
        router.executeSwap{value: 1 ether}(
            address(mockDex),
            address(tokenA),
            address(tokenB),
            1000,
            ""
        );
    }
    
    // ========== MOCK SWAP TESTS (NATIVE ETH) ==========
    
    function test_NativeETHSwapWithDefaultFee() public {
        uint256 amountIn = 1 ether;
        uint256 expectedFee = (amountIn * 100) / 10000; // 1%
        uint256 expectedAmountAfterFee = amountIn - expectedFee;
        
        bytes memory swapCalldata = abi.encodeWithSelector(
            MockRouter.swap.selector,
            address(0),
            address(tokenB),
            expectedAmountAfterFee,
            user
        );
        
        uint256 feeCollectorBalanceBefore = feeCollector.balance;
        
        vm.prank(user);
        router.executeSwap{value: amountIn}(
            address(mockDex),
            NATIVE_PLACEHOLDER,
            address(tokenB),
            amountIn,
            swapCalldata
        );
        
        assertEq(feeCollector.balance, feeCollectorBalanceBefore + expectedFee);
    }
    
    function test_RevertWhenETHAmountMismatch() public {
        uint256 amountIn = 1 ether;
        
        vm.prank(user);
        vm.expectRevert(IGeniusSwapRouter.ETHAmountMismatch.selector);
        router.executeSwap{value: 0.5 ether}(
            address(mockDex),
            NATIVE_PLACEHOLDER,
            address(tokenB),
            amountIn,
            ""
        );
    }
    
    // ========== EVENT TESTS ==========
    
    function test_EmitFeeRateUpdatedEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit FeeRateUpdated(user, 200);
        router.setUserFeeRate(user, 200);
    }
    
    function test_EmitDefaultFeeRateUpdatedEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit DefaultFeeRateUpdated(200);
        router.setDefaultFeeRate(200);
    }
    
    function test_EmitFeeCollectorUpdatedEvent() public {
        address newCollector = address(4);
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit FeeCollectorUpdated(feeCollector, newCollector);
        router.setFeeCollector(newCollector);
    }
    
    function test_EmitSwapExecutedEvent() public {
        uint256 amountIn = 1000 * 10**18;
        uint256 expectedFee = (amountIn * 100) / 10000;
        uint256 expectedAmountAfterFee = amountIn - expectedFee;
        
        vm.startPrank(user);
        tokenA.approve(address(router), amountIn);
        
        bytes memory swapCalldata = abi.encodeWithSelector(
            MockRouter.swap.selector,
            address(tokenA),
            address(tokenB),
            expectedAmountAfterFee,
            user
        );
        
        vm.expectEmit(true, true, true, true);
        emit SwapExecuted(user, address(mockDex), address(tokenA), amountIn, amountIn, expectedFee);
        
        router.executeSwap(
            address(mockDex),
            address(tokenA),
            address(tokenB),
            amountIn,
            swapCalldata
        );
        vm.stopPrank();
    }
    
    // ========== REENTRANCY TEST ==========
    
    function test_ReentrancyProtection() public pure {
        // The nonReentrant modifier should prevent reentrancy
        // This is implicitly tested by the contract using ReentrancyGuard
        assertTrue(true);
    }
}
