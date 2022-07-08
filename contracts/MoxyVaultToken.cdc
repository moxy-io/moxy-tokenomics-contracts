import FungibleToken from "./flow/FungibleToken.cdc"
import LockedToken from "./LockedToken.cdc"
import MoxyData from "./MoxyData.cdc"

pub contract MoxyVaultToken: FungibleToken {

    /// Total supply of ExampleTokens in existence
    pub var totalSupply: UFix64
    access(contract) var totalSupplies: @MoxyData.OrderedDictionary

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

    pub event MVToMOXYConverterCreated(conversionAmount: UFix64, timestamp: UFix64)

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
    pub resource Vault: FungibleToken.Provider, FungibleToken.Receiver, FungibleToken.Balance, DailyBalancesInterface, ReceiverInterface {

        /// The total balance of this vault
        pub var balance: UFix64
        access(contract) var dailyBalances: @MoxyData.OrderedDictionary
        
//        access(contract) var dailyBalances: {UFix64:UFix64}
//        access(contract) var timestampMap: [UFix64]


        // initialize the balance at resource creation time
        init(balance: UFix64) {
            self.balance = balance
            self.dailyBalances <- MoxyData.createNewOrderedDictionary()
        }

        pub fun getDailyBalances(): {UFix64: UFix64} {
            return self.dailyBalances.getDictionary()
        }

        pub fun getDailyBalanceFor(timestamp: UFix64): UFix64? {
            return self.dailyBalances.getValueOrMostRecentFor(timestamp: timestamp)
        }

        pub fun getDailyBalanceForToday(): UFix64? {
            return self.dailyBalances.getValueForToday()
        }

        pub fun getDailyBalancesChanges(): {UFix64:UFix64} {
            return self.dailyBalances.getValueChanges()
        }

        pub fun getDailyBalanceChange(timestamp: UFix64): UFix64 {
            return self.dailyBalances.getValueChange(timestamp: timestamp)
        }

        pub fun getLastTimestampAdded(): UFix64? {
            return self.dailyBalances.getLastKeyAdded()
        }

        pub fun getFirstTimestampAdded(): UFix64? {
            return self.dailyBalances.getFirstKeyAdded()
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
            // Withdraw can only be done when a conversion MV to MOX is requested
            // withdraw are done from oldest deposits to newer deposits

            self.dailyBalances.withdrawValueFromOldest(amount: amount)
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
            let timestamp = getCurrentBlock().timestamp
            return self.depositFor(from: <-from, timestamp: timestamp)
        }

        pub fun depositFor(from: @FungibleToken.Vault, timestamp: UFix64) {
            let vault <- from as! @MoxyVaultToken.Vault

            self.dailyBalances.setAmountFor(timestamp: timestamp, amount: vault.balance)

            self.balance = self.balance + vault.balance

            emit TokensDeposited(amount: vault.balance, to: self.owner?.address)
            vault.balance = 0.0

            destroy vault       
        }

        pub fun createNewMVConverter(privateVaultRef: Capability<&FungibleToken.Vault>, allowedAmount: UFix64): @MVConverter {
            return <- create MVConverter(privateVaultRef: privateVaultRef, allowedAmount: allowedAmount)
        }
        
        destroy() {
            MoxyVaultToken.destroyTotalSupply(orderedDictionary: <- self.dailyBalances) 
            MoxyVaultToken.totalSupply = MoxyVaultToken.totalSupply - self.balance
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
        pub fun mintTokens(amount: UFix64): @MoxyVaultToken.Vault {
            let timestamp = getCurrentBlock().timestamp
            return <-self.mintTokensFor(amount: amount, timestamp: timestamp)
        }

        pub fun mintTokensFor(amount: UFix64, timestamp: UFix64): @MoxyVaultToken.Vault {
            pre {
                amount > 0.0: "Amount minted must be greater than zero"
                amount <= self.allowedAmount: "Amount minted must be less than the allowed amount"
            }

            if (!MoxyVaultToken.totalSupplies.canUpdateTo(timestamp: timestamp)) {
                panic("Cannot mint MV token for events before the last registerd")
            } 

            MoxyVaultToken.totalSupplies.setAmountFor(timestamp: timestamp, amount: amount)

            MoxyVaultToken.totalSupply = MoxyVaultToken.totalSupply + amount

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
            let vault <- from as! @MoxyVaultToken.Vault
            let amount = vault.balance
            destroy vault
            emit TokensBurned(amount: amount)
        }
    }

    pub fun getTimestampTo0000(timestamp: UFix64): UFix64 {
        let days = timestamp / 86400.0
        return UFix64(UInt64(days)) * 86400.0
    }

    pub fun getLastTotalSupplyTimestampAdded(): UFix64? {
        return self.totalSupplies.getLastKeyAdded()
    }


    pub fun getTotalSupplyFor(timestamp: UFix64): UFix64 {
        return self.totalSupplies.getValueOrMostRecentFor(timestamp: timestamp)
    }

    pub fun getDailyChangeTo(timestamp: UFix64): UFix64 {
        return self.totalSupplies.getValueChange(timestamp: timestamp)
    }

    pub resource MVConverter: Converter {
        pub var privateVaultRef: Capability<&FungibleToken.Vault>
        pub var allowedAmount: UFix64

        pub fun getDailyVault(amount: UFix64): @FungibleToken.Vault {
            pre {
                amount > 0.0: "Amount to burn must be greater than zero"
                amount <= self.allowedAmount: "Amount to burn must be equal or less than the allowed amount. Allowed amount: ".concat(self.allowedAmount.toString()).concat(" amount: ").concat(amount.toString())
            }
            self.allowedAmount = self.allowedAmount - amount
            let vault <- self.privateVaultRef.borrow()!.withdraw(amount: amount)
            
            return <-vault
        }

        init(privateVaultRef: Capability<&FungibleToken.Vault>, allowedAmount: UFix64 ) {
            self.privateVaultRef = privateVaultRef
            self.allowedAmount = allowedAmount
        }
    }

    pub resource interface DailyBalancesInterface {
        pub fun getDailyBalances(): {UFix64: UFix64}
        pub fun getDailyBalanceFor(timestamp: UFix64): UFix64? 
        pub fun getDailyBalanceForToday(): UFix64?
        pub fun getDailyBalanceChange(timestamp: UFix64): UFix64
        pub fun getLastTimestampAdded(): UFix64?
        pub fun getFirstTimestampAdded(): UFix64?
        pub fun getDailyBalancesChanges(): {UFix64:UFix64}
    }

    pub resource interface ReceiverInterface {
        pub fun depositFor(from: @FungibleToken.Vault, timestamp: UFix64) 
    }

    pub resource interface Converter {
        pub fun getDailyVault(amount: UFix64): @FungibleToken.Vault
    }

    pub fun createEmptyLockedVault(): @LockedToken.LockedVault {
        return <- LockedToken.createLockedVault(vault: <- self.createEmptyVault())
    }

    pub fun getTotalSupplies(): {UFix64: UFix64} {
        return self.totalSupplies.getDictionary()
    }

    pub fun destroyTotalSupply(orderedDictionary: @MoxyData.OrderedDictionary) {
        self.totalSupplies.destroyWith(orderedDictionary: <-orderedDictionary)
    }

    pub let moxyVaultTokenVaultStorage: StoragePath
    pub let moxyVaultTokenVaultPrivate: PrivatePath
    pub let moxyVaultTokenAdminStorage: StoragePath
    pub let moxyVaultTokenReceiverPath: PublicPath
    pub let moxyVaultTokenBalancePath: PublicPath
    pub let moxyVaultTokenDailyBalancePath: PublicPath
    pub let moxyVaultTokenReceiverTimestampPath: PublicPath
    // Paths for Locked tonkens 
    pub let moxyVaultTokenLockedVaultStorage: StoragePath
    pub let moxyVaultTokenLockedVaultPrivate: PrivatePath
    pub let moxyVaultTokenLockedBalancePath: PublicPath
    pub let moxyVaultTokenLockedReceiverPath: PublicPath

    init() {
        self.totalSupply = 0.0
        self.totalSupplies <- MoxyData.createNewOrderedDictionary()

        self.moxyVaultTokenVaultStorage = /storage/moxyVaultTokenVault
        self.moxyVaultTokenVaultPrivate = /private/moxyVaultTokenVault
        self.moxyVaultTokenAdminStorage = /storage/moxyVaultTokenAdmin
        self.moxyVaultTokenReceiverPath = /public/moxyVaultTokenReceiver
        self.moxyVaultTokenBalancePath = /public/moxyVaultTokenBalance
        self.moxyVaultTokenDailyBalancePath = /public/moxyVaultTokenDailyBalance
        self.moxyVaultTokenReceiverTimestampPath = /public/moxyVaultTokenReceiverTimestamp
        // Locked vaults
        self.moxyVaultTokenLockedVaultStorage = /storage/moxyVaultTokenLockedVault
        self.moxyVaultTokenLockedVaultPrivate = /private/moxyVaultTokenLockedVault
        self.moxyVaultTokenLockedBalancePath = /public/moxyVaultTokenLockedBalance
        self.moxyVaultTokenLockedReceiverPath = /public/moxyVaultTokenLockedReceiver

        // Create the Vault with the total supply of tokens and save it in storage
        //
        let vault <- create Vault(balance: self.totalSupply)
        self.account.save(<-vault, to: self.moxyVaultTokenVaultStorage)

        // Private access to MoxyVault token Vault
        self.account.link<&MoxyVaultToken.Vault>(
            self.moxyVaultTokenVaultPrivate,
            target: self.moxyVaultTokenVaultStorage
        )

        // Create a public capability to the stored Vault that only exposes
        // the `deposit` method through the `Receiver` interface
        //
        self.account.link<&{FungibleToken.Receiver}>(
            self.moxyVaultTokenReceiverPath,
            target: self.moxyVaultTokenVaultStorage
        )
        // Link to receive tokens in a specific timestamp
        self.account.link<&{MoxyVaultToken.ReceiverInterface}>(
            self.moxyVaultTokenReceiverTimestampPath,
            target: self.moxyVaultTokenVaultStorage
        )

        // Create a public capability to the stored Vault that only exposes
        // the `balance` field through the `Balance` interface
        //
        self.account.link<&MoxyVaultToken.Vault{FungibleToken.Balance}>(
            self.moxyVaultTokenBalancePath,
            target: self.moxyVaultTokenVaultStorage
        )
        self.account.link<&MoxyVaultToken.Vault{DailyBalancesInterface}>(
            self.moxyVaultTokenDailyBalancePath,
            target: self.moxyVaultTokenVaultStorage
        )

        // Create locked Vault and links
        let lockedVault <- self.createEmptyLockedVault()
        self.account.save(<-lockedVault, to: self.moxyVaultTokenLockedVaultStorage)

        self.account.link<&LockedToken.LockedVault>(
            self.moxyVaultTokenLockedVaultPrivate,
            target: self.moxyVaultTokenLockedVaultStorage
        )

        self.account.link<&LockedToken.LockedVault{LockedToken.Balance}>(
            self.moxyVaultTokenLockedBalancePath,
            target: self.moxyVaultTokenLockedVaultStorage
        )

        self.account.link<&{LockedToken.Receiver}>(
            self.moxyVaultTokenLockedReceiverPath,
            target: self.moxyVaultTokenLockedVaultStorage
        )

        let admin <- create Administrator()
        self.account.save(<-admin, to: self.moxyVaultTokenAdminStorage)


        // Emit an event that shows that the contract was initialized
        //
        emit TokensInitialized(initialSupply: self.totalSupply)
    }
}
 