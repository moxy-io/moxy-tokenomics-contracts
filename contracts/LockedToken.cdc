import FungibleToken from "./flow/FungibleToken.cdc"
import LinearRelease from "./LinearRelease.cdc"

pub contract LockedToken {

    /// LockedTokensWithdrawn
    ///
    /// The event that is emitted when locked tokens are withdrawn from a Vault
    /// due to an MV to MOX convert request
    pub event LockedTokensWithdrawn(amount: UFix64, from: Address?)

    pub resource FixedBalances {
        pub var schedule: @LinearRelease.LinearSchedule
        pub var dailyAmount: UFix64

        pub fun unlockAmounts(): UFix64 {
            let amount = self.schedule.getDailyAmountToPay()
            self.schedule.updateLastReleaseDate()

            return amount
        }

        init(schedule: @LinearRelease.LinearSchedule, dailyAmount: UFix64) {
            self.schedule <- schedule
            self.dailyAmount = dailyAmount
        }

        destroy() {
            destroy self.schedule
        }
    }

    pub resource LockedVault: Receiver, Balance {
        access(contract) var lockedBalances: {UFix64:UFix64}
        access(contract) var lockedFixedBalances: @[FixedBalances]
        access(contract) var vault: @FungibleToken.Vault

        pub fun getBalance():UFix64 {
            return self.vault.balance
        }

        pub fun getLockedBalances(): {UFix64:UFix64} {
            return self.lockedBalances
        }

        pub fun deposit(from: @FungibleToken.Vault) {
            self.depositFor(from: <-from, time: getCurrentBlock().timestamp)
        }

        pub fun depositFor(from: @FungibleToken.Vault, time: UFix64) {
            let amount = from.balance
            self.vault.deposit(from: <-from)
            if (self.lockedBalances[time] == nil) {
                self.lockedBalances[time] = 0.0
            } 
            self.lockedBalances[time] = self.lockedBalances[time]! + amount
        }

        pub fun depositFromFixedSchedule(from: @FungibleToken.Vault, schedule: @LinearRelease.LinearSchedule) {
            let dailyAmount = from.balance / UFix64(schedule.days)

            self.vault.deposit(from: <-from)

            let fixedBalances <- create FixedBalances(schedule: <-schedule, dailyAmount: dailyAmount)
            self.lockedFixedBalances.append(<-fixedBalances)
        }

        pub fun depositFromSchedule(from: @FungibleToken.Vault, schedule: {UFix64:UFix64}) {
            self.vault.deposit(from: <-from)
            // Merge schedules with existing lockedBalances
            for time in schedule.keys {
                if (self.lockedBalances[time] == nil) {
                    self.lockedBalances[time] = 0.0
                }
                self.lockedBalances[time] = self.lockedBalances[time]! + schedule[time]!
            }
        }

        pub fun sumLockedBalances(): UFix64 {
            var total = 0.0
            for value in self.lockedBalances.values {
                total = total + value
            }
            return total
        }

        pub fun withdraw(amount: UFix64): @FungibleToken.Vault {
            emit LockedTokensWithdrawn(amount: amount, from: self.owner?.address)
            return <- self.vault.withdraw(amount: amount)            
        }

        // Withdraws the tokens that are available to unlock
        pub fun withdrawUnlocked(): @FungibleToken.Vault {
            let temp = self.lockedBalances
            var total = 0.0
            let dict = self.getUnlockBalancesFor(days: 0.0)
            for key in dict.keys {
                let value = dict[key]!
                let amount = self.lockedBalances[key]!
                self.lockedBalances.remove(key: key)
                total = total + amount
            }

            // Unlock fixed amounts
            var totalFixed = 0.0
            var i = 0
            while (i < self.lockedFixedBalances.length) {
                let amount = self.lockedFixedBalances[i].unlockAmounts()
                totalFixed = totalFixed + amount
                i = i + 1
            }
            total = total + totalFixed

            return <-self.vault.withdraw(amount: total)
        }

        pub fun getTotalLockedBalance(): UFix64 {
            return self.vault.balance
        }

        pub fun getTotalToUnlockBalanceFor(days: UFix64): UFix64 {
            // Returns the amount that will be unlocked in the next few days
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
            // Returns a dictionary with the amounts that will be unlocked in the next few days
            var dict: {UFix64:UFix64} = {} 
            var timestamp = getCurrentBlock().timestamp + (days * 86400.0)
            for key in self.lockedBalances.keys {
                if (key < timestamp) {
                    dict[key] = self.lockedBalances[key]! 
                }
            }
            return dict
        }

        init(vault: @FungibleToken.Vault) {
            self.lockedBalances = {}
            self.lockedFixedBalances <- []
            self.vault <- vault
        }

        destroy() {
            destroy self.vault
            destroy self.lockedFixedBalances
        }
    }

    pub resource interface Receiver {

        /// deposit takes a Vault and deposits it into the implementing resource type
        ///
        pub fun deposit(from: @FungibleToken.Vault)
        pub fun depositFor(from: @FungibleToken.Vault, time: UFix64)
        pub fun depositFromSchedule(from: @FungibleToken.Vault, schedule: {UFix64:UFix64})
        pub fun depositFromFixedSchedule(from: @FungibleToken.Vault, schedule: @LinearRelease.LinearSchedule)
        pub fun withdrawUnlocked(): @FungibleToken.Vault 
    }

    pub resource interface Balance {

        /// The total balance of a vault
        ///
        pub fun getBalance():UFix64
        pub fun getLockedBalances(): {UFix64:UFix64} 
        pub fun getTotalToUnlockBalanceFor(days: UFix64): UFix64 
        pub fun getTotalLockedBalance(): UFix64 
    }

    pub fun createLockedVault(vault: @FungibleToken.Vault): @LockedVault {
        return <-create LockedVault(vault: <-vault)
    }

}
 