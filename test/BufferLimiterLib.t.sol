// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {abs} from "src/utils/Math.sol";
import {BufferLib, Buffer, BufferResult} from "src/limiter/BufferLimiterLib.sol";
import {console2 as console} from "forge-std/console2.sol";

/// @author philogy <https://github.com/philogy>
contract BufferLimtierLibTest is Test {
    using SafeCastLib for uint256;

    Buffer internal buffer;

    uint256 tvl;

    uint256 internal constant MAIN_WINDOW = 1 days;
    uint256 internal constant ELASTIC_WINDOW = 10 minutes;
    int256 internal constant MAX_DRAW = -0.05e18;

    function setUp() public {
        buffer = BufferLib.newBuffer(block.timestamp);
        print("init");
    }

    function testPass() public {
        _inflow(10e18);
        print("1");

        skip(3 minutes);
        _update();
        print("2");

        skip(10 minutes);
        _outflow(0.5e18);
        print("3");

        skip(1 minutes);
        _update();
        print("4");
        _inflow(5.1e18);
        print("_inflow(5.1e18)");
        _outflow(2.5e18);
        print("_outflow(2.5e18) 1/2");
        _outflow(2.6e18);
        print("_outflow(2.5e18) 2/2");
    }

    function testInflows() public {
        _inflow(10e18);
        print("1");

        skip(20 minutes);

        _inflow(50e18);
        print("2");
    }

    function testInflows_2() public {
        _inflow(10e18);
        skip(10 minutes);

        _outflow(0.5e18);
        print("1");

        _inflow(40e18);
        print("2");
    }

    function _update() internal {
        buffer = buffer.update({mainWindow: MAIN_WINDOW, elasticWindow: ELASTIC_WINDOW, time: block.timestamp});
    }

    function _inflow(uint256 amount) internal {
        buffer = buffer.recordFlow({
            maxDrawWad: MAX_DRAW,
            mainWindow: MAIN_WINDOW,
            elasticWindow: ELASTIC_WINDOW,
            time: block.timestamp,
            reserves: tvl,
            flow: amount.toInt256()
        }).unwrap();
        tvl += amount;
    }

    function _outflow(uint256 amount) internal {
        BufferResult result = buffer.recordFlow({
            maxDrawWad: MAX_DRAW,
            mainWindow: MAIN_WINDOW,
            elasticWindow: ELASTIC_WINDOW,
            time: block.timestamp,
            reserves: tvl,
            flow: -amount.toInt256()
        });

        if (!result.isErr()) {
            tvl -= amount;
            buffer = result.unwrap();
        } else {
            console.log("!!! LIMIT HIT !!!");
            emit log_named_decimal_uint("  amount", amount, 18);
        }
    }

    function print() public {
        print("");
    }

    function print(string memory name) public {
        (uint256 lastUpdatedAt, uint256 mainUsedWad, uint256 elasticBufferWad) = buffer.unpack();
        console.log("Buffer \"%s\" (t: %d)", name, block.timestamp);
        console.log("  last updated: %d", lastUpdatedAt);
        emit log_named_decimal_uint("  TVL         ", tvl, 18);
        emit log_named_decimal_uint("  main        ", mainUsedWad, 18);
        emit log_named_decimal_uint("  elastic     ", elasticBufferWad, 18);
        (int256 maxMainFlow, uint256 maxElasticDeplete) = buffer.getMaxFlow(MAX_DRAW, tvl);
        uint256 maxOut = abs(maxMainFlow) + maxElasticDeplete;
        emit log_named_decimal_uint("  max out     ", maxOut, 18);
    }
}
