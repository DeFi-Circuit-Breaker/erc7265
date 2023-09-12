# Rate Limiter "Buffer" Technical Documentation

This document describes the functionality, implementation and properties underlying the rate limiter
library as laid out in [`BufferLimiterLib.sol`](./BufferLimiterLib.sol).

## Goal

The goal is to create a simple library that statefully tracks inflows / outflows for a given
property e.g. asset reserves or token issuance and indicate whens a certain configured threshold is
exceeded.

Rate limiters are be "biased" in the sense that they limit only one direction of
movement, e.g. for asset reserves a single limiter would allow arbitrary inflows while returning
errors if certain outflow bounds are exceeded. 

Beyond the base goal of tracking flows practically the implementation aims to be simple and compact,
having a small state, requiring minimal state reads and updates to be maintained in a contract.


## Maths

### Definitions

**Environment**

- $t$ current time in seconds
- $x$ the total reserves / TVL of the property being tracked

**Limiter Parameters**

- $r$ the maximum relative change, negative if limiting outflows, positive for inflows e.g. `-0.05` => maximum 5% outflow
- $t_m$ main window, time in seconds for main buffer to go from empty to fully replenished
- $t_l$ elastic window, time in seconds for elastic buffer to be naturally depleted

**Virtual State**

These are definitions that are useful starting points / mental models but are not directly part of
the limiter's state.

- $b_m$ the real main capacity of the limiter e.g. `-5e6` indicates that 5M tokens can be withdrawn
- $b_l$ the real elastic capacity of the limiter

**Limiter State ($v$, $s$, $t_l$)**

- $v$ the relative main buffer capacity, defined as: $v = \frac{b_m}{x \cdot r}$ (sign of buffer $b$ and $r$ should
  always cancel such that $v \in [0; 1]$)
- $s$ the relative elastic buffer capacity, defined as $s = \frac{b_l}{x}$
- $t_l$ the last timestamp in seconds at which the limiter was updated

**Changes**

Changes of time ($\Delta t$), TVL ($\Delta x$) or buffers ($\Delta b_m$) are denotated by the symbol
being changed and the greek letter delta ($\Delta$).

Similarly values immediately after an update are denoted with a tilda e.g.: $t_l' \coloneqq t_l + \Delta t$

### State Transitions

#### Simple Update

No inflow / outflow, simply decay elastic buffer and replenish main:

- **Timestamp update:**

  $$\Delta t = t - t_l$$
  $$t_l' \coloneqq  t_l + \Delta t $$

- **Main buffer update (main buffer needs to be capped to 100% available via `min`)**
  $$v' = \min(v + \frac{\Delta t}{t_m}; 1)$$

- **Elastic buffer update (cannot go below zero)**
  $$s' = \max(s \cdot (1 - \frac{\Delta t}{t_m}); 0)$$

#### Inflow ($\frac{\Delta x}{r} < 0$)

First the simple update is applied to replenish/deplete the buffers and set the time to the newest
timestamp. Note that the base symbols ($s$, $v$, $t_l$) are implied to be the values post-"simple
update".

- **(Implicit) Reserve update ($x' > 0 \land x > 0$):**

  $$x' = x + \Delta x$$

- **Elastic buffer update:**
  Absolute value $|\Delta x|$ is used as $s$ is an unsigned, relative capacity value, therefore
  increases can't be negative.

  $$s' = (s \cdot x + |\Delta x|) \cdot \frac{1}{x'} $$

  The implicit scaling of the elastic buffer by $\frac{x}{x'}$ ($s' = s \cdot \frac{x}{x'} + \frac{|\Delta x|}{x'}$) ensures that elastic buffer increases are additive (assuming both updates are inflows):

  $$s_2 = (((s_0 \cdot x_0 + |\Delta x_1|)\cdot \frac{1}{x_1})\cdot x_1 + |\Delta x_2|) \cdot \frac{1}{x_2}$$

  $$s_2 = (s_0 \cdot x_0 + |\Delta x_1|+ |\Delta x_2|) \cdot \frac{1}{x_2}$$

  We can also prove that the real elastic buffer change $\Delta b_l = b_l' - b_l$ is equal to
  $\Delta x$ (assuming the elastic buffer is expressed as an unsigned capacity value):

  $$\Delta b_l = x' \cdot s' - x \cdot s$$
  $$\Delta b_l = x' \cdot (s \cdot x + |\Delta x|) \cdot \frac{1}{x'}  - x \cdot s$$
  $$\Delta b_l = s \cdot x + |\Delta x| - x \cdot s$$
  $$\Delta b_l = |\Delta x|$$


- **Main buffer update:**

  $$v' = v \cdot \frac{x}{x'}$$

  Similar to the elastic update the existing relative value is scaled to ensure consistency and
  additivity.


#### Outflow ($\frac{\Delta x}{r} > 0$)

Similar to the outflow the elastic buffer is updated. However unlike the inflow it's depleted:
- **(Implicit) Reserve update ($x' > 0 \land x > 0$):**

  $$x' = x + \Delta x$$

- **Elastic buffer update:**
  $$s' = \max(s \cdot x - |\Delta x|; 0) \cdot \frac{1}{x'} $$

- **Main buffer update:**

  First the amount that was used to deplete the elastic buffer is removed from the amount delta:

  $$\Delta x' = \max(|\Delta x| - s\cdot x; 0)$$

  $$v' = (v \cdot x - \frac{\Delta x'}{|r|}) \cdot \frac{1}{x'} $$

- **Limit exceeded condition:**

  If the following condition is true it indicates that the limit has been exceeded. This is also
  when $v'$ would be negative.

  $$\frac{\Delta x'}{|r|} > v \cdot x$$

