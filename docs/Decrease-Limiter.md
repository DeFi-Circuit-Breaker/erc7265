# Decrease Limiter

## Goal

The goal of decrease limiters is to detect large spikes in short-term **decreases of a set metric**
in a smart contract system. This decrease limiter is primarly aimed at tracking and limiting sudden
changes in asset reserves.

Specifically this allows it to serve as a general purpose security mechanism by limiting the core
damage (loss of assets) a smart contract application may suffer irrespective of the root cause as it only concerns itself with inflows and outflows.

## Design

### Outflow tracking

The overarching mechainsm to implement is a system that signals whenever the net outflows $\Delta x$
over a given a time frame (main time frame) $T_m$ exceeds some % threshhold $r$ of the total reserves
$x$.

#### Naive Approach

Naively this can be achieved by tracking all flows (in/out) along with their timestamp, filtering by
$t_i \ge t - T_m$, summing them (the outflows) up and comparing them against the threshold $x\cdot r$ (whereby $x$
is the total reserves $T_m$ seconds ago).

This approach is precise but not very efficient due to every liquidity event having to be
individually tracked and retrieved, leading up to $O(n)$ storage reads to compute the signal and $O(1)$ writes which are particularly expensive in the EVM.

#### The _Buffer_ Based Design

Instead of tracking individual liquidity events this design tracks the cumulative remaining outflow
capacity, dubbed the "main buffer" $b_m$. This buffer is depleted whenever an outflow occurs and is
replenished gradually over time up to its cap which is defined as the threshold $x \cdot r$:

$$ b_m' := \min (x\cdot r, b_m + x\cdot r \cdot \frac{\Delta t}{T_m}) - \Delta x$$

A negative post-update buffer ($b' \lt 0$) indicates that the limiter has been exceeded. In the
core implementation the buffer is represented as an unsigned integer, meaning its lower bound is
`0`. To indicate that a given limiter has been exceeded the update method returns an `overflow`
value indicating how much of the change went beyond the limit:

```solidity
function applyOutflow(
    DecreaseLimiter limiter,
    LimiterConfig config,
    uint256 preTvl,
    uint256 outflow,
    uint256 currentTime
) internal pure returns (DecreaseLimiter updatedLimiter, uint256 overflow) {
    // ... actual logic
}
```

**Illustrated as:**

<img src="../_assets/decrease-limiter-main-buffer-basic.png" />

**How the Main Buffer Handles Inflows**

The only impact inflows have to the main buffer is to increase the its cap and replenish rate.

<img src="../_assets/decrease-limiter-main-buffer-inflow.png" width="400" />

#### Mitigating Denial-of-Service (DoS): The _Elastic_ Buffer

If the rate limiter were only made up of the main buffer and used to track asset inflows/outflows it
would be trivial to have it continuously be empty maxed out ($b_m = 0$) via a simple flashloan:

<img src="../_assets/decrease-limiter-dos.png" width="700" />


