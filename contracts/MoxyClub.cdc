import PlayToken from "./PlayToken.cdc"
import ScoreToken from "./ScoreToken.cdc"
import MoxyToken from "./MoxyToken.cdc"
import MoxyVaultToken from "./MoxyVaultToken.cdc"
import LockedToken from "./LockedToken.cdc"
import MoxyReleaseRounds from "./MoxyReleaseRounds.cdc"
import FungibleToken from "./flow/FungibleToken.cdc"
import MoxyProcessQueue from "./MoxyProcessQueue.cdc"

pub contract MoxyClub {

    pub event MoxyAccountAdded(address: Address)
    pub event RoundAdded(name: String)

    // Fee Charged event on MOX transfer
    pub event FeeCharged(address: Address, amount: UFix64)

    // Treasury repurchase event triggered when Treasury wallet has received MOX tokens
    // This will enforce PLAY token with the 10% of MOX received on a 2:1 MOX to PLAY
    // conversion 
    pub event TreasuryRepurchase(amount: UFix64)

    pub event MOXRewaredDueMVHoldingsTo(address: Address, timestamp: UFix64, amount: UFix64)
    pub event MOXRewaredDueDailyActivityTo(address: Address, timestamp: UFix64, amount: UFix64)
    pub event MOXToMVDailyConversionTo(address: Address, timestamp: UFix64, amount: UFix64)

    pub event MembershipFeeDeducted(address: Address, feeDeducted: UFix64, remaining: UFix64)

    //Events to process Start of Round Releases
    pub event StartingRoundReleaseInitializeProcess(timestamp: UFix64, roundsToProcess: Int, accountsToProcess: Int)
    pub event FinishedRoundReleaseInitializeProcess(timestamp: UFix64, roundsProcessed: Int, accountsProcessed: Int)

    //Events to process Round Release allocations
    pub event StartingDailyRoundReleaseAllocationProcess(timestamp: UFix64, accountsToProcess: Int)
    pub event FinishedDailyRoundReleaseAllocationProcess(timestamp: UFix64, accountsProcessed: Int)

    //Events when paying MV Holdings
    pub event PaidAlreadyMadeWhenPayingMVHoldingsRewards(address: Address, timestamp: UFix64)
    pub event AddressNotFoundWhenPayingMVHoldingsRewards(address: Address, timestamp: UFix64)
    pub event RequestedDateSmallerToLastUpdateWhenPayingMVHoldingsRewards(address: Address, timestamp: UFix64, lastMVHoldingsUpdatedTimestamp: UFix64)
    pub event StartingRewardsPaymentsDueMVHoldings(timestamp: UFix64, accountsToProcess: Int)
    pub event FinishedRewardsPaymentsDueMVHoldings(timestamp: UFix64, accountsProcessed: Int)

    // Event for Proof of Play (PoP) rewards
    pub event AddressNotFoundWhenPayingPoPRewards(address: Address, timestamp: UFix64)
    pub event StartingRewardsPaymentsDuePoP(timestamp: UFix64, accountsToProcess: Int)
    pub event FinishedRewardsPaymentsDuePoP(timestamp: UFix64, accountsProcessed: Int)
    pub event RequestedDateSmallerToLastUpdateWhenPayingPoPRewards(address: Address, timestamp: UFix64, lastDailyActivityUpdatedTimestamp: UFix64)

    //Events when Vaults not found on users storage
    pub event AccountDoesNotHaveScoreVault(address: Address, message: String)
    pub event AccountDoesNotHaveMoxyVaultVault(address: Address, message: String)

    // Ecosystem parameters modifications events
    pub event MOXYToFLOWValueChanged(oldAmount: UFix64, newAmount: UFix64, timestamp: UFix64)
    pub event TreasuryAddressChanged(newAddress: Address)
    pub event AssociationAddressChanged(newAddress: Address)
    
    // Play and Earn private reference assigned
    pub event PlayAndEarnReferenceAssigned(address: Address)
    pub event PlayAndEarnEventAccountAdded(address: Address)

    // Events for process of paying MOXY due MV conversion
    pub event StartingPayingMOXYDueMVConversion(timestamp: UFix64, accountsToProcess: Int)
    pub event FinishedPayingMOXYDueMVConversion(timestamp: UFix64, accountsProcessed: Int)
    pub event MVToMOXYConversionPerformed(address: Address, amount: UFix64, timestamp: UFix64)
    pub event MVToMOXYConversionAlreadyPerformed(address: Address, timestamp: UFix64, lastUpdated: UFix64)
    pub event MVToMOXYConversionAlreadyFinished(address: Address, timestamp: UFix64, lastUpdated: UFix64)

    // Event when Proof of Play weights are modified
    pub event PopWeightsChanged(newScoreWeight: UFix64, newDailyScoreWeight: UFix64, newPlayDonationWeight: UFix64)

    // Project cost events
    pub event ProjectCostChanged(newAmount: UFix64)
    pub event ProjectCostPaid(address: Address, amount: UFix64)

   pub resource MoxyAccount {
        pub var dailyActivityUpdatedTimestamp: UFix64
        
        // Variables for MV Holdings
        access(contract) var earnedFromMVHoldings: {UFix64:UFix64}
        access(contract) var totalEarneadFromMVHoldings: UFix64
        access(contract) var lastMVHoldingsUpdatedTimestamp: UFix64

        access(contract) var mvToMOXYConverter: {UFix64:Capability<&MVToMOXYConverter>?}
        pub var membershipFee: UFix64
        pub var membershipFeePaid: UFix64

        pub var playAndEarnRef: Capability<&FungibleToken.Vault>?

        pub fun setDailyActivityUpdatedTimestamp(timestamp: UFix64) {
            self.dailyActivityUpdatedTimestamp = timestamp
        }

        pub fun setLastMVHoldingsUpdatedTimestamp(timestamp: UFix64) {
            self.lastMVHoldingsUpdatedTimestamp = timestamp
        }

        pub fun setMOXEarnedFromMVHoldingsFor(timestamp: UFix64, amount: UFix64) {
            self.earnedFromMVHoldings[timestamp] = amount
            self.totalEarneadFromMVHoldings = self.totalEarneadFromMVHoldings + amount
            self.lastMVHoldingsUpdatedTimestamp = timestamp
        }

        pub fun setMVToMOXYConverterFor(timestamp: UFix64, capabilityRef: Capability<&MVToMOXYConverter>){
            self.mvToMOXYConverter[timestamp] = capabilityRef           
        }

        pub fun getMVToMOXYConverter(timestamp: UFix64): Capability<&MVToMOXYConverter>?? {
            return self.mvToMOXYConverter[timestamp]
        }

        pub fun payMOXDueMVConversionUpto(timestamp: UFix64) {
            var conversionsFinished = true
            for time in self.mvToMOXYConverter.keys {
                let converter = self.mvToMOXYConverter[time]!!.borrow()!
                converter.payUpto(timestamp: timestamp)
            }
        }

        pub fun haveFinishedConversions(): Bool {
            var conversionsFinished = true
            for time in self.mvToMOXYConverter.keys {
                let converter = self.mvToMOXYConverter[time]!!.borrow()!
                conversionsFinished = conversionsFinished && converter.hasFinished()
            }
            return conversionsFinished
        }

        pub fun getMVToMOXtRequests(): {UFix64: MVToMOXRequestInfo} {
            let array: {UFix64:MVToMOXRequestInfo} = {} 
            for time in self.mvToMOXYConverter.keys {
                let converter = self.mvToMOXYConverter[time]!!.borrow()!
                let request = MVToMOXRequestInfo(amount: converter.conversionAmount, 
                    amountReleased: converter.convertedAmount, creationTimestamp: converter.creationTimestamp, 
                    lastReleaseTime0000: converter.lastReleaseTime0000, finishTimestamp: converter.getFinishTimestamp())
                array[converter.creationTimestamp] = request 
            }
            return array
        }

        pub fun getMembershipFeeRemaining(): UFix64 {
            return self.membershipFee - self.membershipFeePaid
        }

        pub fun hasMembershipFeePending(): Bool {
            return (self.membershipFee - self.membershipFeePaid) > 0.0
        }

        pub fun updateMembershipFeePaid(amount: UFix64) {
            self.membershipFeePaid = self.membershipFeePaid + amount
        }

        pub fun getEarnedFromMVHoldings(): {UFix64: UFix64} {
            return self.earnedFromMVHoldings
        }

        pub fun getTotalEarnedFromMVHoldings(): UFix64 {
            return self.totalEarneadFromMVHoldings
        }

        pub fun setPlayAndEarnRef(vaultRef: Capability<&FungibleToken.Vault>) {
            self.playAndEarnRef = vaultRef
        }

        init(){
            self.dailyActivityUpdatedTimestamp = 0.0
            self.earnedFromMVHoldings = {}
            self.totalEarneadFromMVHoldings = 0.0
            self.lastMVHoldingsUpdatedTimestamp = 0.0
            self.mvToMOXYConverter = {}
            self.membershipFee = 5.0 //Fee is in MOXY Token
            self.membershipFeePaid = 0.0
            self.playAndEarnRef = nil
        }
    }

    pub resource PlayAndEarnAccount {
        pub var creationDate: UFix64

        init() {
            self.creationDate = getCurrentBlock().timestamp
        }
    }     

    pub struct MVToMOXRequestInfo {
        pub var amount: UFix64
        pub var amountReleased: UFix64
        pub var creationTimestamp: UFix64
        pub var lastReleaseTime0000: UFix64
        pub var finishTimestamp: UFix64
        pub var remainingDays: Int
        pub var remainingAmount: UFix64
        
        init(amount: UFix64, amountReleased: UFix64, creationTimestamp: UFix64, lastReleaseTime0000: UFix64, finishTimestamp: UFix64) {
            self.amount = amount
            self.amountReleased = amountReleased
            self.creationTimestamp = creationTimestamp
            self.lastReleaseTime0000 = lastReleaseTime0000
            self.finishTimestamp = finishTimestamp
            self.remainingDays = Int((self.finishTimestamp - self.lastReleaseTime0000) / 86400.0)
            self.remainingAmount = self.amount - self.amountReleased
        }
     }

     pub resource MVToMOXYConverter {
        pub var creationTimestamp: UFix64
        pub var conversionAmount: UFix64
        pub var convertedAmount: UFix64
        pub var mvConverter: @MoxyVaultToken.MVConverter
        pub var lockedMOXYVault: @FungibleToken.Vault
        pub var lastReleaseTime0000: UFix64
        pub var withdrawalDays: Int

        pub fun payUpto(timestamp: UFix64) {
            let time0000 = MoxyVaultToken.getTimestampTo0000(timestamp: timestamp)
            if (time0000 <= self.lastReleaseTime0000) {
                log("WARNING: Cannot pay MOXY in MV to MOXY convertion because it has already paid up to the requested date")
                emit MVToMOXYConversionAlreadyPerformed(address: self.owner!.address, timestamp: time0000, lastUpdated: self.lastReleaseTime0000)
                return
            }

            if (self.hasFinished()) {
                log("WARNING: Conversion process already finished")
                emit MVToMOXYConversionAlreadyFinished(address: self.owner!.address, timestamp: time0000, lastUpdated: self.lastReleaseTime0000)
                return

            }

            let days = UFix64(UInt64((time0000 - self.lastReleaseTime0000) / 86400.0))
            var amount: UFix64 = 0.0 

            // If time is grather than the finish time, the amount to withdraw is
            // all allowed
            if (time0000 >= self.getFinishTimestamp()) {
                // Amount to withdraw is all allowed
                amount = self.mvConverter.allowedAmount
            } else {
                // Amount to withdraw is based on daily pay
                amount = (self.conversionAmount / UFix64(self.withdrawalDays)) * days
            }
            
            // Burn los MV
            let admin = MoxyClub.account.borrow<&MoxyVaultToken.Administrator>(from: MoxyVaultToken.moxyVaultTokenAdminStorage)
                ?? panic("Could not borrow a reference to the admin resource")
            let burner <- admin.createNewBurner()
            let vault2 <- self.mvConverter.getDailyVault(amount: amount)
            burner.burnTokens(from: <- vault2)
            destroy burner

            // Convert Locked MOXY to MOXY
            // Get the recipient's public account object
            let recipient = self.lockedMOXYVault.owner!

            // Get a reference to the recipient's Receiver
            let receiverRef = recipient.getCapability(MoxyToken.moxyTokenReceiverPath)
                .borrow<&{FungibleToken.Receiver}>()
                ?? panic("Could not borrow receiver reference to the recipient's Vault")

            let vault3 <- self.lockedMOXYVault.withdraw(amount: amount)
            // Deposit the withdrawn tokens in the recipient's receiver
            receiverRef.deposit(from: <- vault3)

            //update converted amount and timestamp
            self.convertedAmount = self.convertedAmount + amount
            self.lastReleaseTime0000 = time0000

            emit MVToMOXYConversionPerformed(address: recipient.address, amount: amount, timestamp: time0000)
        }

        pub fun hasFinished(): Bool {
            return self.convertedAmount >= self.conversionAmount
        }

        pub fun getFinishTimestamp(): UFix64 {
            return MoxyVaultToken.getTimestampTo0000(timestamp: self.creationTimestamp) + (UFix64(self.withdrawalDays) * 86400.0)
        }

        init(mvConverter: @MoxyVaultToken.MVConverter, lockedMOXYVault: @FungibleToken.Vault , timestamp: UFix64, withdrawalDays: Int) {
            self.creationTimestamp = timestamp
            self.conversionAmount = mvConverter.allowedAmount
            self.convertedAmount = 0.0
            self.mvConverter <- mvConverter
            self.lockedMOXYVault <- lockedMOXYVault
            self.lastReleaseTime0000 = MoxyVaultToken.getTimestampTo0000(timestamp: timestamp)
            self.withdrawalDays = withdrawalDays
        }

        destroy() {
            destroy self.mvConverter
            destroy self.lockedMOXYVault
        }
    }


    pub resource MoxyEcosystem: MoxyEcosystemInfoInterface, MVToMOXYRequestsInfoInterface {
        access(contract) let accounts: @{Address:MoxyAccount}
        access(contract) let playAndEarnEventAccounts: @{Address:PlayAndEarnAccount}
        pub var isReleaseStarted: Bool

        /// Fee amount to charge on MOX transactions
        pub var feeAmountInFLOW: UFix64
        pub var moxyToFLOWValue: UFix64
        pub var percentFeeToPLAY: UFix64

        // Moxy Controlled Addresses
        pub var treasuryAddress: Address?
        pub var associationAddress: Address?

        // Total earned from MV holdings
        pub var totalEarnedFromMVHoldings: UFix64

        pub var mvToMOXWithdrawalDays: Int

        // Process Queue handling
        pub var roundReleaseQueue: @MoxyProcessQueue.Queue
        pub var mvHoldingsQueue: @MoxyProcessQueue.Queue
        pub var proofOfPlayQueue: @MoxyProcessQueue.Queue
        pub var mvToMOXConversionQueue: @MoxyProcessQueue.Queue

        // Proof of Play weight for score, daily score and play donations
        pub var popScoreWeight: UFix64
        pub var popDailyScoreWeight: UFix64
        pub var popPlayDonationWeight: UFix64

        // Project cost to be paid for users when submitting a project
        // It's value is in MOXY
        pub var projectCost: UFix64


        pub fun getMOXYFeeAmount(): UFix64 {
            return self.feeAmountInFLOW * 2.0 * self.moxyToFLOWValue
        }

        pub fun getMOXYToFLOWValue(): UFix64 {
            return self.moxyToFLOWValue
        }

        pub fun setMOXYToFLOWValue(amount: UFix64) {
            let oldValue = self.moxyToFLOWValue
            self.moxyToFLOWValue = amount
            emit MOXYToFLOWValueChanged(oldAmount: oldValue, newAmount: amount, timestamp: getCurrentBlock().timestamp)
        }

        pub fun setTreasuryAddress(address: Address) {
            self.treasuryAddress = address
            emit TreasuryAddressChanged(newAddress: address)
        }

        pub fun setAssociationAddress(address: Address) {
            self.associationAddress = address
            emit AssociationAddressChanged(newAddress: address)
        }

        pub fun setPlayAndEarnRefTo(address: Address, vaultRef: Capability<&FungibleToken.Vault>) {
            self.accounts[address]?.setPlayAndEarnRef(vaultRef: vaultRef)
            emit PlayAndEarnReferenceAssigned(address: address)
        }

        pub fun setPopWeights(scoreWeight: UFix64, dailyScoreWeight: UFix64, playDonationWeight: UFix64) {
            pre {
                scoreWeight + dailyScoreWeight + playDonationWeight == 100.0 : "The sum of three weights should be 100.0"
            }

            self.popScoreWeight = scoreWeight
            self.popDailyScoreWeight = dailyScoreWeight
            self.popPlayDonationWeight = playDonationWeight
            emit PopWeightsChanged(newScoreWeight: scoreWeight, newDailyScoreWeight: scoreWeight, newPlayDonationWeight: scoreWeight)
        }

        pub fun setProjectCost(amount: UFix64) {
            self.projectCost = amount
            emit ProjectCostChanged(newAmount: amount)
        }

        pub fun getProjectCost(): UFix64 {
            return self.projectCost
        }

        pub fun payProjectCost(fromVault: @FungibleToken.Vault, address: Address) {
            pre {
                fromVault.balance == self.projectCost : "Amount to paid does not match with project cost amount."
            }
            let amount = fromVault.balance
            self.transferMOXY(fromVault: <-fromVault, to: self.treasuryAddress!) 
            emit ProjectCostPaid(address: address, amount: amount)

        }

        pub fun getTreasuryAddress(): Address? {
            return self.treasuryAddress
        }

        pub fun getAssociationAddress(): Address? {
            return self.associationAddress
        }
        
        pub fun hasMembershipFeePendingFor(address: Address): Bool {
            if (self.accounts[address] == nil) {
                panic("Address not found in MoxyClub")
            }
            return self.accounts[address]?.hasMembershipFeePending()!
        }

        //Returns the Membership Fee remaining for an address
        pub fun getMembershipFeeRemainingFor(address: Address): UFix64 {
            if (self.accounts[address] == nil) {
                panic("Address not found in MoxyClub")
            }
            return self.accounts[address]?.getMembershipFeeRemaining()!
        }

        pub fun getTotalEarnedFromMVHoldings(): UFix64 {
            return self.totalEarnedFromMVHoldings
        }

        pub fun getEarnedFromMVHoldingsFor(address: Address): {UFix64: UFix64} {
            if (self.accounts[address] == nil) {
                panic("Address not found in MoxyClub")
            }
            return self.accounts[address]?.getEarnedFromMVHoldings()!
        }

        pub fun getTotalEarnedFromMVHoldingsFor(address: Address): UFix64 {
            if (self.accounts[address] == nil) {
                panic("Address not found in MoxyClub")
            }
            return self.accounts[address]?.getTotalEarnedFromMVHoldings()!
        }

        //Returns the Membership Fee total for an address
        pub fun getMembershipFeeFor(address: Address): UFix64 {
            if (self.accounts[address] == nil) {
                panic("Address not found in MoxyClub")
            }
            return self.accounts[address]?.membershipFee!
        }

        pub fun isMoxyAccount(address: Address): Bool {
            return (self.accounts[address] != nil)
        }


        pub fun addMoxyAccount(address: Address){
            // Only add the account if it doesn't exists
            if (self.accounts[address] == nil) {
                self.accounts[address] <-! create MoxyAccount()
                self.mvHoldingsQueue.addAccount(address: address)
                self.proofOfPlayQueue.addAccount(address: address)
                
                emit MoxyClub.MoxyAccountAdded(address: address)
            }
        }

        pub fun addPlayAndEarnEventAccount(address: Address){
            // Add a Play and Earn Account to the Moxy Ecosystem
            if (self.playAndEarnEventAccounts[address] != nil) {
                panic("Can't add Play and Earn Event account, acount already added.")
            }
            self.playAndEarnEventAccounts[address] <-! create PlayAndEarnAccount()
            emit MoxyClub.PlayAndEarnEventAccountAdded(address: address)
        }

        pub fun addAccountToRound(roundId: String, address: Address, amount: UFix64) {
            let roundManager = self.getRoundsCapability().borrow()!
            roundManager.setAddress(roundId: roundId, address: address, amount: amount)
            self.roundReleaseQueue.addAccount(address: address)
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

        // Collects the initial fixed Memebership Fee (5 MOXY total)
        access(contract) fun collectMembershipFee(address: Address, vault: @FungibleToken.Vault): @FungibleToken.Vault {
            
            let remainingFee = self.accounts[address]?.getMembershipFeeRemaining()!

            var feeToDeduct = remainingFee
            if (remainingFee > vault.balance) {
                feeToDeduct = vault.balance
            }

            let association = getAccount(self.associationAddress!)
            let associationVaultRef = association.getCapability(MoxyToken.moxyTokenReceiverPath)
                    .borrow<&{FungibleToken.Receiver}>()
                    ?? panic("Could not borrow Balance reference to the Vault")

            let vaultFee <- vault.withdraw(amount: feeToDeduct)
            associationVaultRef.deposit(from: <-vaultFee)
            
            self.accounts[address]?.updateMembershipFeePaid(amount: feeToDeduct)

            emit MembershipFeeDeducted(address: address, feeDeducted: feeToDeduct, remaining: remainingFee - feeToDeduct)

            return <-vault

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

            let lockedVaultRef = acct.getCapability(MoxyVaultToken.moxyVaultTokenLockedBalancePath)
                .borrow<&LockedToken.LockedVault{LockedToken.Balance}>()
                ?? panic("Could not borrow Balance reference to the Vault")

            
            let balancesChanges = vaultRef.getDailyBalancesChanges()
            let lockedBalancesChanges = lockedVaultRef.getLockedBalances()

            var rewardsMox = self.getMOXRewardsFromDictionaryFor(time0000: time0000, dictionary: balancesChanges)
            var rewardsMoxFromLockedMV = self.getMOXRewardsFromDictionaryFor(time0000: time0000, dictionary: lockedBalancesChanges)

            var totalRewards = rewardsMox + rewardsMoxFromLockedMV

            let totalMV = balanceRef.balance
            let totalLockedMV = lockedVaultRef.getBalance()
            let total = totalMV + totalLockedMV

            // Maximum Holdings Modifier
            if (total > 10000000.0) {
                totalRewards = totalRewards + (total * 0.05 / 365.0)
            }

            return totalRewards
        }

        access(contract) fun getMOXRewardsFromDictionaryFor(time0000: UFix64, dictionary: {UFix64:UFix64}): UFix64 {
            // Iterate over all MV allocated over past days
            var rewardsMox = 0.0
            for time in dictionary.keys {

                if (time0000 < time) {
                    // Continue on future MV holdings rewards
                    // This could be caused due to not running daily process on time
                    continue
                }
                // Daily Linear Appreciation over Time
                let days = (time0000 - time) / 86400.0
                let amount = dictionary[time]!

                var percentage = 0.0
                if (days > 0.0  && days <= 90.0 ) {
                    percentage = 2.0
                }
                if (days > 90.0  && days <= 180.0 ) {
                    percentage = 4.0
                }
                if (days > 180.0  && days <= 365.0 ) {
                    percentage = 6.0
                }
                if (days > 365.0 ) {
                    percentage = 10.0
                }

                percentage = UFix64(percentage / 100.0 / 365.0)
                rewardsMox = rewardsMox + (amount * percentage)
            }

            return rewardsMox
        }

        pub fun rewardDueMVHoldings(quantity: Int) {
            //It will run for a quantity of addresses depending on the current queue progress
            if (self.mvHoldingsQueue.isAtBeginning()) {
                emit StartingRewardsPaymentsDueMVHoldings(timestamp: getCurrentBlock().timestamp, accountsToProcess: self.mvHoldingsQueue.getAccountsQuantity())
            }
            let addresses = self.mvHoldingsQueue.getNextAddresses(cant: quantity)
            self.rewardDueMVHoldingsToAddresses(addresses: addresses)
            self.mvHoldingsQueue.completeNextAddresses(quantity: addresses.length)
            if (self.mvHoldingsQueue.hasFinished()) {
                emit FinishedRewardsPaymentsDueMVHoldings(timestamp: getCurrentBlock().timestamp, accountsProcessed: self.mvHoldingsQueue.getAccountsQuantity())
            }
        }

        pub fun rewardDueMVHoldingsToAddresses(addresses: [Address]) {
            for address in addresses {
                self.rewardDueMVHoldingsTo(address: address)
            }
        }

        pub fun rewardDueMVHoldingsTo(address: Address) {
            let timestamp = getCurrentBlock().timestamp
            let time0000 = MoxyClub.getTimestampTo0000(timestamp: timestamp)
            if (self.accounts[address] == nil) {
                log("Address not found in Moxy Club ecosystem")
                emit AddressNotFoundWhenPayingMVHoldingsRewards(address: address, timestamp: time0000)
                return
            }

            // Check for already paid account
            var lastMVHoldingsUpdatedTimestamp = self.accounts[address]?.lastMVHoldingsUpdatedTimestamp!
            if (lastMVHoldingsUpdatedTimestamp == 0.0) {
                //Set fist time when converting MOX to MV when is not already set
                let acct = getAccount(address)
                let mvInfoRef = acct.getCapability(MoxyVaultToken.moxyVaultTokenDailyBalancePath)
                    .borrow<&MoxyVaultToken.Vault{MoxyVaultToken.DailyBalancesInterface}>()
                if (mvInfoRef == nil) {
                    log("Account does not have MoxyVault Vault")
                    emit AccountDoesNotHaveMoxyVaultVault(address: address, message: "Could not borrow reference to MV Vault when processing MV Holdings rewards.")
                    return
                }
                let firstTime = mvInfoRef!.getFirstTimestampAdded()
                if (firstTime == nil) {
                    log("Address does not have MV holdings")
                    return
                }
                self.accounts[address]?.setLastMVHoldingsUpdatedTimestamp(timestamp: firstTime!)
                lastMVHoldingsUpdatedTimestamp = firstTime!
            }
            
            if (lastMVHoldingsUpdatedTimestamp >= time0000) {
                log("Requested date is smaller than the last MV Holdings updated date")
                emit RequestedDateSmallerToLastUpdateWhenPayingMVHoldingsRewards(address: address, timestamp: time0000, lastMVHoldingsUpdatedTimestamp: lastMVHoldingsUpdatedTimestamp)
                return
            }

            // Get all timestamps from last updated MV Rewards to time0000
            let last0000 = MoxyClub.getTimestampTo0000(timestamp: lastMVHoldingsUpdatedTimestamp)
            let days = (time0000 - last0000) / 86400.0

            var i = 0.0
            var times: [UFix64] = []
            while i < days {
                i = i + 1.0
                times.append(last0000 + (i * 86400.0))
            }

            for time in times {
                if (self.accounts[address]?.earnedFromMVHoldings![time] != nil) {
                    log("Rewards already paid to address in requested day")
                    emit PaidAlreadyMadeWhenPayingMVHoldingsRewards(address: address, timestamp: time0000)
                    continue
                }

                // Moxy Vault rewards are paid in MOX, calculated by each user's MV holding  
                let rewardMOX = self.calculateRewardsDueMVHoldingsTo(address: address, timestamp: time) 
                if (rewardMOX > 0.0) {
                    
                    // Mint corresponding MOX tokens to user's account
                    self.mintMOXToAddress(address: address, amount: rewardMOX)

                    // Update the minted timestamp (MoxyAccount)
                    self.accounts[address]?.setMOXEarnedFromMVHoldingsFor(timestamp: time, amount: rewardMOX)

                    self.totalEarnedFromMVHoldings = self.totalEarnedFromMVHoldings + rewardMOX
                    emit MOXRewaredDueMVHoldingsTo(address: address, timestamp: time, amount: rewardMOX)
                }
            }
        }

        pub fun rewardDueDailyActivity(quantity: Int) {
            //It will run for a quantity of addresses depending on the current queue progress
            if (self.proofOfPlayQueue.isAtBeginning()) {
                emit StartingRewardsPaymentsDuePoP(timestamp: getCurrentBlock().timestamp, accountsToProcess: self.proofOfPlayQueue.getAccountsQuantity())
            }
            let addresses = self.proofOfPlayQueue.getNextAddresses(cant: quantity)
            self.rewardDueDailyActivityToAddresses(addresses: addresses)
            self.proofOfPlayQueue.completeNextAddresses(quantity: addresses.length)
            if (self.proofOfPlayQueue.hasFinished()) {
                emit FinishedRewardsPaymentsDuePoP(timestamp: getCurrentBlock().timestamp, accountsProcessed: self.proofOfPlayQueue.getAccountsQuantity())
            }
        }

        pub fun rewardDueDailyActivityToAddresses(addresses: [Address]) {
            for address in addresses {
                self.rewardDueDailyActivityFor(address: address)
            }
        }

        pub fun rewardDueDailyActivityFor(address: Address) {
            let timestamp = getCurrentBlock().timestamp

            // PLAY + SCORE + SCORE24
            let timeTo0000 = MoxyClub.getTimestampTo0000(timestamp: timestamp)

            if (self.accounts[address] == nil) {
                log("Address not found in Moxy Club ecosystem")
                emit AddressNotFoundWhenPayingPoPRewards(address: address, timestamp: timeTo0000)
                return
            }

            // Check for already paid account
            var dailyActivityUpdatedTimestamp = self.accounts[address]?.dailyActivityUpdatedTimestamp!
            if (dailyActivityUpdatedTimestamp == 0.0) {
                //Set fist time when received first  SCORE for PoP
                let acct = getAccount(address)
                let mvInfoRef = acct.getCapability(ScoreToken.scoreTokenDailyBalancePath)
                    .borrow<&ScoreToken.Vault{ScoreToken.DailyBalancesInterface}>()
                if (mvInfoRef == nil) {
                    log("Account does not have Score Vault")
                    emit AccountDoesNotHaveScoreVault(address: address, message: "Could not borrow reference to SCORE Vault when processing PoP rewards.")
                    return
                }
                let firstTime = mvInfoRef!.getFirstTimestampAdded()
                if (firstTime == nil) {
                    log("Address does not have SCORE records")
                    return
                }
                self.accounts[address]?.setDailyActivityUpdatedTimestamp(timestamp: firstTime!)
                dailyActivityUpdatedTimestamp = firstTime!
            }
            
            if (dailyActivityUpdatedTimestamp >= timeTo0000) {
                log("Requested date is smaller than the last Daily Activity updated date")
                emit RequestedDateSmallerToLastUpdateWhenPayingPoPRewards(address: address, timestamp: timeTo0000, lastDailyActivityUpdatedTimestamp: dailyActivityUpdatedTimestamp)
                return
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

                let highScore = ecosystemPlayTotalSupply * (1.0/100.0) / 365.0 * (self.popScoreWeight / 100.0) * (score! / ecosystemScoreTotalSupply)
                var score24Change = 0.0
                if (ecosystemScore24Change != 0.0) {
                    // If SCORE changed
                    score24Change = ecosystemPlayTotalSupply * (1.0/100.0) / 365.0 * (self.popPlayDonationWeight / 100.0) * (change / ecosystemScore24Change)
                }
                let donationLevelProgression = ecosystemPlayTotalSupply * (1.0/100.0) / 365.0 * (self.popPlayDonationWeight / 100.0) * (play! / ecosystemPlayTotalSupply)

                let totalMOX = highScore + score24Change + donationLevelProgression

                if (totalMOX > 0.0) {
                    // Mint corresponding MOX tokens to user's account
                    self.mintMOXToAddress(address: address, amount: totalMOX)
                    emit MOXRewaredDueDailyActivityTo(address: address, timestamp: timeTo0000, amount: totalMOX)
                }
                // Update the minted timestamp (MoxyAccount)
                self.accounts[address]?.setDailyActivityUpdatedTimestamp(timestamp: timeTo0000)
            }
        }

        access(contract) fun mintMOXYTokens(amount: UFix64): @FungibleToken.Vault {
            let tokenAdmin = MoxyClub.account.borrow<&MoxyToken.Administrator>(from: MoxyToken.moxyTokenAdminStorage)
                ?? panic("Signer is not the token admin")
            
            let minter <- tokenAdmin.createNewMinter(allowedAmount: amount)
            let vault <- minter.mintTokens(amount: amount)

            destroy minter

            return <-vault
        }

        pub fun mintMOXToAddress(address: Address, amount: UFix64) {
            let tokenReceiver = getAccount(address)
                .getCapability(MoxyToken.moxyTokenReceiverPath)
                .borrow<&{FungibleToken.Receiver}>()
                ?? panic("Unable to borrow receiver reference")
            
            let mintedVault <- self.mintMOXYTokens(amount: amount)

            // Mint tokens to user, first deduct Membership Fee amount
            if (self.accounts[address]?.hasMembershipFeePending()!) {
                let vaultDeducted <- self.collectMembershipFee(address: address, vault: <-mintedVault)
                tokenReceiver.deposit(from: <- vaultDeducted)            
            } else {
                tokenReceiver.deposit(from: <- mintedVault)
            }
        }

        pub fun getTotalSupply24DueForProcessTo(address: Address, toTimestamp: UFix64): {UFix64: UFix64} {
            
            let fromTimestamp = self.accounts[address]?.dailyActivityUpdatedTimestamp!
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

        pub fun createMVToMOXYConverter(mvConverter: @MoxyVaultToken.MVConverter, lockedMOXYVault: @FungibleToken.Vault): @MVToMOXYConverter {
            return <- create MVToMOXYConverter(mvConverter: <-mvConverter, lockedMOXYVault: <- lockedMOXYVault, timestamp: getCurrentBlock().timestamp, withdrawalDays: self.mvToMOXWithdrawalDays)
        }

        pub fun getMVConverterStorageIdentifier(timestamp: UFix64): String {
            return "mvToMOXYConverter".concat(UInt64(timestamp).toString())
        }

        pub fun requestMVToMOXConversion(address:Address, mvToMOXYConverterCapability: Capability<&MVToMOXYConverter>, amount: UFix64) {

            let timestamp = getCurrentBlock().timestamp

            // Saves the capability to access to the converted created by the user.
            self.accounts[address]?.setMVToMOXYConverterFor(timestamp: timestamp, capabilityRef: mvToMOXYConverterCapability)
            self.mvToMOXConversionQueue.addAccount(address: address)

            emit MOXToMVDailyConversionTo(address: address, timestamp: timestamp, amount: amount)
        }

        pub fun payMOXDueMVConversion(quantity: Int) {
            //It will run for a quantity of addresses depending on the current queue progress
            if (self.mvToMOXConversionQueue.isAtBeginning()) {
                emit StartingPayingMOXYDueMVConversion(timestamp: getCurrentBlock().timestamp, accountsToProcess: self.mvToMOXConversionQueue.getAccountsQuantity())
            }
            let addresses = self.mvToMOXConversionQueue.getNextAddresses(cant: quantity)
            self.payMOXDueMVConversionToAddresses(addresses: addresses)
            self.mvToMOXConversionQueue.completeNextAddresses(quantity: addresses.length)
            //self.checkAndRemoveFinishedConversionTo(addresses: addresses)
            if (self.mvToMOXConversionQueue.hasFinished()) {
                emit FinishedPayingMOXYDueMVConversion(timestamp: getCurrentBlock().timestamp, accountsProcessed: self.mvHoldingsQueue.getAccountsQuantity())
            }
        }

        pub fun payMOXDueMVConversionToAddresses(addresses: [Address]) {
            for address in addresses {
                self.payMOXDueMVConversionFor(address: address)
            }
        }

        // Pay due MOXY to MV conversion for an specific account up to
        // the current timestamp date
        pub fun payMOXDueMVConversionFor(address: Address) {
            let timestamp = getCurrentBlock().timestamp
            self.accounts[address]?.payMOXDueMVConversionUpto(timestamp: timestamp)
        }

        pub fun checkAndRemoveFinishedConversionTo(addresses: [Address]) {
            for address in addresses {
                if (self.accounts[address]?.haveFinishedConversions()!) {
                    self.mvToMOXConversionQueue.removeAccount(address: address)
                }
            }
        }


        pub fun depositToPlayAndEarnVault(address: Address, vault: @FungibleToken.Vault) {
            self.accounts[address]?.playAndEarnRef!.borrow()!.deposit(from: <-vault)
        }

        pub fun withdrawFromPlayAndEarnVault(address: Address, amount: UFix64) {
            let peVault = self.accounts[address]?.playAndEarnRef!.borrow()!
            let vault <- peVault.withdraw(amount: amount)

            let recipient = getAccount(address)
            // Get a reference to the recipient's Receiver
            let receiverRef = recipient.getCapability(MoxyToken.moxyTokenReceiverPath)
                .borrow<&{FungibleToken.Receiver}>()
                ?? panic("Could not borrow receiver reference to the recipient's Vault")

            receiverRef.deposit(from: <-vault)
        }

        pub fun payFromPlayAndEarnVault(payee: Address, amount: UFix64, toAddress: Address) {
            let peVault = self.accounts[payee]?.playAndEarnRef!.borrow()!
            let vault <- peVault.withdraw(amount: amount)

            self.transferMOXY(fromVault: <-vault, to: toAddress)
        }

        pub fun transferMOXY(fromVault: @FungibleToken.Vault, to: Address) {
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

            
            if (self.accounts[to] == nil && self.playAndEarnEventAccounts[to] == nil) {
                panic ("Account not found in Moxy Club.")
            }

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
            let feeAmount = self.getMOXYFeeAmount()
            var receiverAmount = fromVault.balance - feeAmount
            var convertToPLAY: UFix64 = 0.0

            emit FeeCharged(address: to, amount: feeAmount)

            // Receiver if treasury 10% goes to PLAY
            if (to == self.treasuryAddress) {
                convertToPLAY = receiverAmount * 0.1
                receiverAmount = receiverAmount - convertToPLAY

                emit TreasuryRepurchase(amount: convertToPLAY)
            } 

            let receiverVault: @FungibleToken.Vault <- fromVault.withdraw(amount: receiverAmount) 
            let feeReceiverVault: @FungibleToken.Vault <- fromVault.withdraw(amount: feeAmount + convertToPLAY)

            // Deposit the withdrawn tokens in the recipient's receiver
            // If the recipient has pending Membership Fee to paid, the fee is collected
            if (self.accountHasMembershipFeePending(address: to)) {
                let vaultDeducted <- self.collectMembershipFee(address: to, vault: <-receiverVault)
                receiverRef.deposit(from: <- vaultDeducted)
            } else {
                receiverRef.deposit(from: <- receiverVault)
            }

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
            feeReceiverRef.deposit(from: <- fromVault)
            feeReceiverRef.deposit(from: <- feeReceiverVault)
            
        }

        pub fun accountHasMembershipFeePending(address: Address): Bool {
            if (self.accounts[address] == nil && self.playAndEarnEventAccounts[address] == nil) {
                panic ("Account not found in Moxy Club.")
            }
            if (self.playAndEarnEventAccounts[address] != nil) {
                return false
            }
            return self.accounts[address]?.hasMembershipFeePending()!
        }

        access(contract) fun convertMOXtoPLAY(vault: @FungibleToken.Vault, address: Address) {
            let playAmount = vault.balance / 2.0

            if (playAmount > 0.0) {
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
            }

            // Burn MOX
            // Create a reference to the admin admin resource in storage
            let admin = MoxyClub.account.borrow<&MoxyToken.Administrator>(from: MoxyToken.moxyTokenAdminStorage)
                ?? panic("Could not borrow a reference to the admin resource")

            let burner <- admin.createNewBurner()
            burner.burnTokens(from: <-vault)
            destroy burner

        }

        // Returns the MV to MOX requests by address
        pub fun getMVToMOXtRequests(address: Address): {UFix64: MVToMOXRequestInfo} {
            if (self.accounts[address] == nil) {
                panic("Address not found in MoxyClub")
            }
            return self.accounts[address]?.getMVToMOXtRequests()!
        }

        pub fun isTGESet(): Bool {
            return self.getTGEDate() > 0.0
        }
        
        pub fun releaseIsNotStarted(): Bool {
            return !self.isReleaseStarted
        }

        pub fun isTGEDateReached(): Bool {
            return self.getTGEDate() <= getCurrentBlock().timestamp
        }

        pub fun areRoundsReadyToStartRelease(): Bool {
            let rounds = self.getRoundsCapability().borrow()!
            return  rounds.isReadyToStartRelease()
        }

        pub fun haveAllRoundsStarted(): Bool {
            let rounds = self.getRoundsCapability().borrow()!
            return  rounds.haveAllRoundsStarted()
        }
        
        // Start release to a quantity of addresses. This is the starting point
        // The methods called from here will be not available to call independtly
        pub fun startReleaseTo(quantity: Int) {
             pre {
                self.releaseIsNotStarted() : "Cannot start allocation process: Release is already started."
                self.isTGESet() : "Cannot start allocation process: TGE Date is not set."
                self.isTGEDateReached() : "Cannot start allocation process: TGE date is not reached."
                self.areRoundsReadyToStartRelease() :  "Cannot start allocation process: Rounds are not ready to start, please verify allocations."
            }

            let rounds = self.getRoundsCapability().borrow()!
            
            if (rounds.isQueueAtBegining()) {
                // Start round release is starting process. Emit event.
                let accountsToProcess = rounds.getAccountsToProcess()
                emit StartingRoundReleaseInitializeProcess(timestamp: (getCurrentBlock().timestamp),roundsToProcess: rounds.getRoundsLength(), accountsToProcess: accountsToProcess)
            }

            for roundId in rounds.getRoundsNames() {
                if (!rounds.hasQueueFinished(roundId: roundId)) {
                    // Process unfinished round and exit
                    let addresses = rounds.getQueueNextAddresses(roundId: roundId, quantity: quantity)
                    rounds.completeNextAddresses(roundId: roundId, quantity: quantity)
                    self.startReleaseRoundToAddress(roundId: roundId, addresses: addresses)
                    return
                }
            }

            // Check if all rounds were processed
            if (rounds.initialAllocationFinished()) {
                self.isReleaseStarted = true
                let accountsToProcess = rounds.getAccountsToProcess()
                emit FinishedRoundReleaseInitializeProcess(timestamp: getCurrentBlock().timestamp, roundsProcessed: rounds.getRoundsLength(), accountsProcessed: accountsToProcess)
            }
        }

        // Process start release to addresses from round id provided
        access(self) fun startReleaseRoundToAddress(roundId: String, addresses: [Address]) {
            for address in addresses {
                self.startReleaseRoundAddress(roundId: roundId, address: address)
            }
        }

        access(self) fun startReleaseRoundAddress(roundId: String, address: Address) {
            let rounds = self.getRoundsCapability().borrow()!
            let amount = rounds.getAmountFor(roundId: roundId, address: address)!
            
            if (amount > 0.0) {
                // Mint $MOXY for the round
                let initialReleaseVault <- self.mintMOXYTokens(amount: amount)
                rounds.startReleaseRound(roundId: roundId, address: address, initialVault: <-initialReleaseVault)
            }
        }

        pub fun assignMoxyControlledWalletsToRounds( 
                    publicIDOAddress: Address, teamAddress: Address, 
                    foundationAddress: Address, advisorsAddress: Address,
                    treasuryAddress: Address, ecosystemAddress: Address) {
            
            let roundsManager = self.getRoundsCapability().borrow()!
            roundsManager.fullAllocateTo(roundId: "public_ido", address: publicIDOAddress)
            roundsManager.fullAllocateTo(roundId: "team", address: teamAddress)
            roundsManager.fullAllocateTo(roundId: "moxy_foundation", address: foundationAddress)
            roundsManager.fullAllocateTo(roundId: "advisors", address: advisorsAddress)
            roundsManager.fullAllocateTo(roundId: "treasury", address: treasuryAddress)
            roundsManager.fullAllocateTo(roundId: "ecosystem", address: ecosystemAddress)

            self.roundReleaseQueue.addAccount(address: publicIDOAddress)
            self.roundReleaseQueue.addAccount(address: teamAddress)
            self.roundReleaseQueue.addAccount(address: foundationAddress)
            self.roundReleaseQueue.addAccount(address: advisorsAddress)
            self.roundReleaseQueue.addAccount(address: treasuryAddress)
            self.roundReleaseQueue.addAccount(address: ecosystemAddress)
            
        }

        pub fun areMoxyControlledWalletsAllocated(): Bool {
            let roundsManager = self.getRoundsCapability().borrow()!

            return (
                    roundsManager.isReadyToStartReleaseTo(roundId: "public_ido") &&
                    roundsManager.isReadyToStartReleaseTo(roundId: "team") &&
                    roundsManager.isReadyToStartReleaseTo(roundId: "moxy_foundation") &&
                    roundsManager.isReadyToStartReleaseTo(roundId: "advisors") &&
                    roundsManager.isReadyToStartReleaseTo(roundId: "treasury") &&
                    roundsManager.isReadyToStartReleaseTo(roundId: "ecosystem")
                )
        }

        pub fun purchaseFromPublicPresale(roundsRef: Capability<&MoxyReleaseRounds.Rounds>, address: Address, amount: UFix64) {
            let roundManager = roundsRef.borrow()!

            roundManager.setAddress(roundId: "public_presale", address: address, amount: amount)
            self.roundReleaseQueue.addAccount(address: address)

            if (self.isReleaseStarted) {
                // Mint $MOXY for the round
                let initialReleaseVault <- self.mintMOXYTokens(amount: amount)
                roundManager.allocateAfterTGE(roundId: "public_presale", vault: <-initialReleaseVault, address: address)
            }
        }

        pub fun getProcessRoundsRemainings(): Int {
            return self.roundReleaseQueue.getRemainings()
        }

        pub fun getProcessMVHoldingsRemainings(): Int {
            return self.mvHoldingsQueue.getRemainings()
        }

        pub fun getProcessProofOfPlayRemainings(): Int {
            return self.proofOfPlayQueue.getRemainings()
        }

        pub fun getMVToMOXConversionRemainings(): Int {
            return self.mvToMOXConversionQueue.getRemainings()
        }

        pub fun allocateDailyReleaseTo(roundsRef: Capability<&MoxyReleaseRounds.Rounds>, quantity: Int) {
            //It will run for a quantity of addresses depending on the current queue progress
            if (self.roundReleaseQueue.isAtBeginning()) {
                emit StartingDailyRoundReleaseAllocationProcess(timestamp: getCurrentBlock().timestamp, accountsToProcess: self.roundReleaseQueue.getAccountsQuantity())
            }
            let addresses = self.roundReleaseQueue.getNextAddresses(cant: quantity)
            self.allocateDailyReleaseToAddresses(roundsRef: roundsRef, addresses: addresses)
            self.roundReleaseQueue.completeNextAddresses(quantity: addresses.length)
            if (self.roundReleaseQueue.hasFinished()) {
                emit FinishedDailyRoundReleaseAllocationProcess(timestamp: getCurrentBlock().timestamp, accountsProcessed: self.roundReleaseQueue.getAccountsQuantity())
            }
        }

        pub fun allocateDailyReleaseToAddresses(roundsRef: Capability<&MoxyReleaseRounds.Rounds>, addresses: [Address]) {
            for address in addresses {
                self.allocateDailyReleaseNowToAddress(roundsRef: roundsRef, address: address)
            }
        }

        pub fun allocateDailyReleaseNowToAddress(roundsRef: Capability<&MoxyReleaseRounds.Rounds>, address: Address) {
//            let roundManager = roundsRef.borrow()!
            let roundManager= self.getRoundsCapability().borrow()!

            if (!roundManager.hasRoundRelease(address: address)) {
                log("Address is not participating on round release process")
                return
            }

            let membershipFeeReceiver = getAccount(address)
                            .getCapability(MoxyToken.moxyTokenReceiverPath)
                            .borrow<&{FungibleToken.Receiver}>()
                            ?? panic("Unable to borrow receiver reference")
            let feeRemaining = self.accounts[address]?.getMembershipFeeRemaining()!
            let feeVault <- roundManager.allocateDailyReleaseNowToAddress(address: address, feeRemaining: feeRemaining)
            
            let vaultDeducted <- self.collectMembershipFee(address: address, vault: <-feeVault)
            membershipFeeReceiver.deposit(from: <- vaultDeducted)            
        }

        access(self) fun getRoundsCapability(): Capability<&MoxyReleaseRounds.Rounds> {
            return MoxyClub.account.getCapability<&MoxyReleaseRounds.Rounds>(MoxyReleaseRounds.moxyRoundsPrivate)
        }

        pub fun getTGEDate(): UFix64 {
            let rounds = self.getRoundsCapability().borrow()!
            return rounds.tgeDate
        }

        pub fun releaseStarted(): Bool {
            return self.isReleaseStarted
        }

        init() {
            self.accounts <- {}

            self.isReleaseStarted = false
  
            // Fee amount in MOX
            self.feeAmountInFLOW = 0.000001
            self.moxyToFLOWValue = 0.02076124 //Estimated FLOW to USD: 2.89, MOXY to USD: 0.06
        

            // BURN on transaction fees: 95% to Moxy and its affiliates/partners, 
            // and 5% BURN to PLAY token to further strengthen Proof of Play
            self.percentFeeToPLAY = 0.05
            
            self.treasuryAddress = nil
            self.associationAddress = nil

            self.totalEarnedFromMVHoldings = 0.0

            self.mvToMOXWithdrawalDays = 90

            self.roundReleaseQueue <- MoxyProcessQueue.createNewQueue()
            self.mvHoldingsQueue <- MoxyProcessQueue.createNewQueue()
            self.proofOfPlayQueue <- MoxyProcessQueue.createNewQueue()
            self.mvToMOXConversionQueue <- MoxyProcessQueue.createNewQueue()

            // Proof of Play Weigth
            self.popScoreWeight = 30.0
            self.popDailyScoreWeight = 70.0
            self.popPlayDonationWeight = 0.0

            // Play and Earn event accounts dictionary
            self.playAndEarnEventAccounts <- {}

            // Project cost value is in MOXY
            self.projectCost = 10.0

        }

        destroy() {
            destroy self.accounts
            destroy self.playAndEarnEventAccounts
            destroy self.roundReleaseQueue
            destroy self.mvHoldingsQueue
            destroy self.proofOfPlayQueue
            destroy self.mvToMOXConversionQueue
        }

    }

    access(self) fun getMoxyEcosystemCapability(): &MoxyEcosystem {
        return self.account
            .getCapability(self.moxyEcosystemPrivate)
            .borrow<&MoxyClub.MoxyEcosystem>()!
    }

    pub fun getMoxyEcosystemPublicCapability(): &MoxyEcosystem{MoxyEcosystemInfoInterface} {
        return self.account
                .getCapability(MoxyClub.moxyEcosystemInfoPublic)
                .borrow<&MoxyClub.MoxyEcosystem{MoxyEcosystemInfoInterface}>()!
    }
    
    
    pub fun getTimestampTo0000(timestamp: UFix64): UFix64 {
        let days = timestamp / 86400.0
        return UFix64(UInt64(days)) * 86400.0
    }

/*     pub fun isMoxyAccount(address: Address): Bool {
        return self.getMoxyEcosystemCapability().isMoxyAccount(address: address)
    }
*/
    pub resource interface MoxyEcosystemInfoInterface {
        pub fun isMoxyAccount(address: Address): Bool
        pub fun getTreasuryAddress(): Address?
        pub fun getAssociationAddress(): Address?
        pub fun getProjectCost(): UFix64

        pub fun hasMembershipFeePendingFor(address: Address): Bool
        pub fun getMembershipFeeRemainingFor(address: Address): UFix64
        pub fun getMembershipFeeFor(address: Address): UFix64

        pub fun getTotalEarnedFromMVHoldings(): UFix64
        pub fun getEarnedFromMVHoldingsFor(address: Address): {UFix64: UFix64}
        pub fun getTotalEarnedFromMVHoldingsFor(address: Address): UFix64

        pub fun getMOXYFeeAmount(): UFix64
        pub fun getMOXYToFLOWValue(): UFix64

        pub fun areMoxyControlledWalletsAllocated(): Bool
        
        pub fun getProcessRoundsRemainings(): Int
        pub fun getProcessMVHoldingsRemainings(): Int 
        pub fun getProcessProofOfPlayRemainings(): Int 
        pub fun getMVToMOXConversionRemainings(): Int 

        pub fun releaseStarted(): Bool
    }

    pub resource interface MVToMOXYRequestsInfoInterface {
        pub fun getMVToMOXtRequests(address: Address): {UFix64: MVToMOXRequestInfo}
    }

    pub let moxyEcosystemStorage: StoragePath
    pub let moxyEcosystemPrivate: PrivatePath
    pub let moxyEcosystemInfoPublic: PublicPath

    pub let mvToMOXYRequestsInfoPublic: PublicPath

    // Initialize contract
    init(){
        
        // Moxy Ecosystem initialization
        let moxyEcosystem <- create MoxyEcosystem()

        self.moxyEcosystemStorage = /storage/moxyEcosystem
        self.moxyEcosystemPrivate = /private/moxyEcosystem
        self.moxyEcosystemInfoPublic = /public/moxyEcosystemInfo

        self.mvToMOXYRequestsInfoPublic = /public/mvToMOXYRequestsInfoPublic

        self.account.save(<-moxyEcosystem, to: self.moxyEcosystemStorage)
        self.account.link<&MoxyEcosystem>(self.moxyEcosystemPrivate, target: self.moxyEcosystemStorage)

        self.account.link<&MoxyEcosystem{MVToMOXYRequestsInfoInterface}>(
            self.mvToMOXYRequestsInfoPublic,
            target: self.moxyEcosystemStorage
        )

        self.account.link<&MoxyEcosystem{MoxyEcosystemInfoInterface}>(
            self.moxyEcosystemInfoPublic ,
            target: self.moxyEcosystemStorage
        )

    }
}
 