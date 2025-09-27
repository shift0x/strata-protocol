// margin accounts are isolated per market and user. This mitigates bad debt risk and
// enables efficent partial liquidiation of user margin accounts when needeed.
module marketplace::isolated_margin_account {
    use std::signer::{Self};
    use aptos_framework::object::{Self, Object, ExtendRef};
    
    friend marketplace::implied_volatility_market;
    
    struct AccountRefs has key {
        extend_ref: object::ExtendRef
    }

    struct IsolatedMarginAccount has key, copy, drop {
        // address of the user that the account belongs to
        user_address: address,
        // the amount of iv units borrowed
        iv_units_borrowed: u64,
        // collateral
        collateral: u64
    }

    /// Create a new isolated margin account
    public(friend) fun new(user_address: address): address {
        let margin_account = IsolatedMarginAccount {
            user_address,
            iv_units_borrowed: 0,
            collateral: 0
        };

        // Create object to hold the margin account
        let constructor_ref = object::create_object(user_address);
        let object_signer = object::generate_signer(&constructor_ref);
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let object_addr = signer::address_of(&object_signer);

        // Store the margin account in the object
        move_to(&object_signer, margin_account);
        move_to(&object_signer, AccountRefs { extend_ref });

        object_addr
    }

    /// Get the margin account state
    #[view]
    public fun get_margin_account_state(
        account_address: address
    ) : IsolatedMarginAccount acquires IsolatedMarginAccount {
        *borrow_global<IsolatedMarginAccount>(account_address)
    }

    #[view]
    public fun empty(
        account_address: address
    ): IsolatedMarginAccount {
        IsolatedMarginAccount {
            user_address: account_address,
            iv_units_borrowed: 0,
            collateral: 0
        }
    }

    public(friend) fun record_new_borrow(
        account_address: address, 
        iv_units_borrowed: u64,
        collateral_amount: u64
    ) acquires IsolatedMarginAccount {
        let margin_account = borrow_global_mut<IsolatedMarginAccount>(account_address);

        margin_account.iv_units_borrowed = margin_account.iv_units_borrowed + iv_units_borrowed;
        margin_account.collateral = margin_account.collateral + collateral_amount;
    }

    public(friend) fun get_signer(
        margin_account_address: address
    ) : signer acquires AccountRefs {
        let refs = borrow_global<AccountRefs>(margin_account_address);
        
        object::generate_signer_for_extending(&refs.extend_ref)
    }

    /// Subtract from IV units borrowed
    public(friend) fun subtract_iv_units_borrowed(
        account_address: address, 
        amount: u64
    ) acquires IsolatedMarginAccount {
        let margin_account = borrow_global_mut<IsolatedMarginAccount>(account_address);
        margin_account.iv_units_borrowed = margin_account.iv_units_borrowed - amount;
    }

    /// Subtract from collateral
    public(friend) fun subtract_collateral(account: &mut IsolatedMarginAccount, amount: u64) {
        account.collateral = account.collateral - amount;
    }

    // Getter functions for IsolatedMarginAccount fields
    
    /// Get the user address from a margin account
    public fun get_user_address(account: &IsolatedMarginAccount): address {
        account.user_address
    }

    /// Get the IV units borrowed from a margin account
    public fun get_iv_units_borrowed(account: &IsolatedMarginAccount): u64 {
        account.iv_units_borrowed
    }

    /// Get the collateral amount from a margin account
    public fun get_collateral(account: &IsolatedMarginAccount): u64 {
        account.collateral
    }
}
