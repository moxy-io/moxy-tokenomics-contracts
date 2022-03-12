import FungibleToken from "./flow/FungibleToken.cdc"
// import FungibleToken from 0xee82856bf20e2aa6

pub contract PlayToken: FungibleToken {

    /// Total supply of ExampleTokens in existence
    pub var totalSupply: UFix64
    access(contract) var totalSupplies24: {UFix64:UFix64}

    /// TokensInitialized
    ///
    /// The event that is emitted when the contract is created
    pub event TokensInitialized(initialSupply: UFix64)

    /// TokensWithdrawn
    ///
    /// The event that is emitted when tokens are withdrawn from a Vault
    pub event TokensWithdrawn(amount: UFix64, from: Address?)

    /// TokensDeposited
    ///
    /// The event that is emitted when tokens are deposited to a Vault
    pub event TokensDeposited(amount: UFix64, to: Address?)

    /// TokensMinted
    ///
    /// The event that is emitted when new tokens are minted
    pub event TokensMinted(amount: UFix64)

    /// TokensBurned
    ///
    /// The event that is emitted when tokens are destroyed
    pub event TokensBurned(amount: UFix64)

    /// MinterCreated
    ///
    /// The event that is emitted when a new minter resource is created
    pub event MinterCreated(allowedAmount: UFix64)

    /// BurnerCreated
    ///
    /// The event that is emitted when a new burner resource is created
    pub event BurnerCreated()

    /// Vault
    ///
    /// Each user stores an instance of only the Vault in their storage
    /// The functions in the Vault and governed by the pre and post conditions
    /// in FungibleToken when they are called.
    /// The checks happen at runtime whenever a function is called.
    ///
    /// Resources can only be created in the context of the contract that they
    /// are defined in, so there is no way for a malicious user to create Vaults
    /// out of thin air. A special Minter resource needs to be defined to mint
    /// new tokens.
    ///
    pub resource Vault: FungibleToken.Provider, FungibleToken.Receiver, FungibleToken.Balance, DailyBalancesInterface {

        /// The total balance of this vault
        pub var balance: UFix64
        access(contract) var dailyBalances: {UFix64:UFix64}

        // initialize the balance at resource creation time
        init(balance: UFix64) {
            self.balance = balance
            self.dailyBalances = {}
        }

        pub fun getDailyBalances(): {UFix64: UFix64} {
            return self.dailyBalances
        }

        pub fun getDailyBalanceFor(timestamp: UFix64): UFix64? {
            var value = self.dailyBalances[timestamp]
            if (value == nil) {
                value = 0.0
            }
            return value
        }

        /// withdraw
        ///
        /// Function that takes an amount as an argument
        /// and withdraws that amount from the Vault.
        ///
        /// It creates a new temporary Vault that is used to hold
        /// the money that is being transferred. It returns the newly
        /// created Vault to the context that called so it can be deposited
        /// elsewhere.
        ///
        pub fun withdraw(amount: UFix64): @FungibleToken.Vault {
           // PLAY Tokens can't be transferred
            panic("PLAY can't be withdrawn")
        }

        /// deposit
        ///
        /// Function that takes a Vault object as an argument and adds
        /// its balance to the balance of the owners Vault.
        ///
        /// It is allowed to destroy the sent Vault because the Vault
        /// was a temporary holder of the tokens. The Vault's balance has
        /// been consumed and therefore can be destroyed.
        ///
        pub fun deposit(from: @FungibleToken.Vault) {
            let vault <- from as! @PlayToken.Vault
            
            let time0000 = PlayToken.getTimestampTo0000(timestamp: getCurrentBlock().timestamp)
            if (self.dailyBalances[time0000] == nil) {
                self.dailyBalances[time0000] = self.balance
            }
            self.dailyBalances[time0000] = self.dailyBalances[time0000]! + vault.balance

            self.balance = self.balance + vault.balance

            emit TokensDeposited(amount: vault.balance, to: self.owner?.address)
            vault.balance = 0.0
            destroy vault
        }

        destroy() {
            // Updating total supply registered daily
            let time0000 = PlayToken.getTimestampTo0000(timestamp: getCurrentBlock().timestamp)
            if (PlayToken.totalSupplies24[time0000] == nil) {
                PlayToken.totalSupplies24[time0000] = PlayToken.totalSupply
            }
            PlayToken.totalSupplies24[time0000] = PlayToken.totalSupplies24[time0000]! - self.balance

            PlayToken.totalSupply = PlayToken.totalSupply - self.balance
        }
    }

    /// createEmptyVault
    ///
    /// Function that creates a new Vault with a balance of zero
    /// and returns it to the calling context. A user must call this function
    /// and store the returned Vault in their storage in order to allow their
    /// account to be able to receive deposits of this token type.
    ///
    pub fun createEmptyVault(): @Vault {
        return <-create Vault(balance: 0.0)
    }

    pub resource Administrator {

        /// createNewMinter
        ///
        /// Function that creates and returns a new minter resource
        ///
        pub fun createNewMinter(allowedAmount: UFix64): @Minter {
            emit MinterCreated(allowedAmount: allowedAmount)
            return <-create Minter(allowedAmount: allowedAmount)
        }

        /// createNewBurner
        ///
        /// Function that creates and returns a new burner resource
        ///
        pub fun createNewBurner(): @Burner {
            emit BurnerCreated()
            return <-create Burner()
        }
    }

    /// Minter
    ///
    /// Resource object that token admin accounts can hold to mint new tokens.
    ///
    pub resource Minter {

        /// The amount of tokens that the minter is allowed to mint
        pub var allowedAmount: UFix64

        /// mintTokens
        ///
        /// Function that mints new tokens, adds them to the total supply,
        /// and returns them to the calling context.
        ///
        pub fun mintTokens(amount: UFix64): @PlayToken.Vault {
            pre {
                amount > 0.0: "Amount minted must be greater than zero"
                amount <= self.allowedAmount: "Amount minted must be less than the allowed amount"
            }
            // Updating total supply registered daily
            let time0000 = PlayToken.getTimestampTo0000(timestamp: getCurrentBlock().timestamp)
            if (PlayToken.totalSupplies24[time0000] == nil) {
                PlayToken.totalSupplies24[time0000] = PlayToken.totalSupply
            }
            PlayToken.totalSupplies24[time0000] = PlayToken.totalSupplies24[time0000]! + amount

            PlayToken.totalSupply = PlayToken.totalSupply + amount
            self.allowedAmount = self.allowedAmount - amount
            emit TokensMinted(amount: amount)
            return <-create Vault(balance: amount)
        }

        init(allowedAmount: UFix64) {
            self.allowedAmount = allowedAmount
        }
    }

    /// Burner
    ///
    /// Resource object that token admin accounts can hold to burn tokens.
    ///
    pub resource Burner {

        /// burnTokens
        ///
        /// Function that destroys a Vault instance, effectively burning the tokens.
        ///
        /// Note: the burned tokens are automatically subtracted from the
        /// total supply in the Vault destructor.
        ///
        pub fun burnTokens(from: @FungibleToken.Vault) {
            let vault <- from as! @PlayToken.Vault
            let amount = vault.balance
            destroy vault
            emit TokensBurned(amount: amount)
        }
    }

    pub fun getTimestampTo0000(timestamp: UFix64): UFix64 {
        let days = timestamp / 86400.0
        return UFix64(UInt64(days)) * 86400.0
    }

    pub fun getTotalSupplyFor(timestamp: UFix64): UFix64 {
        let time0000 = self.getTimestampTo0000(timestamp: timestamp)
        
        if (PlayToken.totalSupplies24[time0000] == nil) {
            PlayToken.totalSupplies24[time0000] = PlayToken.totalSupply
        }
        return PlayToken.totalSupplies24[time0000]!
    }

    pub resource interface DailyBalancesInterface {
        pub fun getDailyBalances(): {UFix64: UFix64}
        pub fun getDailyBalanceFor(timestamp: UFix64): UFix64? 
    }

    pub let playTokenVaultStorage: StoragePath
    pub let playTokenAdminStorage: StoragePath
    pub let playTokenReceiverPath: PublicPath
    pub let playTokenBalancePath: PublicPath
    pub let playTokenDailyBalancePath: PublicPath

    init() {
        // Initial total supply defined for PLAY token to starting strength
        // of Proof of Play
        self.totalSupply = 300000000.0
        self.totalSupplies24 = {}

        self.playTokenVaultStorage = /storage/playTokenVault
        self.playTokenAdminStorage = /storage/playTokenAdmin
        self.playTokenReceiverPath = /public/playTokenReceiver
        self.playTokenBalancePath = /public/playTokenBalance
        self.playTokenDailyBalancePath = /public/playTokenDailyBalancePath

        // Create the Vault with the total supply of tokens and save it in storage
        //
        let vault <- create Vault(balance: self.totalSupply)
        self.account.save(<-vault, to: self.playTokenVaultStorage)

        // Create a public capability to the stored Vault that only exposes
        // the `deposit` method through the `Receiver` interface
        //
        self.account.link<&{FungibleToken.Receiver}>(
            self.playTokenReceiverPath ,
            target: self.playTokenVaultStorage
        )

        // Create a public capability to the stored Vault that only exposes
        // the `balance` field through the `Balance` interface
        //
        self.account.link<&PlayToken.Vault{FungibleToken.Balance}>(
            self.playTokenBalancePath,
            target: self.playTokenVaultStorage
        )

        self.account.link<&PlayToken.Vault{FungibleToken.Balance}>(
            self.playTokenDailyBalancePath,
            target: self.playTokenVaultStorage
        )

        let admin <- create Administrator()
        self.account.save(<-admin, to: self.playTokenAdminStorage)

        // Emit an event that shows that the contract was initialized
        //
        emit TokensInitialized(initialSupply: self.totalSupply)
    }
}
 