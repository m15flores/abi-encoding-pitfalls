// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "../src/DeFiEncoder.sol";

/**
 * @title DeFiEncoderTest
 * @notice Comprehensive test targeting 100% coverage for DeFiEncoder
 */
contract DeFiEncoderTest is Test {
    DeFiEncoder encoder;

    /**
     * @dev Deploy a fresh contract before each test
     */
    function setUp() public {
        encoder = new DeFiEncoder();
    }

    /**
     * @dev Pool id must be invariant to token ordering (tokens are sorted internally)
     */
    function test_CreatePoolIdentifierSameForBothTokenOrders() public view {
        address tokenA = address(0x100);
        address tokenB = address(0x200);
        uint24 fee = 3000;

        bytes32 idAB = encoder.createPoolIdentifier(tokenA, tokenB, fee);
        bytes32 idBA = encoder.createPoolIdentifier(tokenB, tokenA, fee);

        assertEq(idAB, idBA, "Tokens are not correctly sorted.");
    }

    function test_CreatePoolIdentifier_DifferentFeeDifferentId() public view {
        address tokenA = address(0x100);
        address tokenB = address(0x200);
        uint24 fee0 = 3000;
        uint24 fee1 = 5000;

        bytes32 idLow = encoder.createPoolIdentifier(tokenA, tokenB, fee0);
        bytes32 idHigh = encoder.createPoolIdentifier(tokenB, tokenA, fee1);

        assertTrue(idLow != idHigh, "Different fees must yield different ids.");
    }

    function test_EncodeTradingPosition_ReturnsExpectedDataAndHash() public {
        address user = address(0x1234);
        address tokenIn = address(0xA1);
        address tokenOut = address(0xB2);
        uint256 amountIn = 1 ether;
        uint256 amountOut = 2 ether;

        // Freeze block timestamp to a known value
        uint256 fixTimestamp = 1_700_000_000;
        vm.warp(fixTimestamp);

        (bytes32 positionId, bytes memory encodedData) =
            encoder.encodeTradingPosition(user, tokenIn, tokenOut, amountIn, amountOut);

        bytes memory expected = abi.encodePacked(user, tokenIn, tokenOut, amountIn, amountOut, fixTimestamp);

        assertEq(encodedData, expected, "Encoded trading position missmatch.");
        assertEq(positionId, keccak256(expected), "PositionId must be keccak of encodedData.");
    }

    function test_EncodeSwapData_EncodesPathAmountsDeadline() public view {
        address[] memory path = new address[](3);
        path[0] = address(0x1);
        path[1] = address(0x2);
        path[2] = address(0x3);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10;
        amounts[1] = 20;
        amounts[2] = 30;

        uint256 deadline = 999;

        bytes memory pathData;
        for (uint256 i = 0; i < path.length; i++) {
            pathData = abi.encodePacked(pathData, path[i]);
        }

        bytes memory amountsData;
        for (uint256 i = 0; i < amounts.length; i++) {
            amountsData = abi.encodePacked(amountsData, amounts[i]);
        }

        bytes memory expected = abi.encodePacked(pathData, amountsData, deadline);
        bytes memory actual = encoder.encodeSwapData(path, amounts, deadline);

        assertEq(expected, actual, "Swap data encoding missmatch.");
    }

    function test_EncodeSwapData_RevertsOnLengthMissmatch() public {
        address[] memory path = new address[](2);
        path[0] = address(0x1);
        path[1] = address(0x2);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;

        uint256 deadline = 999;

        vm.expectRevert(DeFiEncoder.InvalidLength.selector);
        encoder.encodeSwapData(path, amounts, deadline);
    }

    function test_EncodeLimitOrder_EncodesFieldsInOrder() public {
        address maker = makeAddr("maker");
        address taker = makeAddr("taker");
        address tokenIn = makeAddr("tokenIn");
        address tokenOut = makeAddr("tokenOut");
        uint256 amountIn = 1 ether;
        uint256 amountOut = 2 ether;
        uint256 nonce = 7;

        (bytes32 orderHash, bytes memory orderData) =
            encoder.encodeLimitOrder(maker, taker, tokenIn, tokenOut, amountIn, amountOut, nonce);

        bytes memory expected =
            abi.encodePacked(maker, taker, tokenIn, tokenOut, amountIn, amountOut, nonce, "LIMIT_ORDER_V1");

        assertEq(orderData, expected);
        assertEq(orderData.length, expected.length);
        assertEq(orderHash, keccak256(expected));
    }

    function test_EncodeLimitOrder_DifferentNonceDifferentHash() public {
        address maker = makeAddr("maker");
        address taker = makeAddr("taker");
        address tokenIn = makeAddr("tokenIn");
        address tokenOut = makeAddr("tokenOut");
        uint256 amountIn = 1 ether;
        uint256 amountOut = 2 ether;
        uint256 nonce1 = 7;
        uint256 nonce2 = 8;

        (bytes32 orderHash1,) = encoder.encodeLimitOrder(maker, taker, tokenIn, tokenOut, amountIn, amountOut, nonce1);
        (bytes32 orderHash2,) = encoder.encodeLimitOrder(maker, taker, tokenIn, tokenOut, amountIn, amountOut, nonce2);

        assertNotEq(orderHash1, orderHash2);
    }

    function test_EncodeYieldPosition_ReturnsExpectedHash() public {
        address user = makeAddr("user");
        bytes32 poolId = keccak256("pool");
        uint256 amount = 1 ether;
        uint256 startTime = 1_700_000_000;

        bytes32 positionId = encoder.encodeYieldPosition(user, poolId, amount, startTime);

        bytes memory expected =
            bytes.concat(bytes20(user), poolId, bytes32(amount), bytes32(startTime), bytes("YIELD_POSITION"));

        assertEq(positionId, keccak256(expected));
    }

    function test_EncodeYieldPosition_DifferentUserDifferentId() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        bytes32 poolId = keccak256("pool");
        uint256 amount = 1 ether;
        uint256 startTime = 1_700_000_000;

        bytes32 id1 = encoder.encodeYieldPosition(user1, poolId, amount, startTime);
        bytes32 id2 = encoder.encodeYieldPosition(user2, poolId, amount, startTime);

        assertNotEq(id1, id2);
    }
}
