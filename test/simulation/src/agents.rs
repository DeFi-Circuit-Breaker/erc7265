use anyhow::Result;
use arbiter_core::math::{GeometricBrownianMotion, StochasticProcess, Trajectories};
use arbiter_core::middleware::RevmMiddlewareError;
use bindings::mock_decrease_limiter::MockDecreaseLimiterErrors;
use ethers::abi::AbiDecode;

use serde::Serialize;

use super::*;

#[derive(Serialize)]
pub struct ExceedEvent {
    time: U256,
    pre_tvl: f64,
    tvl_change: f64,
    target_val: f64,
}

pub struct TVLChanger {
    limiter: MockDecreaseLimiter<RevmMiddleware>,
    trajectory: Trajectories,
    pub last_tvl: f64,
    index: usize,
    pub exceed_events: Vec<ExceedEvent>,
}

impl TVLChanger {
    pub fn new(
        limiter: MockDecreaseLimiter<RevmMiddleware>,
        initial_tvl: f64,
        num_steps: usize,
        t_n: f64,
        seed: Option<u64>,
        mu: f64,
        sigma: f64,
    ) -> Self {
        let process = GeometricBrownianMotion::new(mu / t_n, sigma / t_n);

        let t_0: f64 = 0.0;

        let trajectory = match seed {
            Some(seed) => {
                process.seedable_euler_maruyama(initial_tvl, t_0, t_n, num_steps, 1, false, seed)
            }
            None => process.euler_maruyama(initial_tvl, t_0, t_n, num_steps, 1, false),
        };

        Self {
            limiter,
            trajectory,
            last_tvl: initial_tvl,
            index: 0,
            exceed_events: vec![],
        }
    }

    pub fn path(&self) -> Vec<f64> {
        self.trajectory.paths[0].clone()
    }

    pub async fn apply_next_change(&mut self) -> Result<()> {
        let mut new_tvl = self.trajectory.paths[0][self.index];
        self.index += 1;
        if new_tvl < 0.0 {
            new_tvl = 0.0;
        }
        let tvl_delta = new_tvl - self.last_tvl;

        // TODO: Test zero
        if tvl_delta > 0.0 {
            self.limiter
                .tracked_inflow(float_to_wad(tvl_delta))
                .send()
                .await?
                .await?;
            self.last_tvl = new_tvl;
        } else if tvl_delta < 0.0 {
            match self
                .limiter
                .tracked_outflow(float_to_wad(-tvl_delta))
                .send()
                .await
            {
                Ok(_) => {
                    self.last_tvl = new_tvl;
                }
                Err(error) => {
                    if let RevmMiddlewareError::ExecutionRevert {
                        gas_used: _,
                        output,
                    } = error.as_middleware_error().unwrap()
                    {
                        if let MockDecreaseLimiterErrors::LimiterExceeded(_) =
                            MockDecreaseLimiterErrors::decode(&output).unwrap()
                        {
                            self.exceed_events.push(ExceedEvent {
                                time: self.limiter.client().get_block_timestamp().await?,
                                pre_tvl: self.last_tvl,
                                tvl_change: tvl_delta,
                                target_val: new_tvl,
                            })
                        }
                    }
                }
            }
        }

        Ok(())
    }
}
