// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {abs, sign, signNeg} from "src/utils/Math.sol";
import {LimiterConfigLib, LimiterConfig} from "src/limiter/LimiterConfigLib.sol";
import {DecreaseLimiterLib, DecreaseLimiter, DecreaseResult} from "src/limiter/DecreaseLimiterLib.sol";
import {console2 as console} from "forge-std/console2.sol";

/// @author philogy <https://github.com/philogy>
contract BufferLimtierLibTest is Test {
    using SafeCastLib for uint256;
    using SafeCastLib for int256;

    LimiterConfig internal config =
        LimiterConfigLib.initNew({maxDrawWad: 0.05e18, mainWindow: 1 days, elasticWindow: 10 minutes});
    DecreaseLimiter internal limiter;

    uint256 tvl;

    function setUp() public {
        limiter = DecreaseLimiterLib.initNew(block.timestamp);
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

    function testInflow_profit() public {
        _inflow(10e18);
        skip(config.getMainWindow());

        _update();
        print("1");

        _inflow(1000e18);
        print("2");

        tvl += 10e18;
        print("2.1");
    }

    function _update() internal {
        limiter = limiter.update(config);
    }

    function _inflow(uint256 amount) internal {
        int256 flow = amount.toInt256();
        limiter = limiter.recordFlow(config, tvl, flow).unwrap();
        _applyTvlChange(flow);
    }

    function _outflow(uint256 amount) internal {
        _handleFlow(-amount.toInt256());
    }

    function _handleFlow(int256 flow) internal {
        if ((flow < 0) == (config.getMaxDrawWad() < 0)) {
            DecreaseResult result = limiter.recordFlow(config, tvl, flow);

            if (result.isOk()) {
                _applyTvlChange(flow);
                limiter = result.unwrap();
            } else {
                console.log("!!! LIMIT HIT !!!");
                emit log_named_decimal_int("  flow", flow, 18);
                fail();
            }
        } else {}
    }

    function print() public {
        print("");
    }

    function print(string memory name) public {
        (uint256 lastUpdatedAt, uint256 mainUsedWad, uint256 elasticBufferWad) = limiter.unpack();
        console.log("Limiter \"%s\" (t: %d)", name, block.timestamp);
        console.log("  last updated: %d", lastUpdatedAt);
        emit log_named_decimal_uint("  TVL         ", tvl, 18);
        emit log_named_decimal_uint("  main        ", mainUsedWad, 18);
        emit log_named_decimal_uint("  elastic     ", elasticBufferWad, 18);
        (uint256 maxMainFlow, uint256 maxElasticDeplete) = limiter.getMaxFlow(config, tvl);
        uint256 maxOut = maxMainFlow + maxElasticDeplete;
        emit log_named_decimal_uint("  max out     ", maxOut, 18);
    }

    function _applyTvlChange(int256 delta) internal {
        tvl = (tvl.toInt256() + delta).toUint256();
    }
}
