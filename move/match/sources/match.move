module match::match {
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, ID, UID};
    use sui::coin::{Self, Coin};
    use sui::bag::{Bag, Self};
    use sui::table::{Table, Self};
    use sui::Clock::Clock;
    use sui::transfer;
    use sui::event;

    // === Structs ===
    public struct Match<phantom COIN> has key, store {
        id: UID,
        maker: address,
        taker: address,
        // status: 
        prize: Balance<SUI>
    }

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
    public fun join_pvp_game() {

    }

    fun create_match(ctx: &mut TxContext) {
        event::emit(TimeEvent { timestamp_ms: clock.timestamp_ms() });
    }

    fun join_match() {

    }

    /// Deposit money into liquidity pool
    fun deposit_pool(pool: &mut TournamentPool, deposit: Coin<Sui>) {
        balance::join(&mut pool.amount, coin:into_balance(deposit));
    }

    public fun view_score() {

    }

    public fun claim_prize() {

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