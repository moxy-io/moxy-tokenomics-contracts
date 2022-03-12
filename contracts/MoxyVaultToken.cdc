import FungibleToken from "./flow/FungibleToken.cdc"
//import FungibleToken from 0xee82856bf20e2aa6
pub contract MoxyVaultToken: FungibleToken {

    /// Total supply of ExampleTokens in existence
    pub var totalSupply: UFix64
    access(contract) var totalSupplies: {UFix64:UFix64}
    access(contract) var totalSupplyTimestampMap: [UFix64]

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
    pub resource Vault: FungibleToken.Provider, FungibleToken.Receiver, FungibleToken.Balance, DailyBalancesInterface, ReceiverInterface {

        /// The total balance of this vault
        pub var balance: UFix64
        access(contract) var dailyBalances: {UFix64:UFix64}
        access(contract) var timestampMap: [UFix64]

        // initialize the balance at resource creation time
        init(balance: UFix64) {
            self.balance = balance
            self.dailyBalances = {}
            self.timestampMap = []
        }

        pub fun getDailyBalanceFor(timestamp: UFix64): UFix64? {
            let time0000 = MoxyVaultToken.getTimestampTo0000(timestamp: timestamp)
            if (self.dailyBalances[time0000] == nil) {
                // For this day there are no registered balances, search for the
                // last recorded balance or zero if there are no previous records
                // per requested day
                var index = -1
                var hasActivity = false
                for time in self.timestampMap {
                    if (time >= time0000  ) {
                        hasActivity = true
                        break
                    }
                    index = index + 1
                }
                if (index < 0) {
                    // There is no previous activity
                    return 0.0
                }
                return self.dailyBalances[self.timestampMap[index]]
            }
            return self.dailyBalances[time0000]
        }

        pub fun getDailyBalanceForToday(): UFix64? {
            return self.getDailyBalanceFor(timestamp: getCurrentBlock().timestamp)
        }

        pub fun getDailyBalancesChanges(): {UFix64:UFix64} {
            let resu: {UFix64:UFix64} = {}
            var timeBefore = 0.0
            for time in self.timestampMap {
                resu[time] = self.dailyBalances[time]! - timeBefore
                timeBefore = self.dailyBalances[time]!
            }

            return resu
        }


        pub fun getDailyBalanceChange(timestamp: UFix64): UFix64 {
            let time0000 = MoxyVaultToken.getTimestampTo0000(timestamp: timestamp)

            if (self.timestampMap.length < 1) {
                // No records => no change
                return 0.0
            }
            if (self.timestampMap[0] > time0000 ) {
                // We query for a timestamp prior to the first one registered
                return 0.0
            }
            var lastTimestamp = self.getLastTimestampAdded()
            if (time0000 > lastTimestamp!) {
                // Check a date after the last one registered
                return 0.0
            }

            // Balance on date
            var tokenTimestamp = self.dailyBalances[time0000]
            
            if (tokenTimestamp == nil) {
                // The date has no records => no changes
                return 0.0
            }

            // We look for the last balance prior to the date
            if (self.timestampMap[0] == time0000 ) {
                // There is no previous, the change is the balance total
                return tokenTimestamp!
            }

            // There is a balance, we have to look for the previous balance to see
            // what was the change

            var index = 0
            for time in self.timestampMap {
                if (time == time0000) {
                    break
                }
                index = index + 1
            }
            let indexBefore = index - 1
            var tokenBefore = self.dailyBalances[self.timestampMap[indexBefore]]

            return tokenTimestamp! - tokenBefore!
        }

        pub fun getLastTimestampAdded(): UFix64? {
            let pos = self.timestampMap.length - 1
            if (pos < 0) {
                return nil
            }
            return self.timestampMap[pos]
        }

        pub fun getFirstTimestampAdded(): UFix64? {
            return self.timestampMap[0]
        }

        pub fun getTimestampToStart(timestamp: UFix64): UFix64 {
            let days = timestamp / 86400.0
            return UFix64(UInt64(days)) * 86400.0
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
            // Withdraw can't be done for MV token
            panic("MV can't be withdrawn")
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
            let time0000 = MoxyVaultToken.getTimestampTo0000(timestamp: timestamp)
            let lastTimestamp = self.getLastTimestampAdded()
            if (lastTimestamp == nil || time0000 > lastTimestamp!) {
                // Add record to array
                self.dailyBalances[time0000] = self.balance
                self.timestampMap.append(time0000)
            }
            self.dailyBalances[time0000] = self.dailyBalances[time0000]! + vault.balance           
            self.balance = self.balance + vault.balance

            emit TokensDeposited(amount: vault.balance, to: self.owner?.address)
            vault.balance = 0.0

            destroy vault       
        }


        destroy() {
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
            let time0000 = MoxyVaultToken.getTimestampTo0000(timestamp: timestamp)
            let lastTimestamp = MoxyVaultToken.getLastTotalSupplyTimestampAdded()

            if (lastTimestamp != nil && time0000 < lastTimestamp!) {
                panic("Cannot mint SCORE token for events before the last registerd")
            } 

            if (lastTimestamp == nil || time0000 > lastTimestamp!) {
                MoxyVaultToken.totalSupplyTimestampMap.append(time0000)
                MoxyVaultToken.totalSupplies[time0000] = MoxyVaultToken.totalSupply
            }

            MoxyVaultToken.totalSupplies[time0000] = MoxyVaultToken.totalSupplies[time0000]! + amount
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
        let pos = self.totalSupplyTimestampMap.length - 1
        if (pos < 0) {
            return nil
        }
        return self.totalSupplyTimestampMap[pos]
    }


    pub fun getTotalSupplyFor(timestamp: UFix64): UFix64 {
        let time0000 = self.getTimestampTo0000(timestamp: timestamp)
    
        if (MoxyVaultToken.totalSupplies[time0000] != nil) {
            return MoxyVaultToken.totalSupplies[time0000]!
        }

        // Check if there is any registered score
        if (MoxyVaultToken.totalSupplyTimestampMap.length < 1) {
            // No score registered yet
            return MoxyVaultToken.totalSupply
        }

        // Check if there is any registered score
        if (MoxyVaultToken.totalSupplyTimestampMap.length < 2) {
            // Only one record
            if (MoxyVaultToken.totalSupplyTimestampMap[0] > time0000 ) {
                // Returns zero because we are looking something prior to the first registered
                return 0.0
            }
            return MoxyVaultToken.totalSupplies[MoxyVaultToken.totalSupplyTimestampMap[0]]!
        }

        // Check the first score before the time0000
        var i = 0
        for time in MoxyVaultToken.totalSupplyTimestampMap {
            if (time > time0000) {
                break
            }
            i = i + 1
        }
        i = i - 1

        return MoxyVaultToken.totalSupplies[MoxyVaultToken.totalSupplyTimestampMap[i]]!
    }

    pub fun getDailyChangeTo(timestamp: UFix64): UFix64 {
        let time0000 = self.getTimestampTo0000(timestamp: timestamp)
        
        var lastTimestamp = self.getLastTotalSupplyTimestampAdded()
        var hasActivity = false
        var i = -1
        for time in MoxyVaultToken.totalSupplyTimestampMap {
            if (time == time0000) {
                hasActivity = true
                break
            }
            i = i + 1
        }

        if (!hasActivity) {
            // No activity found, this may be because the timestamp
            // is at a time lower than the first record 
            // or it is in the future, in which case the total supply is returned
            if (lastTimestamp != nil && lastTimestamp! < time0000) {
               return MoxyVaultToken.totalSupply 
            }
            return 0.0
        }

        if (MoxyVaultToken.totalSupplyTimestampMap.length < 1 || i < 0) {
            return MoxyVaultToken.totalSupplies[time0000]!
        }

        let prevValue = MoxyVaultToken.totalSupplyTimestampMap[i]

        let scoreTimestamp = MoxyVaultToken.totalSupplies[time0000]!
        let scoreYesterday = MoxyVaultToken.totalSupplies[prevValue]!
        
        return scoreTimestamp - scoreYesterday
    }


    pub resource interface DailyBalancesInterface {
        access(contract) var dailyBalances: {UFix64:UFix64}
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

    pub let moxyVaultTokenVaultStorage: StoragePath
    pub let moxyVaultTokenAdminStorage: StoragePath
    pub let moxyVaultTokenReceiverPath: PublicPath
    pub let moxyVaultTokenBalancePath: PublicPath
    pub let moxyVaultTokenDailyBalancePath: PublicPath
    pub let moxyVaultTokenReceiverTimestampPath: PublicPath

    init() {
        self.totalSupply = 0.0
        self.totalSupplies = {}
        self.totalSupplyTimestampMap = []

        self.moxyVaultTokenVaultStorage = /storage/moxyVaultTokenVault
        self.moxyVaultTokenAdminStorage = /storage/moxyVaultTokenAdmin
        self.moxyVaultTokenReceiverPath = /public/moxyVaultTokenReceiver
        self.moxyVaultTokenBalancePath = /public/moxyVaultTokenBalance
        self.moxyVaultTokenDailyBalancePath = /public/moxyVaultTokenDailyBalance
        self.moxyVaultTokenReceiverTimestampPath = /public/moxyVaultTokenReceiverTimestamp


        // Create the Vault with the total supply of tokens and save it in storage
        //
        let vault <- create Vault(balance: self.totalSupply)
        self.account.save(<-vault, to: self.moxyVaultTokenVaultStorage)

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

        let admin <- create Administrator()
        self.account.save(<-admin, to: self.moxyVaultTokenAdminStorage)


        // Emit an event that shows that the contract was initialized
        //
        emit TokensInitialized(initialSupply: self.totalSupply)
    }
}
 