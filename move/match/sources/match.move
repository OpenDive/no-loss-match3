module match::match {
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, ID, UID};
    use sui::coin::{Self, Coin};
    use sui::bag::{Bag, Self};
    use sui::table::{Table, Self};
    use sui::Clock::Clock;
    use sui::transfer;
    use sui::event;

    // === General Structs ===
    public struct GameMatch<phantom COIN> has key, store {
        id: UID,
        maker: address,
        taker: address,
        status: MatchStatus,
        prize: Balance<SUI>
    }

    // === PVP Structs ===

    /// We can also call this an "order book"
    public struct PVPMatchPool has key, store {
        id: UID,
        // matches: Bag,
        matches: Table<address, Match> 
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

    public enum MatchStatus {
        OPEN, // Available (waiting for a Taker)
        IN_PROGRESS, // Matched (while Taker plays).
        RESOLVED, // Scores have been resolved, both scores are in and winner determined.
        SETTLED, // Winner has claimed prize. Prize settled.
        EXPIRED, // Edge Case -- we set a limit to the match being opend
        CANCELLED, // Edge Case -- the "maker" player can pay a fee to cancel match if they don't like their score
        VOIDED, // Edge Case -- some issues might have happened
    }

    // === Events ===

    /// Event marking a match created. 
    /// The "maker" is the player that "created" this match.
    public struct MatchCreatedEvent has copy, drop, store {
        match_id: ID,
        maker: address,
        timestamp_ms: u64
    }

    /// Initialized called only once on module publish
    fun init(ctx: &mut TxContext) {
        let id = id: object::new(ctx);
        // let matches = table::new(ctx);
        let matches = table::new<address, Match>(ctx);

        let matchPool = PVPMatchPool {
            id,
            matches
        }
    }

    /// Player joins PVP game
    /// STEP 1. Check if player has an opened match.
    ///         If player has an open match, then create a new match
    ///         Do not match player with his older match
    /// STEP 2. If player does not have an opened match & not matches in pool.
    ///         Create a new match.
    /// STEP 3. If there are matches available in pool.
    ///         Join "random" match.
    ///         NOTE: match that player is joining already has a score.
    ///         QUESTION: Will score be hidden?
    fun join_pvp_game(
        entry_fee: Coin<SUI>,
        ctx: &mut: TxContext
    ) {
        // STEP 1: If there's a list of "OPEN" matches, match with a "random" one
        if (table::length(&matchPool) != 0) {
            // STEP 2: Join random match
            join_match(entry_fee)
        }
        else {
            // STEP 2: Create match
            // IRVIN: Ask about how to call function internally
            create_match(entry_fee);
        }
    }

    /// Create a match.
    /// From the game's perspective, the player creating the match is called
    /// a "Maker".
    fun create_match(entry_fee: Coin<SUI>, ctx: &mut TxContext) {
        GameMatch {
            id: object::new(ctx),
            maker: tx_context,
            // taker: address,
            status: MatchStatus.OPEN,
            prize: coin::into_balance(entry_fee)
        }
        event::emit(TimeEvent { timestamp_ms: clock.timestamp_ms() });
    }

    /// 
    fun join_match(
        entry_fee: Coin<SUI>,
        ctx: &mut: TxContext
    ) {
        let player = tx_context::sender(ctx);
        // IRVIN: Create VRF
        // Select random entry from table
        // Insert match
    }

    public fun view_match_score() {
    }

    /// Deposit money into liquidity pool
    fun deposit_pool(pool: &mut TournamentPool, deposit: Coin<Sui>) {
        balance::join(&mut pool.amount, coin:into_balance(deposit));
    }

    public fun claim_prize(match: &mut Match, ctx: &mut TxContext) {
        assert(match.status == MatchStatus.RESOLVED);
    }

    public fun mint_nft(payment: Coin<SUI>, ctx: &mut TxContext): NFT {

    }
}

// 1. public `create_match` 
// 2. `stake_entry_fee`
// 3. `deposit_to_pool`
// 4. public `start_match` 
// 5. public `end_match` 
// 6. public `claim_prize`
// 7. public `claim_entry_fee`