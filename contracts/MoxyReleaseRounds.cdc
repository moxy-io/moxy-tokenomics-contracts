import FungibleToken from "./flow/FungibleToken.cdc"
import MoxyToken from "./MoxyToken.cdc"

pub contract MoxyReleaseRounds {

    pub event AccountAdded(address: Address)
    pub event RoundAdded(name: String)

    pub struct ParticipantRoundInfo {
        pub let address: Address
        pub let roundId: String
        pub let amount: UFix64
        pub let amountReleased: UFix64

        init(address: Address, roundId: String, amount: UFix64, amountReleased: UFix64 ) {
            self.address = address
            self.roundId = roundId
            self.amount = amount
            self.amountReleased = amountReleased
        }
    }

    pub struct RoundRelease {

        pub var amount: UFix64
        pub var amountReleased: UFix64

        pub fun getAllocationRemaining(): UFix64 {
            return self.amount - self.amountReleased
        }
        
        pub fun payLinearRelease(amount: UFix64) {
            self.amountReleased = self.amountReleased + amount
        }

        pub fun getAmount(): UFix64 {
            return self.amount
        }

        pub fun increaseAmount(amount: UFix64) {
            self.amount = self.amount + amount
        }
        
        init( amount: UFix64) {

            self.amount = amount
            self.amountReleased = 0.0
        }
    }

    pub resource RoundReleases: RoundReleasesInfo {
        access(contract) let releases: {String: RoundRelease}

        pub fun setAddress(roundId: String, roundRelease: RoundRelease) {
            var round = self.releases[roundId]
            if (round == nil) {
                // Add to round
                self.releases[roundId] = roundRelease
            } else {
                // Update round adding the rounde release info
                round!.increaseAmount(amount: roundRelease.amount)
                self.releases[roundId] = round
            }
        }
        
        pub fun payLinearRelease(roundId: String, roundRelease: RoundRelease) {
            var round = self.releases[roundId]!
            self.releases[roundId] = roundRelease
        }
        
        pub fun getRoundRelease(roundId: String): RoundRelease? {
            return self.releases[roundId]
        }

        init() {
            self.releases = {}
        }
    }

    pub struct Round {
        pub let id: String
        pub let type: String
        pub let name: String
        pub let initialRelease: UFix64
        pub let lockTime: Int 
        pub let months: Int
        pub var tgeDate: UFix64
        pub var lastReleaseDate: UFix64
        access(self) var accounts: {Address: Capability<&RoundReleases>}
        pub var totalAllocated: UFix64
        pub var totalReleased: UFix64

        pub fun getRoundRelease(_ address: Address): RoundRelease? {
            if (self.accounts[address] == nil) {
                return nil
            }
            return self.accounts[address]!.borrow()!.releases[self.id]
        }

        pub fun getAccounts(): {Address: ParticipantRoundInfo} {
             let accounts: {Address: ParticipantRoundInfo} = {}
            for address in self.accounts.keys {
                let release = self.getRoundRelease(address)!
                accounts[address] = ParticipantRoundInfo(address: address, roundId: self.id, amount: release.amount, amountReleased: release.amountReleased)
            }
            return accounts;
        }

        pub fun getAllocationRemaining(): UFix64 {
            return self.initialRelease - self.totalAllocated
        }

        access(contract) fun setAddress(address: Address, amount: UFix64, releasesRef: Capability<&RoundReleases>){

            // Adding reference to address
            if (self.accounts[address] == nil) {
                self.accounts[address] = releasesRef
            }

            // Check if address is not already added to the round
            let roundReleases = self.accounts[address]!.borrow()!
            let roundRelease = RoundRelease(amount: amount)

            roundReleases.setAddress(roundId: self.id, roundRelease: roundRelease)
            
            self.totalAllocated = self.totalAllocated + amount
 
            emit MoxyReleaseRounds.AccountAdded(address: address)
        }

        pub fun payLinearRelease(_ address: Address, amount: UFix64) {
            let roundRealease = self.getRoundRelease(address)!
            roundRealease.payLinearRelease(amount: amount)
        }

        pub fun allocateDailyReleaseToNow(serviceAccount: AuthAccount) {
            if (!self.canStartReleasing()) {
                log ("Cannot start allocation process, set TGE date to start.")
                return 
            }
            
            // Get the daily round
            let dailyAllocation = self.dailyAllocationAmount()

            // Get the amount from the last release to a given date
            let now = getCurrentBlock().timestamp
            let amountToAllocate = self.getDailyAllocationTo(timestamp: now)

            // Withdraw del total para hacer el release
            // Get a reference to the signer's stored vault
            let vaultRef = serviceAccount.borrow<&MoxyToken.Vault>(from: MoxyToken.moxyTokenVaultStorage)
                ?? panic("Could not borrow reference to the owner's Vault!")
            let allocationVault: @FungibleToken.Vault <- vaultRef.withdraw(amount: amountToAllocate)

            // Allocate the amounts to the participants
            for key in self.accounts.keys {
                let releaseRound = self.getRoundRelease(key)!
                let ratio = self.getReleaseRatioFor(address: key)
                let amount = ratio * amountToAllocate
                let roundReleasesRef = self.accounts[key]!
                let roundReleases = roundReleasesRef.borrow()!

                releaseRound.payLinearRelease(amount: amount)
                roundReleases.payLinearRelease(roundId: self.id, roundRelease: releaseRound)
                self.totalReleased = self.totalReleased + amount

                // Deposit into participant account
                let recipient = getAccount(key)
                // Check if the round should give locked tokens
                if (self.areTokensLockedForReleaseTo(timestamp: now)) {
                    // Send locked tokens to recipient
                    let receiverRef = recipient.getCapability(MoxyToken.moxyTokenLockedReceiverPath)
                            .borrow<&{MoxyToken.Receiver}>()
                            ?? panic("Could not borrow receiver reference to the recipient's Vault")

                    // Deposit the withdrawn tokens in the recipient's receiver
                    // The tokens will be locked upto the days defined on round with
                    // starting point at TGE Date.
                    let time = self.tgeDate + self.getLockedTokenTime()
                    receiverRef.deposit(from: <-allocationVault.withdraw(amount: amount), time: time)
                } else { 
                    // send unlocked tokens to recipient
                    let receiverRef = recipient.getCapability(MoxyToken.moxyTokenReceiverPath)
                            .borrow<&{FungibleToken.Receiver}>()
                            ?? panic("Could not borrow receiver reference to the recipient's Vault")

                    // Deposit the withdrawn tokens in the recipient's receiver
                    receiverRef.deposit(from: <-allocationVault.withdraw(amount: amount))
                }
            }
            // If residual tokens because of floating precition will return to service account.
            self.totalReleased = self.totalReleased + allocationVault.balance
            vaultRef.deposit(from: <-allocationVault)

            // Update last release date
            let days = self.getDaysFromLastReleaseTo(timestamp: now)
            self.lastReleaseDate = self.lastReleaseDate + (UFix64(days) * 86400.0)
        }

        pub fun getReleaseRatioFor(address: Address): UFix64 {
            if (self.totalAllocated <= 0.0) {
                panic("Round does not have allocations yet. Release ratio could not be calculated")
            }
            
            let amount = self.getRoundRelease(address)!.amount
            return amount / self.totalAllocated
        }

        pub fun getDailyAllocationTo(timestamp: UFix64): UFix64 {
            let days = self.getDaysFromLastReleaseTo(timestamp: timestamp)
            if (days < 1) {
                return 0.0
            }

            return UFix64(days) * self.dailyAllocationAmount()
        }

        pub fun getDailyAllocationsFrom(from: UFix64, to: UFix64): [UFix64] {
            let from0000 = self.getTimestampTo0000(timestamp: from)
            let to0000 = self.getTimestampTo0000(timestamp: to)
            let days = self.getDaysFromTo(from: from0000, to: to0000)
            let amount = self.dailyAllocationAmount()
            return [from0000, to0000, UFix64(days), amount, self.tgeDate, self.getEndDate(),  self.lastReleaseDate]
        }

        pub fun getDailyAllocationsFromToAddress(address: Address, from: UFix64, to: UFix64): [UFix64]? {
            let allocationInfo = self.getDailyAllocationsFrom(from: from, to: to)
            let roundReleases = self.accounts[address]!.borrow()!
            let roundRelease = roundReleases.getRoundRelease(roundId: self.id)
            
            allocationInfo.append(roundRelease!.amount)
            allocationInfo.append(roundRelease!.amountReleased)
            return allocationInfo
        }

        pub fun getDaysFromLastReleaseTo(timestamp: UFix64) : UInt64 {
            return UInt64((timestamp - self.lastReleaseDate) / 86400.0)
        }

        pub fun getDaysFromTo(from: UFix64, to: UFix64): UInt64 {
            let from0000 = self.getTimestampTo0000(timestamp: from)
            let to0000 = self.getTimestampTo0000(timestamp: to)

            return UInt64((to0000 - from0000) / 86400.0)
        }

        pub fun setTGEDate(timestamp: UFix64) {
            // I only update TGE if there are no allocations made
            let timestampToStart = self.getTimestampTo0000(timestamp: timestamp)
            if (!self.isReleaseProcesStarted()) {
                self.tgeDate = timestampToStart
                self.lastReleaseDate = timestampToStart
            } else {
                log("TGE Date could not be modified, release process already started.")
            }
        }

        pub fun getEndDate(): UFix64 {
            if (!self.isTGESet()) {
                return 0.0
            }
            return self.tgeDate + (UFix64(self.months) * 30.0 * 86400.0)
        }

        pub fun canStartReleasing(): Bool {
            return self.isTGESet()
        }

        pub fun isTGESet(): Bool {
            return self.tgeDate > 0.0
        }

        pub fun isReleaseProcesStarted(): Bool {
            return self.totalReleased != 0.0
        }

        pub fun areTokensLockedForReleaseTo(timestamp: UFix64): Bool {
            // Returns true if tokens should be released as locked tokens
            let time0000 = self.getTimestampTo0000(timestamp: timestamp)
            let endLockTime = self.tgeDate + self.getLockedTokenTime()

            return time0000 <= endLockTime
        }

        pub fun getLockedTokenTime(): UFix64 {
            return UFix64(self.lockTime) * 86400.0
        }

        pub fun getTimestampTo0000(timestamp: UFix64): UFix64 {
            let days = timestamp / 86400.0
            return UFix64(UInt64(days)) * 86400.0
        }

        pub fun dailyAllocationAmount() :UFix64 {
            if (self.months == 0) {
                return self.initialRelease
            }
            let total = self.initialRelease / UFix64(self.months) / 30.0
            return total
        }

        pub fun removeAddress(address: Address){
            if (self.isReleaseProcesStarted()) {
                return
            }
            let roundRelease = self.getRoundRelease(address)!
            self.totalAllocated = self.totalAllocated - roundRelease.getAmount()
            self.accounts.remove(key: address)
        }

        init(id: String, type: String, name: String, initialRelease: UFix64, lockTime: Int, months: Int){
            self.id = id
            self.type = type
            self.name = name
            self.initialRelease = initialRelease
            self.lockTime = lockTime
            self.months = months
            self.accounts = {}
            self.totalAllocated = 0.0
            self.tgeDate = 0.0
            self.lastReleaseDate = 0.0
            self.totalReleased = 0.0
        }
    }

    pub resource Rounds: MoxyRoundsInfo {
        access(contract) let rounds: {String: Round}
        access(self) let releases: {Address:Capability<&RoundReleases>}

        pub fun getRound(_ id: String): Round? {
            return self.rounds[id]
        }

        pub fun addRound(_ id: String, type: String, name: String, initialRelease: UFix64, lockTime: Int, months: Int) {
            let round = Round(id: id, type: type, name: name, initialRelease: initialRelease, lockTime: lockTime, months: months)
            self.rounds[id] = round
            emit MoxyReleaseRounds.RoundAdded(name: name)
        }

        pub fun setAddress(roundId: String, acct: AuthAccount, amount: UFix64){
            
            // Make a new resource to store the roundID in the key and
            // a structure with the RoundRelease (with amount and amount released) in value
            let round = self.rounds[roundId]!
            if (round.isReleaseProcesStarted()) {
                return
            }
            
            if (round.getAllocationRemaining() < amount ) {
                panic("Amount exceeds initial Allocation. Max to allocate is ".concat(round.getAllocationRemaining().toString()))
            }

            if (self.releases[acct.address] == nil) {
                // Create the resource
                let releases <- create RoundReleases()
                // Store the resoure in the account storage
        		acct.save(<-releases, to: MoxyReleaseRounds.roundReleasesStorage)

                // Create capability
                let releasesRef2 = acct.link<&MoxyReleaseRounds.RoundReleases>(
                        MoxyReleaseRounds.roundReleasesPrivate, 
                        target: MoxyReleaseRounds.roundReleasesStorage)!

                // Create public access to resource information
                acct.link<&MoxyReleaseRounds.RoundReleases{RoundReleasesInfo}>(
                        MoxyReleaseRounds.roundReleasesInfoPublic, 
                        target: MoxyReleaseRounds.roundReleasesStorage)!

                self.releases[acct.address] = releasesRef2
                
            } 
            let releasesRef = self.releases[acct.address]!
            round.setAddress(address: acct.address, amount: amount, releasesRef: releasesRef)
            self.rounds[roundId] = round
        }

        pub fun payLinearRelease(roundId: String, address: Address, amount: UFix64){
            self.rounds[roundId]?.payLinearRelease(address, amount: amount)
        }

        pub fun allocateDailyReleaseToNow(roundId: String, serviceAccount: AuthAccount) {
            let round = self.rounds[roundId]!
            round.allocateDailyReleaseToNow(serviceAccount: serviceAccount)
            self.rounds[roundId] = round
        }

        pub fun removeAddress(roundId: String, address: Address){
            self.rounds[roundId]?.removeAddress(address: address)
        }

        pub fun setTGEDate(roundId: String, timestamp: UFix64) {
            self.rounds[roundId]?.setTGEDate(timestamp: timestamp)
        }

        pub fun getAllocationRemaining(_ id: String):UFix64? {
            return self.rounds[id]?.getAllocationRemaining()
        }
        pub fun getDailyAllocationsFrom(roundId: String, from: UFix64, to: UFix64): [UFix64]? {
            return self.rounds[roundId]?.getDailyAllocationsFrom(from: from, to: to)
        }

        pub fun getDailyAllocationsFromToAddress(roundId: String, address: Address, from: UFix64, to: UFix64): [UFix64]?? {
            return self.rounds[roundId]?.getDailyAllocationsFromToAddress(address: address, from: from, to: to)
        }

        pub fun getRoundRelease(_ id: String,  address: Address): RoundRelease?? {
            let round = self.rounds[id]
            let roundRelease = round?.getRoundRelease(address)
            
            return roundRelease
        }

        pub fun getAccounts(_ id: String): {Address: ParticipantRoundInfo}? {
            return self.rounds[id]?.getAccounts();
        }

        pub fun getRoundsForAddress(address: Address): {String: ParticipantRoundInfo} {
            let rounds: {String: ParticipantRoundInfo} = {}
            for round in self.rounds.values {
                let result = round.getRoundRelease(address)
                if (result != nil) {
                    // Add to the round
                    rounds[round.id] = ParticipantRoundInfo(address: address, roundId: round.id, amount: result!.amount, amountReleased: result!.amountReleased)
                }
            }
            return rounds
        }

        init() {
            self.rounds = {}
            self.releases = {}
        }
    }

    access(self) fun getRoundsCapability(): &Rounds {
        return self.account
            .getCapability(self.moxyRoundsPrivate)
            .borrow<&MoxyReleaseRounds.Rounds>()!
    }

    pub fun getRound(_ id: String): Round?{
        let roundsManager = self.getRoundsCapability()
        return roundsManager.getRound(id)
    }

    pub fun getRounds(): [String] {
        let roundsManager = self.getRoundsCapability()
        return roundsManager.rounds.keys
    }

    pub resource interface RoundReleasesInfo {

    }

    pub resource interface MoxyRoundsInfo {
        pub fun getRoundsForAddress(address: Address): {String: ParticipantRoundInfo} 
        pub fun getAllocationRemaining(_ id: String): UFix64? 
        pub fun getDailyAllocationsFrom(roundId: String, from: UFix64, to: UFix64): [UFix64]?
        pub fun getDailyAllocationsFromToAddress(roundId: String, address: Address, from: UFix64, to: UFix64): [UFix64]??
        pub fun getAccounts(_ id: String): {Address: ParticipantRoundInfo}? 
        pub fun getRoundRelease(_ id: String, address: Address): RoundRelease?? 
    }


    pub let moxyRoundsStorage: StoragePath
    pub let moxyRoundsPrivate: PrivatePath
    pub let moxyRoundsInfoPublic: PublicPath

    pub let roundReleasesStorage: StoragePath
    pub let roundReleasesPrivate: PrivatePath
    pub let roundReleasesInfoPublic: PublicPath

    // Initialize contract
    init(){
        
        // Moxy Rounds initialization
        let moxyRounds <- create Rounds()

        moxyRounds.addRound("seed", type: "Token Sale", name: "Seed", initialRelease: 45000000.0, lockTime: 30, months: 24)
        moxyRounds.addRound("private_1", type: "Token Sale", name: "Private 1", initialRelease: 75000000.0, lockTime: 0, months: 20)
        moxyRounds.addRound("private_2", type: "Token Sale", name: "Private 2", initialRelease: 120000000.0, lockTime: 0, months: 16)
        moxyRounds.addRound("public_presale", type: "Token Sale", name: "Public Whitelist", initialRelease: 18000000.0, lockTime: 0, months: 10)
        moxyRounds.addRound("public_ido", type: "Token Sale", name: "Public IDO", initialRelease: 4500000.0, lockTime: 30, months: 0)

        moxyRounds.addRound("team", type: "Token Allocation", name: "Team", initialRelease: 225000000.0, lockTime: 365, months: 24)
        moxyRounds.addRound("moxy_foundation", type: "Token Allocation", name: "Moxy Foundation", initialRelease: 375000000.0, lockTime: 180, months: 24)
        moxyRounds.addRound("advisors", type: "Token Allocation", name: "Advisors", initialRelease: 75000000.0, lockTime: 180, months: 24)
        moxyRounds.addRound("treasury", type: "Token Allocation", name: "Treasury", initialRelease: 150000000.0, lockTime: 90, months: 24)
        moxyRounds.addRound("ecosystem", type: "Token Allocation", name: "Ecosystem", initialRelease: 412500000.0, lockTime: 180, months: 24)

        // Storage of Rounds
        self.moxyRoundsStorage = /storage/moxyRounds
        self.moxyRoundsPrivate = /private/moxyRounds
        self.moxyRoundsInfoPublic = /public/moxyRoundsInfoPublic

        
        self.account.save(<-moxyRounds, to: self.moxyRoundsStorage)
        self.account.link<&MoxyReleaseRounds.Rounds>(self.moxyRoundsPrivate, target: self.moxyRoundsStorage)
        self.account.link<&MoxyReleaseRounds.Rounds{MoxyRoundsInfo}>(
                self.moxyRoundsInfoPublic, 
                target: self.moxyRoundsStorage)!

        // Storage of RoundRelease on user account
        self.roundReleasesStorage = /storage/roundReleaseStorage
        self.roundReleasesPrivate = /private/roundReleasePrivate
        self.roundReleasesInfoPublic = /public/roundReleaseInfoPublic
    }
}
 