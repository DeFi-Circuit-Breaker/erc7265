// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {SafeCastLib} from "solady/src/utils/SafeCastLib.sol";
import {abs, sign, signNeg} from "src/utils/Math.sol";
import {LimiterConfigLib, LimiterConfig} from "src/limiter/LimiterConfigLib.sol";
import {DecreaseLimiterLib, DecreaseLimiter} from "src/limiter/DecreaseLimiterLib.sol";
import {console2 as console} from "forge-std/console2.sol";

/// @author philogy <https://github.com/philogy>
contract DecreaseLimiterLibTest is Test {
    using SafeCastLib for uint256;
    using SafeCastLib for int256;

    LimiterConfig internal config =
        LimiterConfigLib.initNew({maxDrawWad: 0.05e18, mainWindow: 1 days, elasticWindow: 10 minutes});
    DecreaseLimiter internal limiter;

    uint256 tvl;

    function setUp() public {
        limiter = DecreaseLimiterLib.initNew(block.timestamp, 0, config);
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
        limiter = limiter.applyUpdate(config, tvl);
    }

    function _inflow(uint256 amount) internal {
        uint256 overflow;
        (limiter, overflow) = limiter.applyInflow(config, tvl, amount);
        assert(overflow == 0);
        tvl += amount;
    }

    function _outflow(uint256 amount) internal {
        (DecreaseLimiter newLimiter, uint256 overflow) = limiter.applyOutflow(config, tvl, amount);
        if (overflow == 0) {
            tvl -= amount;
            limiter = newLimiter;
        } else {
            console.log("!!! LIMIT HIT !!!");
            emit log_named_decimal_uint("  flow", amount, 18);
            fail();
        }
    }

    function print() public {
        print("");
    }

    function print(string memory name) public {
        (uint256 lastUpdatedAt, uint256 mainUsedWad, uint256 elasticBufferWad) = limiter.getState().unpack();
        console.log("Limiter \"%s\" (t: %d)", name, block.timestamp);
        console.log("  last updated: %d", lastUpdatedAt);
        emit log_named_decimal_uint("  TVL         ", tvl, 18);
        emit log_named_decimal_uint("  main        ", mainUsedWad, 18);
        emit log_named_decimal_uint("  elastic     ", elasticBufferWad, 18);
        (uint256 maxMainFlow, uint256 maxElasticDeplete) =
            limiter._getPassivelyUpdatedBuffers(config, tvl, block.timestamp);
        uint256 maxOut = maxMainFlow + maxElasticDeplete;
        emit log_named_decimal_uint("  max out     ", maxOut, 18);
    }

    function _applyTvlChange(int256 delta) internal {
        tvl = (tvl.toInt256() + delta).toUint256();
    }
}
