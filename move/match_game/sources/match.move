module match_game::match_game {
    use sui::sui::SUI;
    use sui::tx_context::{TxContext};
    use sui::object::{Self, ID, UID};
    use sui::coin::{Self, Coin};
    use sui::bag::{Self};
    use sui::table::{Table, Self};
    use sui::balance::{Self, Balance};
    use sui::random::{Random, new_generator};
    use sui::clock;
    use sui::clock::Clock;
    use sui::transfer;
    use sui::event;
    use sui::ecvrf;
    use std::vector;

    // ====== Errors ======
    // Not enough funds for entry fees
    // const EEntryFee: u64 = 0;
    // // Match is in progress
    // const EMatchInProgress: u64 = 1;

    // const EGameInProgress: u64 = 0;
    // const EGameAlreadyCompleted: u64 = 1;
    // const EInvalidAmount: u64 = 2;
    // const EGameMismatch: u64 = 3;
    // const ENotWinner: u64 = 4;
    // const ENoParticipants: u64 = 5;

    // ====== General Structs ======
    public struct GameMatch has key, store {
        id: UID,
        maker: address,
        taker: Option<address>,
        status: MatchStatus,
         prize: Balance<SUI>
    }

    // ====== PVP Structs ======

    // We can also call this an "order book"
    public struct PVPMatchPool has key, store {
        id: UID,
        matches: vector<GameMatch>
        // IRVIN: Ask about what data structure to use
    }

    // === Tournament Structs ===
    public struct TournamentPool has key {
        id: UID,
        amount: Balance<SUI>
    }

    public struct EntryTicketNFT has key {
        id: UID,
        entry_fee: Balance<SUI>,
        timestamp_ms: u64 
    }

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
        match_id: ID,
        maker: address,
        timestamp_ms: u64
    }
    // public struct MatchCreatedEvent has copy, drop, store {
    //     gameMatch: GameMatch
    // }

    // ====== Functions ======

    // Initialized called only once on module publish
    fun init(ctx: &mut TxContext) {
        let id = object::new(ctx);
        let matches = vector::empty<GameMatch>();
        let matchPool = PVPMatchPool {
            id,
            matches
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
    public entry fun join_pvp_game(
        entry_fee: Coin<SUI>,
        match_pool: &mut PVPMatchPool,
        r: &Random,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // STEP 1: If there's a list of "OPEN" matches, match with a "random" one
        if (vector::length(&match_pool.matches) > 0) {
            // STEP 2: Join random match
            join_match(entry_fee, match_pool, r, ctx);
        }
        else {
            // STEP 2: Create match
            // IRVIN: Ask about how to call function internally
            create_match(entry_fee, match_pool, clock, ctx);
        }
    }

    // Create a match.
    // From the game's perspective, the player creating the match is called
    // a "Maker".
    fun create_match(
        entry_fee: Coin<SUI>,
        match_pool: &mut PVPMatchPool,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let maker = tx_context::sender(ctx);
        let id = object::new(ctx);
        let gameMatch: GameMatch = GameMatch {
            id: id,
            maker: maker,
            taker: option::some(tx_context::sender(ctx)), // TODO: Fix this
            status: MatchStatus::OPEN,
            prize: coin::into_balance(entry_fee)
        };

        let timestamp_ms = clock.timestamp_ms();
        let matchCreatedEvent = MatchCreatedEvent {
            match_id: gameMatch.id.uid_to_inner(),
            maker,
            timestamp_ms,
        };
        match_pool.matches.push_back(gameMatch);
        event::emit(matchCreatedEvent)
    }

    // 
    fun join_match(
        entry_fee: Coin<SUI>,
        match_pool: &mut PVPMatchPool,
        r: &Random,
        ctx: &mut TxContext
    ) {
        // assert!(entry_fee <= balance::value(&pool.amount), ELoanAmountExceedPool);

        let player = tx_context::sender(ctx);
        let matches_len = vector::length(&match_pool.matches);

        if(matches_len == 1) {
            let matchPaired = &mut match_pool.matches[0];
            matchPaired.taker = option::some(player);
            matchPaired.status = MatchStatus::IN_PROGRESS;
            // matchPaired.prize = coin::into_balance(entry_fee);
            matchPaired.prize.join(entry_fee.into_balance());
        }
        else
        {
            let mut generator = r.new_generator(ctx);
            let rand_index = generator.generate_u64_in_range(0, matches_len);
            let matchPaired = match_pool.matches.borrow_mut(rand_index);
            matchPaired.taker = option::some(tx_context::sender(ctx));
            matchPaired.status = MatchStatus::IN_PROGRESS;

            balance::join(&mut matchPaired.prize, coin::into_balance(entry_fee));
        }
    }

    // public submit_match_result(

    // ) {

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