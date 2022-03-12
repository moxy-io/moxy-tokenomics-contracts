import FungibleToken from "./flow/FungibleToken.cdc"

pub contract MoxyToken: FungibleToken {

    /// Total supply of ExampleTokens in existence
    pub var totalSupply: UFix64
    
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
    pub resource Vault: FungibleToken.Provider, FungibleToken.Receiver, FungibleToken.Balance {

        /// The total balance of this vault
        pub var balance: UFix64

        // initialize the balance at resource creation time
        init(balance: UFix64) {
            self.balance = balance
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
            self.balance = self.balance - amount
            emit TokensWithdrawn(amount: amount, from: self.owner?.address)
            return <-create Vault(balance: amount)
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
            let vault <- from as! @MoxyToken.Vault
            self.balance = self.balance + vault.balance
            emit TokensDeposited(amount: vault.balance, to: self.owner?.address)
            vault.balance = 0.0
            destroy vault
        }

        destroy() {
            MoxyToken.totalSupply = MoxyToken.totalSupply - self.balance
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

    pub fun createEmptyLockedVault(): @LockedVault {
        return <-create LockedVault()
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
        pub fun mintTokens(amount: UFix64): @MoxyToken.Vault {
            pre {
                amount > 0.0: "Amount minted must be greater than zero"
                amount <= self.allowedAmount: "Amount minted must be less than the allowed amount"
            }
            MoxyToken.totalSupply = MoxyToken.totalSupply + amount
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
            let vault <- from as! @MoxyToken.Vault
            let amount = vault.balance
            destroy vault
            emit TokensBurned(amount: amount)
        }
    }

    pub resource LockedVault: Receiver, Balance {
        access(contract) var lockedBalances: {UFix64:UFix64}
        access(contract) var vault: @FungibleToken.Vault

        pub fun getBalance():UFix64 {
            return self.vault.balance
        }

        pub fun getLockedBalances(): {UFix64:UFix64} {
            return self.lockedBalances
        }

        pub fun deposit(from: @FungibleToken.Vault, time: UFix64) {
            let amount = from.balance
            self.vault.deposit(from: <-from)
            if (self.lockedBalances[time] == nil) {
                self.lockedBalances[time] = 0.0
            } 
            self.lockedBalances[time] = self.lockedBalances[time]! + amount
        }

        pub fun unlockOverdueMOX() {
            var total = 0.0
            let dict = self.getUnlockBalancesFor(days: 0.0)
            for key in dict.keys {
                let value = dict[key]!
                self.unlockBalance(timestamp: key)
            }
        }

        access(contract) fun unlockBalance(timestamp: UFix64) {
            // Obtener el valor del diccionario
            // hacer el withdraw
            // remover el valor del diccionario
            let amount = self.lockedBalances[timestamp]
            if (amount == nil) {
                return
            }
            let vault <- self.vault.withdraw(amount: amount!)
            // Buscar la referencia del vault receiver del usuario

            // Get a reference to the recipient's Receiver
            let userRef = self.owner!.getCapability(MoxyToken.moxyTokenReceiverPath)
                .borrow<&{FungibleToken.Receiver}>()
                ?? panic("Could not borrow receiver reference to the recipient's Vault")

            // Deposit the withdrawn tokens in the recipient's receiver
            userRef.deposit(from: <- vault)
            self.lockedBalances.remove(key: timestamp)
        }

        pub fun getTotalLockedBalance(): UFix64 {
            return self.vault.balance
        }

        pub fun getTotalToUnlockBalanceFor(days: UFix64): UFix64 {
            // Returns how many MOX will be unlocked in the next few days
            var total = 0.0
            var timestamp = getCurrentBlock().timestamp + (days * 86400.0)
            for key in self.lockedBalances.keys {
                if (key < timestamp) {
                    let value = self.lockedBalances[key]!
                    total = total + value
                }
            }
            return total
        }

        pub fun getUnlockBalancesFor(days: UFix64): {UFix64:UFix64} {
            // Returns a dictionary with the MOX that will be unlocked in the next few days
            var dict: {UFix64:UFix64} = {} 
            var timestamp = getCurrentBlock().timestamp + (days * 86400.0)
            for key in self.lockedBalances.keys {
                if (key < timestamp) {
                    dict[key] = self.lockedBalances[key]! 
                }
            }
            return dict
        }

        destroy() {
            destroy self.vault
        }

        init() {
            self.lockedBalances = {}
            self.vault <- MoxyToken.createEmptyVault()
        }
    }

    pub fun getTotalSuply(): UFix64 {
        return self.totalSupply
    }

    pub resource interface Receiver {

        /// deposit takes a Vault and deposits it into the implementing resource type
        ///
        pub fun deposit(from: @FungibleToken.Vault, time: UFix64)
        pub fun unlockOverdueMOX()
    }

    pub resource interface Balance {

        /// The total balance of a vault
        ///
        pub fun getBalance():UFix64
        pub fun getLockedBalances(): {UFix64:UFix64} 
        pub fun getTotalToUnlockBalanceFor(days: UFix64): UFix64 
        pub fun getTotalLockedBalance(): UFix64 
        
    }

    pub let moxyTokenVaultStorage: StoragePath
    pub let moxyTokenLockedVaultStorage: StoragePath
    pub let moxyTokenAdminStorage: StoragePath
    pub let moxyTokenReceiverPath: PublicPath
    pub let moxyTokenBalancePath: PublicPath
    pub let moxyTokenLockedBalancePath: PublicPath
    pub let moxyTokenLockedReceiverPath: PublicPath

    init() {
        // The initial total supply corresponds with the total amount
        // to release in the different Token allocations rounds
        self.totalSupply = 1500000000.0

        self.moxyTokenVaultStorage = /storage/moxyTokenVault
        self.moxyTokenLockedVaultStorage = /storage/moxyTokenLockedVault
        self.moxyTokenAdminStorage = /storage/moxyTokenAdmin
        self.moxyTokenReceiverPath = /public/moxyTokenReceiver
        self.moxyTokenBalancePath = /public/moxyTokenBalance
        self.moxyTokenLockedBalancePath = /public/moxyTokenLockedBalance
        self.moxyTokenLockedReceiverPath = /public/moxyTokenLockedReceiver
      
        // Create the Vault with the total supply of tokens and save it in storage
        //
        let vault <- create Vault(balance: self.totalSupply)
        self.account.save(<-vault, to: self.moxyTokenVaultStorage)

        // Create a public capability to the stored Vault that only exposes
        // the `deposit` method through the `Receiver` interface
        //
        self.account.link<&{FungibleToken.Receiver}>(
            self.moxyTokenReceiverPath,
            target: self.moxyTokenVaultStorage
        )

        // Create a public capability to the stored Vault that only exposes
        // the `balance` field through the `Balance` interface
        //
        self.account.link<&MoxyToken.Vault{FungibleToken.Balance}>(
            self.moxyTokenBalancePath,
            target: self.moxyTokenVaultStorage
        )

        // Create locked Vault and links
        let lockedVault <- create LockedVault()
        self.account.save(<-lockedVault, to: self.moxyTokenLockedVaultStorage)

        self.account.link<&MoxyToken.LockedVault{MoxyToken.Balance}>(
            self.moxyTokenLockedBalancePath,
            target: self.moxyTokenLockedVaultStorage
        )

        self.account.link<&{MoxyToken.Receiver}>(
            self.moxyTokenLockedReceiverPath,
            target: self.moxyTokenLockedVaultStorage
        )


        let admin <- create Administrator()
        self.account.save(<-admin, to: self.moxyTokenAdminStorage)

        // Emit an event that shows that the contract was initialized
        //
        emit TokensInitialized(initialSupply: self.totalSupply)
    }
}
 