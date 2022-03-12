import PlayToken from "./PlayToken.cdc"
import ScoreToken from "./ScoreToken.cdc"
import MoxyToken from "./MoxyToken.cdc"
import MoxyVaultToken from "./MoxyVaultToken.cdc"
import FungibleToken from "./flow/FungibleToken.cdc"

pub contract MoxyClub {

    pub event AccountAdded(address: Address)
    pub event RoundAdded(name: String)

    // Fee Charged event on MOX transfer
    pub event FeeCharged(amount: UFix64)

    // Treasury repurchase event triggered when Treasury wallet has received MOX tokens
    // This will enforce PLAY token with the 10% of MOX received on a 2:1 MOX to PLAY
    // conversion 
    pub event TreasuryRepurchase(amount: UFix64)

   pub struct TokensEpochInfo {
        pub var dailyActivityUpdatedTimestamp: UFix64
        access(contract) var rewardsMVHoldings: {UFix64:UFix64}
        access(contract) var conversionVaultMVToMOX: Capability<&ConversionVault>?

        pub fun setDailyActivityUpdatedTimestamp(timestamp: UFix64) {
            self.dailyActivityUpdatedTimestamp = timestamp
        }

        pub fun setMOXRewardsDueMVHoldingsFor(timestamp: UFix64, amount: UFix64) {
            self.rewardsMVHoldings[timestamp] = amount
        }

        pub fun setConversionVaultMVToMOXFor(address: Address, capabilityRef: Capability<&ConversionVault>){
            if (self.conversionVaultMVToMOX == nil) {
                self.conversionVaultMVToMOX = capabilityRef
            }
        }

        pub fun createConversionVaultMVToMOXCapabilityFor(acct: AuthAccount): Capability<&ConversionVault> {
            
            // Creates the capability if it not exists on user storage
            // Create ConversionVault for MV to MOX conversions 
            let conversionVault <- MoxyClub.createEmptyConversionVault()
            acct.save(<-conversionVault, to: MoxyClub.convertMVToMOXStorage)

            let privateRef = acct.link<&MoxyClub.ConversionVault>(
                MoxyClub.convertMVToMOXPrivate,
                target: MoxyClub.convertMVToMOXStorage
            )

            acct.link<&MoxyClub.ConversionVault{MoxyClub.ConversionVaultInterface}>(
                MoxyClub.convertMVToMOXInfoPublic,
                target: MoxyClub.convertMVToMOXStorage
            )

            self.conversionVaultMVToMOX = privateRef
            
            return self.conversionVaultMVToMOX!
        }


        init(){
            self.dailyActivityUpdatedTimestamp = 0.0
            self.rewardsMVHoldings = {}
            self.conversionVaultMVToMOX = nil
        }
    }
 
    pub resource Wallets {
        access(contract) let wallets: {Address:TokensEpochInfo}
    
        /// Fee amount to charge on MOX transactions
        pub var feeAmount: UFix64
        pub var percentFeeToPLAY: UFix64
        pub var treasuryAddress: Address?

        pub fun setTreasuryAddress(address: Address) {
            self.treasuryAddress = address
        }

        pub fun isMoxyAccount(address: Address): Bool {
            return (self.wallets[address] != nil)
        }

        pub fun getAddress(address: Address):TokensEpochInfo {
            return self.wallets[address]!
        }

        pub fun addAddress(address: Address){
            
            // Only add the account if it doesn't exists
            if (self.wallets[address] == nil) {
                self.wallets[address] = TokensEpochInfo()
                emit MoxyClub.AccountAdded(address: address)
            }
        }

        pub fun getPlayBalanceFor(address: Address, timestamp: UFix64): UFix64? {
            let acct = getAccount(address)
            let vaultRef = acct.getCapability(PlayToken.playTokenDailyBalancePath)
                    .borrow<&PlayToken.Vault{PlayToken.DailyBalancesInterface}>()
                    ?? panic("Could not borrow Balance reference to the Vault")
            return vaultRef.getDailyBalanceFor(timestamp: timestamp)
        }
 
        pub fun getScoreBalanceFor(address: Address, timestamp: UFix64): UFix64? {
            let acct = getAccount(address)
            let vaultRef = acct.getCapability(ScoreToken.scoreTokenDailyBalancePath)
                .borrow<&ScoreToken.Vault{ScoreToken.DailyBalancesInterface}>()
                ?? panic("Could not borrow Balance reference to the Vault")
            return vaultRef.getDailyBalanceFor(timestamp: timestamp)
        }
        
        pub fun getDailyBalanceChangeFor(address: Address, timestamp: UFix64): UFix64 {
            let acct = getAccount(address)
            let vaultRef = acct.getCapability(ScoreToken.scoreTokenDailyBalancePath)
                .borrow<&ScoreToken.Vault{ScoreToken.DailyBalancesInterface}>()
                ?? panic("Could not borrow Balance reference to the Vault")
            
            return vaultRef.getDailyBalanceChange(timestamp: timestamp)
        }

        pub fun getScore24TotalSupplyChange(timestamp: UFix64): UFix64 {
            return ScoreToken.getDailyChangeTo(timestamp: timestamp)
        }

        pub fun calculateRewardsDueMVHoldingsTo(address: Address, timestamp: UFix64): UFix64 {

            let time0000 = MoxyClub.getTimestampTo0000(timestamp: timestamp)

            let acct = getAccount(address)
            let vaultRef = acct.getCapability(MoxyVaultToken.moxyVaultTokenDailyBalancePath)
                .borrow<&MoxyVaultToken.Vault{MoxyVaultToken.DailyBalancesInterface}>()
                ?? panic("Could not borrow Balance reference to the Vault")

            let balanceRef = acct.getCapability(MoxyVaultToken.moxyVaultTokenBalancePath)
                .borrow<&MoxyVaultToken.Vault{FungibleToken.Balance}>()
                ?? panic("Could not borrow Balance reference to the Vault")
            
            var rewardsMox = 0.0
            let balancesChanges = vaultRef.getDailyBalancesChanges()
            for time in balancesChanges.keys {

                // Daily Linear Appreciation over Time
                let days = (time0000 - time) / 86400.0
                let amount = balancesChanges[time]!
                var percentage = UFix64(UInt64((days / 365.0) + 1.0))
                
                // Maximum APY Gain 10 Year @ 10% APY 
                if (percentage > 10.0) {
                    percentage = 10.0
                }
                percentage = UFix64(percentage / 100.0 / 365.0)
                rewardsMox = rewardsMox + (amount * percentage)
            }
            let totalMV = balanceRef.balance

            // Maximum Holdings Modifier
            if (totalMV > 10000000.0) {
                rewardsMox = rewardsMox + (totalMV * 0.05 / 365.0)
            }

            return rewardsMox
        }

        pub fun rewardDueMVHoldingsToAllAddresses(timestamp: UFix64) {
            for address in self.wallets.keys {
                self.rewardDueMVHoldingsTo(address: address, timestamp: timestamp)
            }
        }

        pub fun rewardDueMVHoldingsTo(address: Address, timestamp: UFix64) {

            let time0000 = MoxyClub.getTimestampTo0000(timestamp: timestamp)
            if (self.wallets[address] == nil) {
                panic("Address not found in Moxy Club ecosystem")
            }

            // Moxy Vault rewards are paid in MOX, calculated by each user's MV holding  
            let rewardMOX = self.calculateRewardsDueMVHoldingsTo(address: address, timestamp: time0000) 
            if (rewardMOX > 0.0) {
                
                // Mint corresponding MOX tokens to user's account
                self.mintMOXToAddress(address: address, amount: rewardMOX)

                // Update the minted timestamp (TokenEpoch)
                self.wallets[address]!.setMOXRewardsDueMVHoldingsFor(timestamp: time0000, amount: rewardMOX)
            }
        }

        pub fun rewardDueDailyActivityToAllAddresses(timestamp: UFix64) {
            for address in self.wallets.keys {
                self.rewardDueDailyActivityTo(address: address, timestamp: timestamp)
            }
        }

        pub fun rewardDueDailyActivityTo(address: Address, timestamp: UFix64) {
            
            // PLAY + SCORE + SCORE24
            let timeTo0000 = MoxyClub.getTimestampTo0000(timestamp: timestamp)

            if (self.wallets[address] == nil) {
                panic("Address not found while rewarding due daily activity.")
            }

            let ecosystemScore24ChangeDict:{UFix64:UFix64} = self.getTotalSupply24DueForProcessTo(address: address, toTimestamp: timeTo0000)
            
            for time0000 in ecosystemScore24ChangeDict.keys {

                // Pull PLAY from user
                var play = self.getPlayBalanceFor(address: address, timestamp: time0000)
                // Pull SCORE from user
                var score = self.getScoreBalanceFor(address: address, timestamp: time0000)
                // Pull SCORE change from user
                var change = self.getDailyBalanceChangeFor(address: address, timestamp: time0000)
                // Pull totalSupply from PLAY, SCORE and SCORE24 (change in score)
                let ecosystemPlayTotalSupply = PlayToken.getTotalSupplyFor(timestamp: time0000)
                let ecosystemScoreTotalSupply = ScoreToken.getTotalSupplyFor(timestamp: time0000)
                let ecosystemScore24Change = self.getScore24TotalSupplyChange(timestamp: time0000)

                if (play == nil) { play = 0.0}
                if (score == nil) { score = 0.0}
                if (change == nil) { change = 0.0}

                let highScore = ecosystemPlayTotalSupply * (1.0/100.0) / 365.0 * (25.0/100.0) * (score! / ecosystemScoreTotalSupply)
                var score24Change = 0.0
                if (ecosystemScore24Change != 0.0) {
                    // If SCORE changed
                    score24Change = ecosystemPlayTotalSupply * (1.0/100.0) / 365.0 * (55.0/100.0) * (change / ecosystemScore24Change)
                }
                let donationLevelProgression = ecosystemPlayTotalSupply * (1.0/100.0) / 365.0 * (20.0/100.0) * (play! / ecosystemPlayTotalSupply)

                let totalMOX = highScore + score24Change + donationLevelProgression

                if (totalMOX > 0.0) {
                    // Mint corresponding MOX tokens to user's account
                    self.mintMOXToAddress(address: address, amount: totalMOX)
                }
                // Update the minted timestamp (TokenEpoch)
                self.wallets[address]!.setDailyActivityUpdatedTimestamp(timestamp: timeTo0000)
            }
        }

        pub fun mintMOXToAddress(address: Address, amount: UFix64) {
            let tokenAdmin = MoxyClub.account.borrow<&MoxyToken.Administrator>(from: MoxyToken.moxyTokenAdminStorage)
                ?? panic("Signer is not the token admin")
            let tokenReceiver = getAccount(address)
                .getCapability(MoxyToken.moxyTokenReceiverPath)
                .borrow<&{FungibleToken.Receiver}>()
                ?? panic("Unable to borrow receiver reference")

            let minter <- tokenAdmin.createNewMinter(allowedAmount: amount)
            let mintedVault <- minter.mintTokens(amount: amount)
            tokenReceiver.deposit(from: <-mintedVault)
            destroy minter
        }

        pub fun getTotalSupply24DueForProcessTo(address: Address, toTimestamp: UFix64): {UFix64: UFix64} {
            
            let fromTimestamp = self.wallets[address]!.dailyActivityUpdatedTimestamp
            let from0000 = MoxyClub.getTimestampTo0000(timestamp: fromTimestamp)
            let to0000 = MoxyClub.getTimestampTo0000(timestamp: toTimestamp)
            let day = 86400.0
            let acct = getAccount(address)
            let vaultRef = acct.getCapability(ScoreToken.scoreTokenDailyBalancePath)
                            .borrow<&ScoreToken.Vault{ScoreToken.DailyBalancesInterface}>()
                            ?? panic("Could not borrow Balance reference to the Vault")

            // Get all pending since last update
            let resu: {UFix64: UFix64} = {}
            var curr0000 = from0000

            if (curr0000 <= 0.0) {
                var first = vaultRef.getFirstTimestampAdded()
                if (first == nil) {
                    return resu
                }
                curr0000 = first!
            }
            if (fromTimestamp == curr0000) {
                // Skip to next if start is equal to last registered
                curr0000 = curr0000 + day
            }

            while (curr0000 <= to0000) {
                var val = vaultRef.getDailyBalances()[curr0000]
                if (val == nil) {
                    val = 0.0
                }
                resu[curr0000] = val
                curr0000 = curr0000 + day
            }
            return resu 
        }

        pub fun requestMVToMOXConversion(acct: AuthAccount, timestamp: UFix64, amount: UFix64) {
            
            // Verify if the account has enough MV amount
            let account = getAccount(acct.address)
            let vaultRef = account.getCapability(MoxyVaultToken.moxyVaultTokenBalancePath)
                .borrow<&MoxyVaultToken.Vault{FungibleToken.Balance}>()
                ?? panic("Could not borrow Balance reference to the Vault")
            if (vaultRef.balance < amount) {
                panic("Not sufficient MV funds to convert.")
            }
            
            let epoch = self.getAddress(address: acct.address)
            if (epoch.conversionVaultMVToMOX == nil) {
                epoch.createConversionVaultMVToMOXCapabilityFor(acct: acct)
                self.wallets[acct.address] = epoch
            }
            let conversionVault = epoch.conversionVaultMVToMOX!.borrow()!
            conversionVault.requestMVToMOXFor(timestamp: timestamp, amount: amount) 
        }

        pub fun payMOXDueMVConversionToAll(timestamp: UFix64) {
            for address in self.wallets.keys {
                self.payMOXDueMVConversion(address: address, timestamp: timestamp)
            }
        }

        pub fun payMOXDueMVConversion(address: Address, timestamp: UFix64) {
            let epoch = self.getAddress(address: address)

            if (epoch.conversionVaultMVToMOX == nil) {
                panic("Address has no MV to MOX requests")
            }

            let conversionVault = epoch.conversionVaultMVToMOX!.borrow()!
            let payouts = conversionVault.getPayMOXDueMVConversion(timestamp: timestamp)

            for time in payouts.keys {
                let amount = payouts[time]!
                self.mintMOXToAddress(address: address, amount: amount)
                conversionVault.updateAmountReleased(timestamp: time, toTimestamp: timestamp, amount: amount)
            }
            self.wallets[address] = epoch
        }

        pub fun transferMOX(from: AuthAccount, to: Address, amount: UFix64) {
            // Function to transfer MOX from one account to a recepient account
            // The process consists on obtainig the vault with the amount received
            // doing a withdraw from the origin account
            // Then is calculated the fee charged, and the amount deposited to
            // the receiver will be the original amount subtracting that fee.
            // Then the fee is stored 95% on Treasury account and 5% is converted
            // to PLAY in order to strength Proof of Play to all ecosystem.
            // Finally if the recipient is the Treasury Account, additionally the 10%
            // of the received funds will be converted to PLAY to strength 
            // Proof of Play.
            // All convertions from MOX to PLAY are done in a rate 2:1 

            // Get a reference to the signer's stored vault
            let vaultRef = from.borrow<&MoxyToken.Vault>(from: MoxyToken.moxyTokenVaultStorage)
                ?? panic("Could not borrow reference to the owner's Vault!")

            // Withdraw tokens from the signer's stored vault
            let sentVault: @FungibleToken.Vault <- vaultRef.withdraw(amount: amount)

            // Get the recipient's public account object
            let recipient = getAccount(to)
            let feeRecipient = getAccount(self.treasuryAddress!)

            // Get a reference to the recipient's Receiver
            let receiverRef = recipient.getCapability(MoxyToken.moxyTokenReceiverPath)
                .borrow<&{FungibleToken.Receiver}>()
                ?? panic("Could not borrow receiver reference to the recipient's Vault")

            // Get a reference to the fee recipient's Receiver
            let feeReceiverRef = feeRecipient.getCapability(MoxyToken.moxyTokenReceiverPath)
                .borrow<&{FungibleToken.Receiver}>()
                ?? panic("Could not borrow receiver reference to the recipient's Vault")

            // Calculate cutted amounts
            let feeAmount = self.feeAmount
            var receiverAmount = amount - feeAmount
            var convertToPLAY: UFix64 = 0.0

            emit FeeCharged(amount: feeAmount)

            // Receiver if treasury 10% goes to PLAY
            if (to == self.treasuryAddress) {
                convertToPLAY = receiverAmount * 0.1
                receiverAmount = receiverAmount - convertToPLAY

                emit TreasuryRepurchase(amount: convertToPLAY)
            } 

            let receiverVault: @FungibleToken.Vault <- sentVault.withdraw(amount: receiverAmount) 
            let feeReceiverVault: @FungibleToken.Vault <- sentVault.withdraw(amount: feeAmount + convertToPLAY)

            // Deposit the withdrawn tokens in the recipient's receiver
            receiverRef.deposit(from: <- receiverVault)

            // Fee Amount 95% to treasury and 5% to PLAY (2x1 ratio)
            let moxToPlayAmount = convertToPLAY + feeAmount * self.percentFeeToPLAY
            let moxFeeAmount = feeReceiverVault.balance - moxToPlayAmount

            let feeReceiverMOXVault: @FungibleToken.Vault <- feeReceiverVault.withdraw(amount: moxFeeAmount)
            let moxToPLAYVault: @FungibleToken.Vault <- feeReceiverVault.withdraw(amount: moxToPlayAmount)

            feeReceiverRef.deposit(from: <- feeReceiverMOXVault)

            // Burn MOX
            // Mint play 2:1 for treasuryAddress
            self.convertMOXtoPLAY(vault: <-moxToPLAYVault, address: self.treasuryAddress!)

            // Residual MOX handling. If there are differences due floating point precision
            feeReceiverRef.deposit(from: <- sentVault)
            feeReceiverRef.deposit(from: <- feeReceiverVault)
            
        }

        access(contract) fun convertMOXtoPLAY(vault: @FungibleToken.Vault, address: Address) {
            let playAmount = vault.balance / 2.0

            // Mint PLAY token
            let tokenAdmin: &PlayToken.Administrator = MoxyClub.account.borrow<&PlayToken.Administrator>(from: PlayToken.playTokenAdminStorage)
                ?? panic("Signer is not the token admin")

            let tokenReceiver: &{FungibleToken.Receiver} = getAccount(address)
                .getCapability(PlayToken.playTokenReceiverPath)
                .borrow<&{FungibleToken.Receiver}>()
                ?? panic("Unable to borrow receiver reference")

            let minter <- tokenAdmin.createNewMinter(allowedAmount: playAmount)
            let mintedVault <- minter.mintTokens(amount: playAmount)
            tokenReceiver.deposit(from: <-mintedVault)
            destroy minter

            // Burn MOX
            // Create a reference to the admin admin resource in storage
            let admin = MoxyClub.account.borrow<&MoxyToken.Administrator>(from: MoxyToken.moxyTokenAdminStorage)
                ?? panic("Could not borrow a reference to the admin resource")

            let burner <- admin.createNewBurner()
            burner.burnTokens(from: <-vault)
            destroy burner

        }

        init() {
            self.wallets = {}
            // Fee amount in MOX
            self.feeAmount = 0.0002
            // BURN on transaction fees: 95% to Moxy and its affiliates/partners, 
            // and 5% BURN to PLAY token to further strengthen Proof of Play
            self.percentFeeToPLAY = 0.05
            
            self.treasuryAddress = nil
        }
    }

    pub resource ConversionVault: ConversionVaultInterface {
        access(contract) var requests: {UFix64:MVToMOXRequest}

        pub fun getRequests(): {UFix64: MVToMOXRequest} {
            return self.requests
        }

        pub fun requestMVToMOXFor(timestamp: UFix64, amount: UFix64) {
            self.requests[timestamp] = MVToMOXRequest(amount: amount, timestamp: timestamp)
        }

        pub fun updateAmountReleased(timestamp: UFix64, toTimestamp: UFix64, amount: UFix64) {
            self.requests[timestamp]!.updateAmountReleased(toTimestamp: toTimestamp, amount: amount)
        }

        pub fun getPayMOXDueMVConversion(timestamp: UFix64): {UFix64: UFix64} {
            let time0000 = MoxyVaultToken.getTimestampTo0000(timestamp: timestamp)
            let resu: {UFix64:UFix64} = {}
            for time in self.requests.keys {
                let request = self.requests[time]!
                if (time0000 > request.lastReleaseTime0000) {
            
                    let days = UFix64(UInt64((time0000 - request.lastReleaseTime0000) / 86400.0))
                    let amount = (request.amount / 365.0) * days
                    if (amount > 0.0) {
                        resu[time] = amount
                    }
                }
            }
            return resu
        }

        init() {
            self.requests = {}
        }
    }

    pub struct MVToMOXRequest {
        pub var amount: UFix64
        pub var amountReleased: UFix64
        pub var lastReleaseTime0000: UFix64

        pub fun updateAmountReleased(toTimestamp: UFix64, amount: UFix64) {
            self.lastReleaseTime0000 = toTimestamp
            self.amountReleased = self.amountReleased + amount
        }

        init(amount: UFix64, timestamp: UFix64) {
            self.amount = amount
            self.amountReleased = 0.0
            self.lastReleaseTime0000 = MoxyVaultToken.getTimestampTo0000(timestamp: timestamp)
        }
    }

    pub resource interface ConversionVaultInterface {
        pub fun getRequests(): {UFix64: MVToMOXRequest}
    }

    access(self) fun createEmptyConversionVault(): @ConversionVault {
        let conversionVault <- create ConversionVault()
        return <-conversionVault
    }

    access(self) fun getWalletsCapability(): &Wallets {
        return self.account
            .getCapability(self.moxyWalletsPrivate)
            .borrow<&MoxyClub.Wallets>()!
    }
    
    pub fun getTimestampTo0000(timestamp: UFix64): UFix64 {
        let days = timestamp / 86400.0
        return UFix64(UInt64(days)) * 86400.0
    }

    pub fun isMoxyAccount(address: Address): Bool {
        return self.getWalletsCapability().isMoxyAccount(address: address)
    }



    pub let moxyWalletsStorage: StoragePath
    pub let moxyWalletsPrivate: PrivatePath
    pub let convertMVToMOXStorage: StoragePath
    pub let convertMVToMOXPrivate: PrivatePath
    pub let convertMVToMOXInfoPublic: PublicPath

    // Initialize contract
    init(){
        
        // Moxy Wallets initialization
        let moxyWallets <- create Wallets()

        self.moxyWalletsStorage = /storage/moxyWallets
        self.moxyWalletsPrivate = /private/moxyWallets

        self.convertMVToMOXStorage = /storage/convertMVToMOXStorage
        self.convertMVToMOXPrivate = /private/convertMVToMOXPrivate
        self.convertMVToMOXInfoPublic = /public/convertMVToMOXInfoPublic

        self.account.save(<-moxyWallets, to: self.moxyWalletsStorage)
        self.account.link<&Wallets>(self.moxyWalletsPrivate, target: self.moxyWalletsStorage)


        // Create ConversionVault for MV to MOX conversions 
        let conversionVault <- create ConversionVault()
        self.account.save(<-conversionVault, to: self.convertMVToMOXStorage)

        self.account.link<&MoxyClub.ConversionVault>(
            self.convertMVToMOXPrivate,
            target: self.convertMVToMOXStorage
        )
        self.account.link<&MoxyClub.ConversionVault{ConversionVaultInterface}>(
            self.convertMVToMOXInfoPublic,
            target: self.convertMVToMOXStorage
        )

    }
}
 