
pub contract LinearRelease {

    pub resource LinearSchedule {
        pub var tgeDate: UFix64
        pub var totalAmount: UFix64
        pub var initialAmount: UFix64
        pub let unlockDate: UFix64
        pub var unlockAmount: UFix64
        pub let days: Int
        pub var dailyAmount: UFix64
        pub var lastReleaseDate: UFix64

        pub fun setStartDate(timestamp: UFix64) {
            self.tgeDate = timestamp
            self.lastReleaseDate = timestamp
        }

        pub fun updateLastReleaseDate() {
            self.lastReleaseDate = getCurrentBlock().timestamp
        }

        pub fun getTotalToUnlock(): UFix64 {
            var total = 0.0 
            total = total + self.getAmountAtTGEToPay()
            total = total + self.getAmountAfterUnlockToPay()
            total = total + self.getDailyAmountToPay()
            return total 
        }

        pub fun getDaysRemaining(): UFix64 {
            /* 
                Returns the remaining days to pay depending the last release paid
             */
            let today0000 = self.getTimestampTo0000(timestamp: getCurrentBlock().timestamp)
            let lastRelease0000 = self.getTimestampTo0000(timestamp: self.lastReleaseDate)

            return (today0000 - lastRelease0000) / 86400.0
        }

        pub fun getAmountAtTGEToPay(): UFix64 {
            if (self.lastReleaseDate <= self.tgeDate) {
                return self.initialAmount
            }
            // Returns zero if amount is already paid
            return 0.0
        }

        pub fun getAmountAtTGE(): UFix64 {
            return self.initialAmount
        }

        pub fun getAmountAfterUnlockToPay(): UFix64 {
            if (self.lastReleaseDate <= self.unlockDate) {
                return self.unlockAmount
            }
            // Returns zero if amount is already paid
            return 0.0
        }

        pub fun getAmountAfterUnlock(): UFix64 {
            return self.unlockAmount
        }

        pub fun getDailyAmountToPay(): UFix64 {
            let days = self.getDaysRemaining()
            return self.dailyAmount * days 
        }

        pub fun getDailyAmount(): UFix64 {
            return self.dailyAmount
        }

        pub fun getTotalDailyAmount(): UFix64 {
            return (self.totalAmount - ( self.initialAmount + self.unlockAmount ))
        }

        pub fun getTimestampTo0000(timestamp: UFix64): UFix64 {
            let days = timestamp / 86400.0
            return UFix64(UInt64(days)) * 86400.0
        }

        init(tgeDate: UFix64, totalAmount: UFix64, initialAmount: UFix64, unlockDate: UFix64, unlockAmount: UFix64, days: Int, dailyAmount: UFix64) {
            self.tgeDate = tgeDate
            self.totalAmount = totalAmount
            self.initialAmount = initialAmount
            self.unlockDate = unlockDate
            self.unlockAmount = unlockAmount
            self.days = days
            self.dailyAmount = dailyAmount
            self.lastReleaseDate = tgeDate
        }

    }

    pub fun createLinearSchedule(tgeDate: UFix64, totalAmount: UFix64, initialAmount: UFix64, unlockDate: UFix64, unlockAmount: UFix64, days: Int, dailyAmount: UFix64): @LinearSchedule {
        return <-create LinearSchedule(tgeDate: tgeDate, totalAmount: totalAmount, 
                        initialAmount: initialAmount, unlockDate: unlockDate, 
                        unlockAmount: unlockAmount, days: days, dailyAmount: dailyAmount)
    }


}
 