
#[test_only]
module match_game::test {
    use sui::clock;
    use sui::coin::{Self, Coin};
    use sui::random::{Self, update_randomness_state_for_testing, Random};
    use sui::sui::SUI;
    use sui::test_scenario as ts;

    use match_game::{match_game};

    // #[test_only]
    // /// Wrapper of module initializer for testing
    // public fun test_init(ctx: &mut TxContext) {
    //     init(MANAGED {}, ctx)
    // }

    #[test]
    fun test_join_pvp_game() {
        let user1 = @0x0;
        let mut ctx = tx_context::dummy();
        let mut ts = ts::begin(user1);
        let entry_fee: Coin<SUI> = ts.take_from_sender();
        
        // let id = object::new(ctx);
        // let matches = vector::empty<GameMatch>();
        // let matchPool = PVPMatchPool {
        //     id,
        //     matches
        // };

        // match_game::match_game::join_pvp_game(
        //     entry_fee, 
        //     match_pool, 
        //     r, 
        //     clock, 
        //     ctx
        // );
    }

    #[test]
    fun test_A() {
        // Initialize a mock sender address
        let user1 = @0x0;
        let user2 = @0x1;
        let user3 = @0x2;
        let user4 = @0x3;
        // Begins a multi-transaction scenario with addr1 as the sender
        let mut ts = ts::begin(user1);

        // Setup randomness
        random::create_for_testing(ts.ctx());
        ts.next_tx(user1);
        let mut random_state: Random = ts.take_shared();
        random_state.update_randomness_state_for_testing(
            0,
            x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F",
            ts.ctx(),
        );

        // let coin: Coin<SUI> = ts.take_from_sender();
        let entry_fee: Coin<SUI> = ts.take_from_sender();
        // match_game::join_pvp_game(
        // );
        // Cleans up the scenario object
        ts::end(ts);
    }
}