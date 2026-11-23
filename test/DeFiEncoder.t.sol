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

    uint256 private constant ADDRESS_SIZE = 20; // address: 20 bytes in encodePacked
    uint256 private constant WORD_SIZE = 32; // uint256 / bytes32 : 32 bytes

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

    function testFuzz_CreatePoolIdentifier_SameIdForBothTokenOrders(address tokenA, address tokenB, uint24 fee)
        public
        view
    {
        bytes32 idAB = encoder.createPoolIdentifier(tokenA, tokenB, fee);
        bytes32 idBA = encoder.createPoolIdentifier(tokenB, tokenA, fee);

        assertEq(idAB, idBA);
    }

    function testFuzz_CreatePoolIdentifier_DifferentFeeDifferentId(
        address tokenA,
        address tokenB,
        uint24 fee1,
        uint24 fee2
    ) public view {
        vm.assume(fee1 != fee2);

        bytes32 id1 = encoder.createPoolIdentifier(tokenA, tokenB, fee1);
        bytes32 id2 = encoder.createPoolIdentifier(tokenB, tokenA, fee2);

        assertNotEq(id1, id2);
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

    function test_EncodeTradingPosition_SameBlockSameParamsSameId() public {
        address user = address(0x1234);
        address tokenIn = address(0xA1);
        address tokenOut = address(0xB2);
        uint256 amountIn = 1 ether;
        uint256 amountOut = 2 ether;

        uint256 fixTimestamp = 1_700_000_000;
        vm.warp(fixTimestamp);

        (bytes32 positionId1,) = encoder.encodeTradingPosition(user, tokenIn, tokenOut, amountIn, amountOut);
        (bytes32 positionId2,) = encoder.encodeTradingPosition(user, tokenIn, tokenOut, amountIn, amountOut);

        // position Id is not unique: same params give the same id
        assertEq(positionId1, positionId2);
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

    function test_EncodeSwapData_RevertWhen_LengthMismatch() public {
        address[] memory path = new address[](2);
        path[0] = address(0x1);
        path[1] = address(0x2);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;

        uint256 deadline = 999;

        vm.expectRevert(DeFiEncoder.InvalidLength.selector);
        encoder.encodeSwapData(path, amounts, deadline);
    }

    function testFuzz_EncodeSwapData_LengthIsFixedByArraySize(uint8 arraySize, uint256 seed, uint256 deadline)
        public
        view
    {
        arraySize = uint8(bound(arraySize, 0, 16));

        address[] memory path = new address[](arraySize);
        uint256[] memory amounts = new uint256[](arraySize);

        for (uint256 i = 0; i < arraySize; i++) {
            path[i] = address(bytes20(keccak256(abi.encode(seed, i))));
            amounts[i] = uint256(keccak256(abi.encode(seed, i)));
        }

        bytes memory swapData = encoder.encodeSwapData(path, amounts, deadline);

        assertEq(swapData.length, arraySize * (ADDRESS_SIZE + WORD_SIZE) + WORD_SIZE);
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

    function testFuzz_EncodeLimitOrder_EncodesFuzzedFields(
        address maker,
        address taker,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 nonce
    ) public view {
        (bytes32 orderHash, bytes memory orderData) =
            encoder.encodeLimitOrder(maker, taker, tokenIn, tokenOut, amountIn, amountOut, nonce);

        bytes memory expected =
            abi.encodePacked(maker, taker, tokenIn, tokenOut, amountIn, amountOut, nonce, "LIMIT_ORDER_V1");

        assertEq(orderData, expected);
        assertEq(orderData.length, 4 * ADDRESS_SIZE + 3 * WORD_SIZE + 14);
        assertEq(orderHash, keccak256(expected));
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

    function test_EncodeFlashLoan_EncodesFieldsInOrder() public {
        address token = makeAddr("token");
        uint256 amount = 1 ether;
        bytes memory callbackData = hex"deadbeef";

        bytes memory flashData = encoder.encodeFlashLoan(token, amount, callbackData);

        bytes memory expected = abi.encodePacked(token, amount, callbackData, "FLASH_LOAN_V1");

        assertEq(flashData, expected);
        // token + amount + callbackData + len("FLASH_LOAN_V1")
        assertEq(flashData.length, ADDRESS_SIZE + WORD_SIZE + callbackData.length + 13);
    }

    function test_EncodeFlashLoan_EmptyCallbackData() public {
        address token = makeAddr("token");
        uint256 amount = 1 ether;
        bytes memory callbackData = "";

        bytes memory flashData = encoder.encodeFlashLoan(token, amount, callbackData);

        bytes memory expected = abi.encodePacked(token, amount, callbackData, "FLASH_LOAN_V1");

        assertEq(flashData, expected);
        // token + amount + callbackData + len("FLASH_LOAN_V1")
        assertEq(flashData.length, ADDRESS_SIZE + WORD_SIZE + callbackData.length + 13);
    }

    function testFuzz_EncodeFlashLoan_LengthMatchesCallbackData(bytes memory callbackData) public {
        address token = makeAddr("token");
        uint256 amount = 1 ether;
        bytes memory flashData = encoder.encodeFlashLoan(token, amount, callbackData);

        bytes memory expected = abi.encodePacked(token, amount, callbackData, "FLASH_LOAN_V1");

        assertEq(flashData, expected);
        assertEq(flashData.length, ADDRESS_SIZE + WORD_SIZE + callbackData.length + 13);
    }

    function testFuzz_EncodeFlashLoan_DifferentCallbackDifferentOutput(
        bytes memory callbackDataA,
        bytes memory callbackDataB
    ) public {
        vm.assume(keccak256(callbackDataA) != keccak256(callbackDataB));

        address token = makeAddr("token");
        uint256 amount = 1 ether;

        bytes memory flashDataA = encoder.encodeFlashLoan(token, amount, callbackDataA);
        bytes memory flashDataB = encoder.encodeFlashLoan(token, amount, callbackDataB);

        assertNotEq(flashDataA, flashDataB);
    }

    function test_EncodeStakingPoolConfig_EncodesFieldsInOrder() public {
        address token = makeAddr("token");
        uint256 rewardRate = 10;
        uint256 lockPeriod = 1_000_000;
        uint256 maxStakers = 5;
        uint256 timestamp = 1_700_000_000;

        vm.warp(timestamp);

        bytes memory poolConfig = encoder.encodeStakingPoolConfig(token, rewardRate, lockPeriod, maxStakers);

        bytes memory expected = abi.encodePacked(token, rewardRate, lockPeriod, maxStakers, timestamp);

        assertEq(poolConfig, expected);
    }

    function test_EncodeStakingPoolConfig_SameBlockSameOutput() public {
        address token = makeAddr("token");
        uint256 rewardRate = 10;
        uint256 lockPeriod = 1_000_000;
        uint256 maxStakers = 5;

        vm.warp(1_700_000_000);

        bytes memory first = encoder.encodeStakingPoolConfig(token, rewardRate, lockPeriod, maxStakers);
        bytes memory second = encoder.encodeStakingPoolConfig(token, rewardRate, lockPeriod, maxStakers);

        assertEq(first, second);
    }

    function test_EncodeStakingPoolConfig_DifferentTimestampDifferentOutput() public {
        address token = makeAddr("token");
        uint256 rewardRate = 10;
        uint256 lockPeriod = 1_000_000;
        uint256 maxStakers = 5;

        vm.warp(block.timestamp + 100);
        bytes memory first = encoder.encodeStakingPoolConfig(token, rewardRate, lockPeriod, maxStakers);

        skip(100);
        bytes memory second = encoder.encodeStakingPoolConfig(token, rewardRate, lockPeriod, maxStakers);

        assertNotEq(first, second);
    }

    function testFuzz_EncodeStakingPoolConfig_EmbedsTimestamp(uint256 timestamp) public {
        address token = makeAddr("token");
        uint256 rewardRate = 10;
        uint256 lockPeriod = 1_000_000;
        uint256 maxStakers = 5;

        vm.warp(timestamp);

        bytes memory poolConfig = encoder.encodeStakingPoolConfig(token, rewardRate, lockPeriod, maxStakers);
        bytes memory expected = abi.encodePacked(token, rewardRate, lockPeriod, maxStakers, timestamp);

        assertEq(poolConfig, expected);
    }

    function test_CreateUserMultiPoolHash_EncodesUserAndPoolIds() public {
        address user = makeAddr("user");
        bytes32[] memory poolIds = new bytes32[](3);
        poolIds[0] = keccak256("pool1");
        poolIds[1] = keccak256("pool2");
        poolIds[2] = keccak256("pool3");

        bytes32 userHash = encoder.createUserMultiPoolHash(user, poolIds);

        bytes memory poolData = abi.encodePacked(user);
        for (uint256 i = 0; i < poolIds.length; i++) {
            poolData = abi.encodePacked(poolData, poolIds[i]);
        }
        bytes32 expected = keccak256(abi.encodePacked(poolData, "MULTI_POOL_USER"));

        assertEq(userHash, expected);
    }

    function test_CreateUserMultiPoolHash_NoPools() public {
        address user = makeAddr("user");
        bytes32[] memory poolIds = new bytes32[](0);

        bytes32 userHash = encoder.createUserMultiPoolHash(user, poolIds);

        bytes memory poolData = abi.encodePacked(user);
        bytes32 expected = keccak256(abi.encodePacked(poolData, "MULTI_POOL_USER"));

        assertEq(userHash, expected);
    }

    function test_CreateUserMultiPoolHash_PoolOrderChangesHash() public {
        address user = makeAddr("user");
        bytes32[] memory poolIdsFirst = new bytes32[](3);
        poolIdsFirst[0] = keccak256("pool1");
        poolIdsFirst[1] = keccak256("pool2");
        poolIdsFirst[2] = keccak256("pool3");

        // Different Order on the pool
        bytes32[] memory poolIdsSecond = new bytes32[](3);
        poolIdsSecond[0] = keccak256("pool3");
        poolIdsSecond[1] = keccak256("pool1");
        poolIdsSecond[2] = keccak256("pool2");

        bytes32 userHashFirst = encoder.createUserMultiPoolHash(user, poolIdsFirst);
        bytes32 userHashSecond = encoder.createUserMultiPoolHash(user, poolIdsSecond);

        assertNotEq(userHashFirst, userHashSecond);
    }

    function test_EncodeYieldStrategyPacked_EncodesFieldsInOrder() public {
        string memory strategyName = "name";
        address[] memory pools = new address[](3);
        pools[0] = makeAddr("pool0");
        pools[1] = makeAddr("pool1");
        pools[2] = makeAddr("pool2");
        uint256[] memory weights = new uint256[](3);
        weights[0] = 10;
        weights[1] = 20;
        weights[2] = 30;

        bytes memory strategyData = encoder.encodeYieldStrategyPacked(strategyName, pools, weights);

        bytes memory nameData = abi.encodePacked(strategyName);

        bytes memory poolsData;
        for (uint256 i = 0; i < pools.length; i++) {
            poolsData = abi.encodePacked(poolsData, pools[i]);
        }

        bytes memory weightsData;
        for (uint256 i = 0; i < weights.length; i++) {
            weightsData = abi.encodePacked(weightsData, weights[i]);
        }

        bytes memory expected = abi.encodePacked(nameData, poolsData, weightsData, "YIELD_STRATEGY_V1");

        assertEq(strategyData, expected);
    }

    function test_EncodeYieldStrategyPacked_NoPools() public view {
        string memory strategyName = "name";
        address[] memory pools = new address[](0);
        uint256[] memory weights = new uint256[](0);

        bytes memory strategyData = encoder.encodeYieldStrategyPacked(strategyName, pools, weights);

        bytes memory nameData = abi.encodePacked(strategyName);
        bytes memory poolsData;
        bytes memory weightsData;
        bytes memory expected = abi.encodePacked(nameData, poolsData, weightsData, "YIELD_STRATEGY_V1");

        assertEq(strategyData, expected);
    }

    function test_EncodeYieldStrategyPacked_RevertWhen_LengthMismatch() public {
        string memory strategyName = "name";
        address[] memory pools = new address[](2);
        pools[0] = makeAddr("pool0");
        pools[1] = makeAddr("pool1");
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10;

        vm.expectRevert(DeFiEncoder.InvalidLength.selector);
        encoder.encodeYieldStrategyPacked(strategyName, pools, weights);
    }

    function test_EncodeYieldStrategyPacked_CollisionBetweenNameAndPool() public {
        address pool = makeAddr("pool");
        uint256 weight = 100;

        string memory nameA = string(bytes.concat(bytes20(pool), bytes32(weight)));
        address[] memory poolsA = new address[](0);
        uint256[] memory weightsA = new uint256[](0);

        string memory nameB = "";
        address[] memory poolsB = new address[](1);
        poolsB[0] = pool;
        uint256[] memory weightsB = new uint256[](1);
        weightsB[0] = weight;

        bytes memory dataA = encoder.encodeYieldStrategyPacked(nameA, poolsA, weightsA);
        bytes memory dataB = encoder.encodeYieldStrategyPacked(nameB, poolsB, weightsB);

        // VULNERABLE BY DESIGN: different inputs, same bytes, same hash
        assertNotEq(poolsA.length, poolsB.length);
        assertEq(dataA, dataB);
        assertEq(keccak256(dataA), keccak256(dataB));
    }

    function testFuzz_EncodeYieldStrategyPacked_CollisionForAnyPoolAndWeight(
        string memory prefix,
        address pool,
        uint256 weight
    ) public view {
        string memory nameA = string(bytes.concat(bytes(prefix), bytes20(pool), bytes32(weight)));
        address[] memory poolsA = new address[](0);
        uint256[] memory weightsA = new uint256[](0);

        string memory nameB = prefix;
        address[] memory poolsB = new address[](1);
        poolsB[0] = pool;
        uint256[] memory weightsB = new uint256[](1);
        weightsB[0] = weight;

        bytes memory dataA = encoder.encodeYieldStrategyPacked(nameA, poolsA, weightsA);
        bytes memory dataB = encoder.encodeYieldStrategyPacked(nameB, poolsB, weightsB);

        // VULNERABLE BY DESIGN: for any input, pool and weight, two different inputs produce the same bytes and same hash
        assertNotEq(poolsA.length, poolsB.length);
        assertEq(dataA, dataB);
        assertEq(keccak256(dataA), keccak256(dataB));
    }

    function test_EncodeYieldStrategyEncoded_NoCollisionBetweenNameAndPool() public {
        address pool = makeAddr("pool");
        uint256 weight = 100;

        // Same inputs that collide in encodeYieldStrategyPacked
        string memory nameA = string(bytes.concat(bytes20(pool), bytes32(weight)));
        address[] memory poolsA = new address[](0);
        uint256[] memory weightsA = new uint256[](0);

        string memory nameB = "";
        address[] memory poolsB = new address[](1);
        poolsB[0] = pool;
        uint256[] memory weightsB = new uint256[](1);
        weightsB[0] = weight;

        bytes memory dataA = encoder.encodeYieldStrategyEncoded(nameA, poolsA, weightsA);
        bytes memory dataB = encoder.encodeYieldStrategyEncoded(nameB, poolsB, weightsB);

        // Unlike the packed version, different inputs give different bytes and hashes
        assertNotEq(poolsA.length, poolsB.length);
        assertNotEq(dataA, dataB);
        assertNotEq(keccak256(dataA), keccak256(dataB));
    }

    function test_EncodeYieldStrategyEncoded_DecodesBackToInputs() public {
        string memory name = "name";
        address[] memory pools = new address[](2);
        pools[0] = makeAddr("pool1");
        pools[1] = makeAddr("pool2");
        uint256[] memory weights = new uint256[](2);
        weights[0] = 100;
        weights[1] = 200;

        bytes memory data = encoder.encodeYieldStrategyEncoded(name, pools, weights);
        (string memory nameDecoded, address[] memory poolsDecoded, uint256[] memory weightsDecoded) =
            abi.decode(data, (string, address[], uint256[]));

        assertEq(name, nameDecoded);
        assertEq(pools, poolsDecoded);
        assertEq(weights, weightsDecoded);
    }

    function testFuzz_EncodeYieldStrategyEncoded_NoCollisionForAnyPoolAndWeight(
        string memory prefix,
        address pool,
        uint256 weight
    ) public view {
        string memory nameA = string(bytes.concat(bytes(prefix), bytes20(pool), bytes32(weight)));
        address[] memory poolsA = new address[](0);
        uint256[] memory weightsA = new uint256[](0);

        string memory nameB = prefix;
        address[] memory poolsB = new address[](1);
        poolsB[0] = pool;
        uint256[] memory weightsB = new uint256[](1);
        weightsB[0] = weight;

        bytes memory dataA = encoder.encodeYieldStrategyEncoded(nameA, poolsA, weightsA);
        bytes memory dataB = encoder.encodeYieldStrategyEncoded(nameB, poolsB, weightsB);

        assertNotEq(poolsA.length, poolsB.length);
        assertNotEq(dataA, dataB);
        assertNotEq(keccak256(dataA), keccak256(dataB));
    }

    function test_EncodeYieldStrategyEncoded_RevertWhen_LengthMismatch() public {
        string memory strategyName = "name";
        address[] memory pools = new address[](2);
        pools[0] = makeAddr("pool0");
        pools[1] = makeAddr("pool1");
        uint256[] memory weights = new uint256[](1);
        weights[0] = 10;

        vm.expectRevert(DeFiEncoder.InvalidLength.selector);
        encoder.encodeYieldStrategyEncoded(strategyName, pools, weights);
    }

    function test_EncodeCrossChainBridgeData_EncodesFieldsInOrder() public {
        uint256 sourceChain = 100;
        uint256 targetChain = 200;
        address token = makeAddr("token");
        uint256 amount = 1 ether;
        address recipient = makeAddr("recipient");

        bytes memory bridgeData = encoder.encodeCrossChainBridgeData(sourceChain, targetChain, token, amount, recipient);
        bytes memory expected =
            abi.encodePacked(sourceChain, targetChain, token, amount, recipient, "CROSS_CHAIN_BRIDGE");

        assertEq(bridgeData, expected);
        // 3 uint256 + 2 addresses + len("CROSS_CHAIN_BRIDGE")
        assertEq(bridgeData.length, 3 * WORD_SIZE + 2 * ADDRESS_SIZE + 18);
    }

    function test_CreateDeFiTransactionId_ReturnsExpectedHash() public {
        string memory txType = "demo";
        address user = makeAddr("user");
        uint256 timestamp = 1_700_000_000;
        uint256 nonce = 7;

        bytes32 txId = encoder.createDeFiTransactionId(txType, user, timestamp, nonce);
        bytes memory expected = abi.encodePacked(txType, user, timestamp, nonce, "DEFI_TX");

        assertEq(txId, keccak256(expected));
    }

    function test_CreateDeFiTransactionId_EmptyTxType() public {
        string memory txType = "";
        address user = makeAddr("user");
        uint256 timestamp = 1_700_000_000;
        uint256 nonce = 7;

        bytes32 txId = encoder.createDeFiTransactionId(txType, user, timestamp, nonce);
        bytes memory expected = abi.encodePacked(txType, user, timestamp, nonce, "DEFI_TX");

        assertEq(txId, keccak256(expected));
    }

    function testFuzz_CreateDeFiTransactionId_DifferentTxTypeDifferentId(
        string memory txTypeA,
        string memory txTypeB,
        address user,
        uint256 timestamp,
        uint256 nonce
    ) public view {
        vm.assume(keccak256(bytes(txTypeA)) != keccak256(bytes(txTypeB)));

        bytes32 txIdA = encoder.createDeFiTransactionId(txTypeA, user, timestamp, nonce);
        bytes32 txIdB = encoder.createDeFiTransactionId(txTypeB, user, timestamp, nonce);

        assertNotEq(txIdA, txIdB);
    }

    function test_EncodeStopLossOrder_EncodeFieldsInOrder() public {
        address user = makeAddr("user");
        address token = makeAddr("token");
        uint256 amount = 1 ether;
        uint256 stopPrice = 100;
        uint256 triggerPrice = 50;

        bytes memory stopLossData = encoder.encodeStopLossOrder(user, token, amount, stopPrice, triggerPrice);
        bytes memory expected = abi.encodePacked(user, token, amount, stopPrice, triggerPrice, "STOP_LOSS_ORDER");

        assertEq(stopLossData, expected);
        // 3 uint256 + 2 addresses + len("STOP_LOSS_ORDER")
        assertEq(stopLossData.length, 3 * WORD_SIZE + 2 * ADDRESS_SIZE + 15);
    }

    function test_EncodeTakeProfitOrder_EncodeFieldsInOrder() public {
        address user = makeAddr("user");
        address token = makeAddr("token");
        uint256 amount = 1 ether;
        uint256 takeProfitPrice = 50;

        bytes memory takeProfitData = encoder.encodeTakeProfitOrder(user, token, amount, takeProfitPrice);
        bytes memory expected = abi.encodePacked(user, token, amount, takeProfitPrice, "TAKE_PROFIT_ORDER");

        assertEq(takeProfitData, expected);
        // 2 uint256 + 2 addresses + len("TAKE_PROFIT_ORDER")
        assertEq(takeProfitData.length, 2 * WORD_SIZE + 2 * ADDRESS_SIZE + 17);
    }

    function test_EncodeTrailingStopOrder_EncodeFieldsInOrder() public {
        address user = makeAddr("user");
        address token = makeAddr("token");
        uint256 amount = 1 ether;
        uint256 trailingPercent = 10;
        uint256 activationPrice = 100;

        bytes memory trailingStopData =
            encoder.encodeTrailingStopOrder(user, token, amount, trailingPercent, activationPrice);
        bytes memory expected =
            abi.encodePacked(user, token, amount, trailingPercent, activationPrice, "TRAILING_STOP_ORDER");

        assertEq(trailingStopData, expected);
        // 3 uint256 + 2 addresses + len("TRAILING_STOP_ORDER")
        assertEq(trailingStopData.length, 3 * WORD_SIZE + 2 * ADDRESS_SIZE + 19);
    }
}
