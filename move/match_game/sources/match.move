module match_game::match_game {
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::random::{Random, new_generator};
    use sui::clock::Clock;
    use sui::event;
    use sui::transfer;

    // ====== General Structs ======
    public struct GameMatch has store {
        // id: ID,
        id: u64,
        maker: address,
        taker: Option<address>,
        maker_score: u64,
        taker_score: u64,
        maker_start: u64,
        maker_end: u64,
        taker_start: u64,
        taker_end: u64,
        status: MatchStatus,
        winner: address,
        prize: Balance<SUI>
    }

    /// A dummy NFT to represent the flashloan functionality
    public struct NFT has key, store {
        id: UID,
        match_id: u64,
        // entry_fee: Balance<SUI>,
        entry_fee: u64
    }


    // ====== PVP Structs ======

    // We can also call this an "order book"
    public struct PVPMatchPool has key, store {
        id: UID,
        // matches: vector<GameMatch> // OLD
        // vector<UID> where we have all matches that are in the "OPEN" state
        open_matches: vector<u64>,
        // Table<K, V> where K is ID from match type and V is the GameMarch object
        all_matches: Table<u64, GameMatch>
        // IRVIN: Ask about what data structure to use
    }

    // === Tournament Structs ===
    // public struct TournamentPool has key {
    //     id: UID,
    //     amount: Balance<SUI>
    // }

    // public struct EntryTicketNFT has key {
    //     id: UID,
    //     entry_fee: Balance<SUI>,
    //     timestamp_ms: u64 
    // }

    public enum MatchStatus has store, copy, drop {
        OPEN, // Available (waiting for a Taker)
        IN_PROGRESS, // Matched (while Taker plays).
        RESOLVED, // Scores have been resolved, both scores are in and winner determined.
        SETTLED, // Winner has claimed prize. Prize settled.
        EXPIRED, // Edge Case -- we set a limit to the match being opend
        CANCELLED, // Edge Case -- the "maker" player can pay a fee to cancel match if they don't like their score
        VOIDED, // Edge Case -- some issues might have happened
    }

    // ====== PVP Structs ======

    // Event on whether the output is verified
    // struct VerifiedEvent has copy, drop {
    //     is_verified: bool,
    // }

    // ====== Events ======

    // Event marking a match created. 
    // The "maker" is the player that "created" this match.
    public struct MatchCreatedEvent has copy, drop {
        match_id: u64,
        maker: address,
        timestamp_ms: u64
    }

    // ====== Functions ======

    // Initialized called only once on module publish
    fun init(ctx: &mut TxContext) {
        let id = object::new(ctx);
        let open_matches = vector::empty<u64>();
        let all_matches:  Table<u64, GameMatch> = table::new(ctx);
        let matchPool = PVPMatchPool {
            id,
            open_matches,
            all_matches
        };

        transfer::transfer(
            matchPool, 
            tx_context::sender(ctx)
        )
    }

    // Player joins PVP game
    // STEP 1. Check if player has an opened match.
    //         If player has an open match, then create a new match
    //         Do not match player with his older match
    // STEP 2. If player does not have an opened match & not matches in pool.
    //         Create a new match.
    // STEP 3. If there are matches available in pool.
    //         Join "random" match.
    //         NOTE: match that player is joining already has a score.
    //         QUESTION: Will score be hidden?
    #[allow(lint(public_random))] // IRVIN: Fix / Look into this later
    public fun join_pvp_game(
        entry_fee: Coin<SUI>,
        match_pool: &mut PVPMatchPool,
        r: &Random,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // STEP 1: If there's a list of "OPEN" matches, match with a "random" one
        if (vector::length(&match_pool.open_matches) > 0) {
            // STEP 2: Join random match
            join_match(entry_fee, match_pool, r, clock, ctx);
        }
        else {
            // STEP 2: Create match
            create_match(entry_fee, match_pool, clock, ctx);
        }
    }

    // Create a match.
    // From the game's perspective, the player creating the match is called
    // a "Maker".
    // This simple creates the match object. 
    // The match score for each player will be updated afterwards
    fun create_match(
        entry_fee: Coin<SUI>,
        match_pool: &mut PVPMatchPool,
        clock: &Clock,
        ctx: &mut TxContext
    ) { 
        let maker = tx_context::sender(ctx);
        // let id = object::new(ctx);
        let entry_fee_val = entry_fee.value();

        let gameMatch: GameMatch = GameMatch {
            id: generate_random_id(clock),
            maker: maker,
            taker: option::some(@0x0), // Create empty address
            maker_score: 0,
            taker_score: 0,
            maker_start: 0,
            maker_end: 0,
            taker_start: 0,
            taker_end: 0,
            status: MatchStatus::OPEN,
            winner: @0x0,
            prize: coin::into_balance(entry_fee)
        };

        let timestamp_ms = clock.timestamp_ms();
        let matchCreatedEvent = MatchCreatedEvent {
            // match_id: gameMatch.id.uid_to_inner(),
            match_id: gameMatch.id,
            maker,
            timestamp_ms,
        };

        // match_pool.open_matches.push_back(gameMatch.id.to_inner());
        match_pool.open_matches.push_back(gameMatch.id);
        
        event::emit(matchCreatedEvent);
        let nft = NFT {
            id: object::new(ctx),
            // match_id: gameMatch.id.uid_to_inner(),
            match_id: gameMatch.id,
            entry_fee: entry_fee_val
        };

        transfer::public_transfer(nft, tx_context::sender(ctx));
        
        table::add(
            &mut match_pool.all_matches, 
            gameMatch.id, 
            gameMatch
        );
    }

    fun generate_random_id(clock: &Clock): u64 {
        // let timestamp = clock::timestamp_ms(clock);
        let timestamp = clock.timestamp_ms();
        let random_value = timestamp % 3;
        // debug::print(&random_value);
        random_value
    }

    // Join a random match
    fun join_match(
        entry_fee: Coin<SUI>,
        match_pool: &mut PVPMatchPool,
        r: &Random,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // assert!(entry_fee <= balance::value(&pool.amount), ELoanAmountExceedPool);

        let player = tx_context::sender(ctx);
        let matches_len = vector::length(&match_pool.open_matches);
        let entry_fee_val = entry_fee.value();

        if(matches_len == 1) {
            let match_id_selected = match_pool.open_matches[0]; // Get ID of match
            let match_selected = match_pool.all_matches.borrow_mut(match_id_selected);
            match_selected.taker = option::some(player);
            match_selected.status = MatchStatus::IN_PROGRESS;
            match_selected.prize.join(entry_fee.into_balance());
            match_selected.taker_start = clock.timestamp_ms();

            // NFT {
            //     id: object::new(ctx),
            //     match_id: match_selected.id.uid_to_inner(),
            //     entry_fee: entry_fee_val
            // }
            let nft = NFT {
                id: object::new(ctx),
                // match_id: gameMatch.id.uid_to_inner(),
                match_id: match_selected.id,
                entry_fee: entry_fee_val
            };

            transfer::public_transfer(nft, tx_context::sender(ctx));
        }
        else
        {
            let mut generator = r.new_generator(ctx);
            let rand_index = generator.generate_u64_in_range(0, matches_len);
            // let matchPaired = match_pool.open_matches.borrow_mut(rand_index);
            let match_id_selected = match_pool.open_matches[0]; // Get ID of match
            let match_selected = match_pool.all_matches.borrow_mut(match_id_selected);
            match_selected.taker = option::some(tx_context::sender(ctx));
            match_selected.status = MatchStatus::IN_PROGRESS;

            balance::join(&mut match_selected.prize, coin::into_balance(entry_fee));

            // NFT {
            //     id: object::new(ctx),
            //     match_id: match_selected.id.uid_to_inner(),
            //     entry_fee: entry_fee_val
            // }
            let nft = NFT {
                id: object::new(ctx),
                // match_id: gameMatch.id.uid_to_inner(),
                match_id: match_selected.id,
                entry_fee: entry_fee_val
            };

            transfer::public_transfer(nft, tx_context::sender(ctx));
        }
    }

    // fun increase_moves(
    //     entry_fee: Coin<SUI>,
    //     match_pool: &mut PVPMatchPool,
    //     match_id: u64
    // ) {

    // }

    // public fun submit_score(
    //     gameMatch: &mut GameMatch,
    //     ctx: &mut TxContext
    // ) {

    // }

    // public fun submit_match_result(
    //     gameMatch: &mut GameMatch,
    //     match_pool: &mut PVPMatchPool,
    //     ctx: &mut TxContext
    // ) {
    //     let matchPaired = mat
    // }

    // ====== Randomness ======
    // fun match_taker_maker(
    //     player1
    //     matchPool: &mut PVPMatchPool, 
    //     r: &Random, 
    //     clock: &Clock, 
    //     ctx: &mut TxContext
    // ) {
    //     assert!(game.end_time <= clock.timestamp_ms(), EGameInProgress);
    //     assert!(game.winner.is_none(), EGameAlreadyCompleted);
    //     assert!(game.participants > 0, ENoParticipants);
    //     let mut generator = r.new_generator(ctx);
    //     let winner = generator.generate_u32_in_range(1, vector::length(&match_pool.matches));
    //     game.winner = option::some(winner);
    // }

    // public fun view_match_score() {
    // }

    // Deposit money into liquidity pool
    // fun deposit_pool(pool: &mut TournamentPool, deposit: Coin<Sui>) {
    //     balance::join(&mut pool.amount, coin:into_balance(deposit));
    // }

    // public fun claim_prize(match: &mut Match, ctx: &mut TxContext) {
        // assert(match.status == MatchStatus.RESOLVED);
    // }

    // public fun mint_nft(payment: Coin<SUI>, ctx: &mut TxContext): NFT {

    // }

    // public fun verify_ecvrf_output(output: vector<u8>, alpha_string: vector<u8>, public_key: vector<u8>, proof: vector<u8>) {
    //     event::emit(VerifiedEvent {is_verified: ecvrf::ecvrf_verify(&output, &alpha_string, &public_key, &proof)});
    // }
}

// 1. public `create_match` 
// 2. `stake_entry_fee`
// 3. `deposit_to_pool`
// 4. public `start_match` 
// 5. public `end_match` 
// 6. public `claim_prize`
// 7. public `claim_entry_fee`