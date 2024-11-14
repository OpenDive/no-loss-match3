module match_game::match_game {
    use sui::sui::SUI;
    use sui::table::{Self, Table};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::random::{Random, new_generator};
    use sui::clock::Clock;
    use sui::event;
    use sui::transfer;

    // ====== Invalid ======
    const EInvalidState: u64 = 1;

    // ====== General Structs ======
    public struct GameMatch has store {
        // id: ID,
        id: u64,
        maker: address,
        taker: address,
        maker_score: u64,
        taker_score: u64,
        maker_start: u64,
        maker_end: u64,
        taker_start: u64,
        taker_end: u64,
        maker_lives: u64,
        taker_lives: u64,
        status: MatchStatus,
        winner: address,
        prize: Balance<SUI>,
        treasury: Balance<SUI>
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
        owner: address,
        open_matches: vector<u64>,
        all_matches: Table<u64, GameMatch>
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
        MAKER_SCORE_SUBMITTED,
        TAKER_SCORE_SUBMITTED,
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
        let owner = ctx.sender();

        let matchPool = PVPMatchPool {
            id,
            owner,
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
            taker: @0x0, // Create empty address
            maker_score: 0,
            taker_score: 0,
            maker_start: 0,
            maker_end: 0,
            taker_start: 0,
            taker_end: 0,
            maker_lives: 2,
            taker_lives: 2,
            status: MatchStatus::OPEN,
            winner: @0x0,
            prize: coin::into_balance(entry_fee),
            treasury: balance::zero()
        };

        let timestamp_ms = clock.timestamp_ms();
        let matchCreatedEvent = MatchCreatedEvent {
            match_id: gameMatch.id,
            maker,
            timestamp_ms,
        };

        match_pool.open_matches.push_back(gameMatch.id);
        
        event::emit(matchCreatedEvent);
        let nft = NFT {
            id: object::new(ctx),
            // match_id: gameMatch.id.uid_to_inner(),
            match_id: gameMatch.id,
            entry_fee: entry_fee_val
        };
        
        table::add(
            &mut match_pool.all_matches, 
            gameMatch.id, 
            gameMatch
        );

        transfer::public_transfer(nft, tx_context::sender(ctx))
    }

    fun generate_random_id(clock: &Clock): u64 {
        let timestamp = clock.timestamp_ms();
        let random_value = timestamp % 3;
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
            match_selected.taker = player;
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
            match_selected.taker = tx_context::sender(ctx);
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
    //     entry_ticket: &mut NFT,
    //     fee: Coin<SUI>,
    //     match_pool: &mut PVPMatchPool,
    // ) {
    //     let match_id = entry_ticket.match_id;
    //     let current_match = match_pool.all_matches.borrow_mut(match_id);
    //         // current_match.taker = option::some(tx_context::sender(ctx));
    //         // current_match.status = MatchStatus::IN_PROGRESS;
    // }

    // struct AdminCap

    public fun increase_lives(
        entry_ticket: &mut NFT,
        fee: Coin<SUI>,
        match_pool: &mut PVPMatchPool,
        ctx: &mut TxContext
    ) {
        let sender_address = tx_context::sender(ctx);
        assert!(match_pool.owner == sender_address, 0);

        let match_id = entry_ticket.match_id;
        let current_match = match_pool.all_matches.borrow_mut(match_id);

        if(sender_address == current_match.maker && current_match.maker_lives == 0){
            current_match.maker_lives = current_match.maker_lives - 1;
            current_match.treasury.join(fee.into_balance());
        }
        else if(sender_address == current_match.taker && current_match.maker_lives == 0) {
            current_match.taker_lives = current_match.taker_lives - 1;
            current_match.treasury.join(fee.into_balance());
        }
        else {
            abort EInvalidState
        }
    }

    public fun remove_lives(
        entry_ticket: &mut NFT,
        match_pool: &mut PVPMatchPool,
        ctx: &mut TxContext
    ) {
        let sender_address = tx_context::sender(ctx);
        assert!(match_pool.owner == sender_address, 0);

        let match_id = entry_ticket.match_id;
        let current_match = match_pool.all_matches.borrow_mut(match_id);

        if(sender_address == current_match.maker && current_match.maker_lives > 0){
            current_match.maker_lives = current_match.maker_lives - 1;
        }
        else if(sender_address == current_match.taker && current_match.maker_lives > 0) {
            current_match.taker_lives = current_match.taker_lives - 1;
        }
        else {
            abort EInvalidState
        }
    }

    public fun submit_score(
        final_score: u64,
        entry_ticket: &mut NFT,
        match_pool: &mut PVPMatchPool,
        ctx: &mut TxContext
    ) {
        let sender_address = tx_context::sender(ctx);
        assert!(match_pool.owner == sender_address, 0);

        let match_id = entry_ticket.match_id;
        let current_match = match_pool.all_matches.borrow_mut(match_id);

        if(sender_address == current_match.maker){
            current_match.maker_score = final_score;
            current_match.status = MatchStatus::MAKER_SCORE_SUBMITTED;
        }
        else {
            current_match.taker_score = final_score;
            current_match.status = MatchStatus::TAKER_SCORE_SUBMITTED;
        }
    }

    public fun resolve_match(
        // entry_ticket: &mut NFT,
        match_id: u64,
        match_pool: &mut PVPMatchPool,
        ctx: &mut TxContext
    ) {
        // let match_id = entry_ticket.match_id;
        let current_match = match_pool.all_matches.borrow_mut(match_id);

        if(current_match.status == MatchStatus::IN_PROGRESS 
            && (current_match.maker_score != 0 && current_match.taker_score != 0)) {
            if(current_match.maker_score > current_match.taker_score) {
                current_match.winner = current_match.maker;
                current_match.status = MatchStatus::RESOLVED;
            }
            else {
                current_match.winner = current_match.taker;
                current_match.status = MatchStatus::RESOLVED;
            }
        }
    }

    public fun settle_match(
        entry_ticket: &mut NFT,
        match_pool: &mut PVPMatchPool,
        ctx: &mut TxContext
    ) {
        let match_id = entry_ticket.match_id;
        let current_match = match_pool.all_matches.borrow_mut(match_id);

        if(current_match.status == MatchStatus::RESOLVED 
            && (current_match.maker_score != 0 && current_match.taker_score != 0)) {
            if(current_match.maker_score > current_match.taker_score) {
                current_match.winner = current_match.maker;
                current_match.status = MatchStatus::SETTLED;

                let prize_amount = current_match.prize.value();
                transfer::public_transfer(
                    current_match.prize.split(prize_amount).into_coin(ctx),
                    ctx.sender(),
                )
            }
            else {
                current_match.winner = current_match.taker;
                current_match.status = MatchStatus::SETTLED;
                let prize_amount = current_match.prize.value();
                transfer::public_transfer(
                    current_match.prize.split(prize_amount).into_coin(ctx),
                    ctx.sender(),
                )
            }
        }
    }

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

    // public fun mint_nft(payment: Coin<SUI>, ctx: &mut TxContext): NFT {

    // }

    // public fun verify_ecvrf_output(output: vector<u8>, alpha_string: vector<u8>, public_key: vector<u8>, proof: vector<u8>) {
    //     event::emit(VerifiedEvent {is_verified: ecvrf::ecvrf_verify(&output, &alpha_string, &public_key, &proof)});
    // }
}