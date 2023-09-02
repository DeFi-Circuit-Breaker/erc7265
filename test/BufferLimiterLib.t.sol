// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {Buffer, BufferLib} from "../src/limiter/BufferLimiterLib.sol";
import {console2 as console} from "forge-std/console2.sol";

/// @author philogy <https://github.com/philogy>
contract BufferLimtierLibTest is Test {
    Buffer internal buffer;
    uint256 tvl;

    uint256 internal constant MAIN_WINDOW = 1 days;
    uint256 internal constant ELASTIC_WINDOW = 10 minutes;
    uint256 internal constant MAX_DRAW = 0.05e18;

    function setUp() public {
        buffer.lastUpdatedAt = block.timestamp;
    }

    function testPass() public {
        _inflow(10e18);
        print();

        skip(3 minutes);
        _update();
        print();

        skip(10 minutes);
        _outflow(0.5e18);
        print();

        skip(1 minutes);
        _inflow(5.1e18);
        print();
        _outflow(2.5e18);
        print();
        _outflow(2.5e18);
        print();
    }

    function _update() internal {
        buffer.update({mainWindow: MAIN_WINDOW, elasticWindow: ELASTIC_WINDOW, time: block.timestamp});
    }

    function _inflow(uint256 amount) internal {
        buffer.recordInflow({
            mainWindow: MAIN_WINDOW,
            elasticWindow: ELASTIC_WINDOW,
            time: block.timestamp,
            preTvl: tvl,
            amount: amount
        });
        tvl += amount;
    }

    function _outflow(uint256 amount) internal {
        if (
            buffer.recordOutflow({
                maxDrawWad: MAX_DRAW,
                mainWindow: MAIN_WINDOW,
                elasticWindow: ELASTIC_WINDOW,
                time: block.timestamp,
                preTvl: tvl,
                amount: amount
            })
        ) {
            tvl -= amount;
        } else {
            console.log("!!! LIMIT HIT !!!");
            emit log_named_decimal_uint("  amount", amount, 18);
        }
    }

    function print() public {
        console.log("Buffer (t: %d)", block.timestamp);
        console.log("  last updated: %d", buffer.lastUpdatedAt);
        emit log_named_decimal_uint("  TVL         ", tvl, 18);
        emit log_named_decimal_uint("  main used   ", buffer.mainUsedWad, 18);
        emit log_named_decimal_uint("  elastic used", buffer.elasticBufferWad, 18);
    }
}
