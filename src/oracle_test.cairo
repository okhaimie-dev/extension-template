use core::num::traits::{Zero};
use core::option::{OptionTrait};
use core::traits::{TryInto};
use ekubo::interfaces::core::{
    ICoreDispatcherTrait, ICoreDispatcher, IExtensionDispatcher, IExtensionDispatcherTrait
};
use ekubo::interfaces::positions::{IPositionsDispatcher, IPositionsDispatcherTrait};
use ekubo::interfaces::router::{IRouterDispatcher, IRouterDispatcherTrait, RouteNode, TokenAmount};
use ekubo::types::bounds::{Bounds};
use ekubo::types::call_points::{CallPoints};
use ekubo::types::i129::{i129};
use ekubo::types::keys::{PoolKey, PositionKey};
use ekubo_extension::oracle::{IOracleDispatcher, IOracleDispatcherTrait, PoolState, Oracle};
use ekubo_extension::test_token::{TestToken, IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    declare, ContractClassTrait, cheat_caller_address, cheat_block_timestamp, CheatSpan,
    ContractClass
};
use starknet::{
    get_contract_address, get_block_timestamp, contract_address_const,
    storage_access::{StorePacking}, syscalls::{deploy_syscall}, ContractAddress
};

fn deploy_token(
    class: ContractClass, recipient: ContractAddress, amount: u256
) -> IERC20Dispatcher {
    let (contract_address, _) = class
        .deploy(@array![recipient.into(), amount.low.into(), amount.high.into()])
        .expect('Deploy token failed');

    IERC20Dispatcher { contract_address }
}

fn deploy_oracle(core: ICoreDispatcher) -> IExtensionDispatcher {
    let contract = declare("Oracle").unwrap();
    let (contract_address, _) = contract
        .deploy(@array![core.contract_address.into()])
        .expect('Deploy failed');

    IExtensionDispatcher { contract_address }
}

fn assert_round_trip<T, U, +StorePacking<T, U>, +PartialEq<T>, +Drop<T>, +Copy<T>>(value: T) {
    assert(StorePacking::<T, U>::unpack(StorePacking::<T, U>::pack(value)) == value, 'roundtrip');
}

#[test]
fn test_pool_state_packing_round_trip_many_values() {
    assert_round_trip(
        PoolState {
            block_timestamp_last: Zero::zero(),
            tick_cumulative_last: Zero::zero(),
            tick_last: Zero::zero(),
        }
    );
    assert_round_trip(
        PoolState {
            block_timestamp_last: 1,
            tick_cumulative_last: i129 { mag: 2, sign: false },
            tick_last: i129 { mag: 3, sign: false },
        }
    );
    assert_round_trip(
        PoolState {
            block_timestamp_last: 1,
            tick_cumulative_last: i129 { mag: 2, sign: true },
            tick_last: i129 { mag: 3, sign: true },
        }
    );
    assert_round_trip(
        PoolState {
            block_timestamp_last: 0xffffffffffffffff,
            tick_cumulative_last: i129 { mag: 0x7fffffffffffffffffffffff, sign: false },
            tick_last: i129 { mag: 0x7fffffff, sign: false },
        }
    );
    assert_round_trip(
        PoolState {
            block_timestamp_last: 0xffffffffffffffff,
            tick_cumulative_last: i129 { mag: 0x7fffffffffffffffffffffff, sign: true },
            tick_last: i129 { mag: 0x7fffffff, sign: true },
        }
    );
}


fn core() -> ICoreDispatcher {
    ICoreDispatcher {
        contract_address: contract_address_const::<
            0x00000005dd3D2F4429AF886cD1a3b08289DBcEa99A294197E9eB43b0e0325b4b
        >()
    }
}

fn positions() -> IPositionsDispatcher {
    IPositionsDispatcher {
        contract_address: contract_address_const::<
            0x02e0af29598b407c8716b17f6d2795eca1b471413fa03fb145a5e33722184067
        >()
    }
}

fn router() -> IRouterDispatcher {
    IRouterDispatcher {
        contract_address: contract_address_const::<
            0x0199741822c2dc722f6f605204f35e56dbc23bceed54818168c4c49e4fb8737e
        >()
    }
}

fn setup(
    starting_balance: u256, fee: u128, tick_spacing: u128, starting_tick: i129
) -> (PoolKey, u256) {
    let oracle = deploy_oracle(core());
    let token_class = declare("TestToken").unwrap();
    let owner = get_contract_address();
    let (tokenA, tokenB) = (
        deploy_token(token_class, owner, starting_balance),
        deploy_token(token_class, owner, starting_balance)
    );
    let (token0, token1) = if (tokenA.contract_address < tokenB.contract_address) {
        (tokenA, tokenB)
    } else {
        (tokenB, tokenA)
    };

    let pool_key = PoolKey {
        token0: token0.contract_address,
        token1: token1.contract_address,
        fee: fee,
        tick_spacing: tick_spacing,
        extension: oracle.contract_address,
    };

    (pool_key, core().initialize_pool(pool_key, starting_tick))
}

#[test]
#[fork("mainnet")]
fn test_create_oracle_pool() {
    let (pool_key, _starting_price) = setup(
        starting_balance: 1000, fee: 0, tick_spacing: 100, starting_tick: Zero::zero()
    );

    router()
        .swap(
            RouteNode { pool_key, sqrt_ratio_limit: u256 { high: 1, low: 0 }, skip_ahead: 0, },
            TokenAmount { token: pool_key.token1, amount: i129 { mag: 1, sign: false } }
        );
}
