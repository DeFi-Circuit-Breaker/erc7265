use anyhow::Result;
use arbiter_core::{
    environment::{BlockSettings, EnvironmentParameters, GasSettings},
    manager::Manager,
    math::float_to_wad,
    middleware::RevmMiddleware,
};
use ethers::types::U256;
use std::sync::Arc;

use crate::agents::*;
use crate::bindings::mock_decrease_limiter::MockDecreaseLimiter;

pub mod agents;

mod bindings;

const TEST_ENV_LABEL: &str = "test";

// Data storage

use serde::Serialize;
use serde_json;
use std::fs::File;
use std::io::Write;

#[derive(Serialize)]
struct DataPoint {
    time: u64,
    max_main_flow: U256,
    max_elastic_deplete: U256,
    tvl: f64,
    last_updated_at: U256,
    rel_main_buffer: U256,
    rel_elastic: U256,
}

use clap::Parser;

#[derive(Parser, Debug)]
struct Args {
    #[arg(short, long)]
    mu: f64,
    #[arg(short, long)]
    sigma: f64,
    #[arg(short, long, default_value_t = 0.05_f64)]
    draw: f64,
}

#[tokio::main]
pub async fn main() -> Result<()> {
    let mut manager = Manager::new();

    let params = EnvironmentParameters {
        label: TEST_ENV_LABEL.to_owned(),
        block_settings: BlockSettings::UserControlled,
        gas_settings: GasSettings::UserControlled,
    };

    let _ = manager.add_environment(params);
    manager.start_environment(TEST_ENV_LABEL)?;

    let client = Arc::new(RevmMiddleware::new(
        manager.environments.get(TEST_ENV_LABEL).unwrap(),
        None,
    )?);
    println!("created client with address {:?}", client.address());

    let args = Args::parse();
    println!("args: {args:?}");

    let max_draw: f64 = args.draw;
    let main_window = 200;
    let elastic_window = 20;
    let initial_tvl = 1.0;
    let constructor_args = (
        float_to_wad(max_draw),
        U256::from(main_window),
        U256::from(elastic_window),
        float_to_wad(initial_tvl),
    );
    let mut bn: u64 = 1;
    let mut time: u64 = 1;
    let _ = client.update_block(bn, time);

    let limiter = MockDecreaseLimiter::deploy(client.clone(), constructor_args)?
        .send()
        .await?;
    println!("limiter deployed at: {}", limiter.address());

    let seconds_per_step: u64 = 1;
    let total_steps: u64 = 10_000;
    let mut changer = TVLChanger::new(
        limiter.clone(),
        initial_tvl,
        total_steps as usize,
        (total_steps * seconds_per_step) as f64,
        Some(420),
        args.mu,
        args.sigma,
    );

    let mut data: Vec<DataPoint> = vec![];

    for _ in 0..total_steps {
        time += seconds_per_step;
        bn += 1;
        let _ = client.clone().update_block(bn, time);
        changer.apply_next_change().await?;

        let (max_main_flow, max_elastic_deplete) = limiter.get_max_flow().call().await?;
        let (last_updated_at, rel_main_buffer, rel_elastic) = limiter.get_raw().call().await?;
        data.push(DataPoint {
            time,
            max_main_flow,
            max_elastic_deplete,
            tvl: changer.last_tvl,
            last_updated_at,
            rel_main_buffer,
            rel_elastic,
        });
    }

    File::create("data/main_data.json")
        .expect("Unable to create file")
        .write_all(
            serde_json::to_string(&data)
                .expect("unable to serialize data")
                .as_bytes(),
        )
        .expect("Unable to write data");

    File::create("data/exceeds.json")
        .expect("Unable to create file")
        .write_all(
            serde_json::to_string(&changer.exceed_events)
                .expect("unable to serialize exceeds")
                .as_bytes(),
        )
        .expect("unable to write data");

    Ok(())
}
