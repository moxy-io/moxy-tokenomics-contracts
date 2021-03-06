
pub contract MoxyData {
    
    /** Resource to store key: Timestamp, value: amount
     *  The amounts in dictionary accumulates from last amounts added
     *  so the changes must to be calculated.
     */
    pub resource OrderedDictionary {
        pub var dictionary: {UFix64:UFix64}
        pub var arrayMap: [UFix64]

        pub fun getDictionary(): {UFix64: UFix64} {
            return self.dictionary
        }

        /**
            Returns the value for the given timestamp. If the timestamp
            is not found, it returns the most recent timestamp that is
            less than the parameter received.
         */
        pub fun getValueOrMostRecentFor(timestamp: UFix64): UFix64 {
            let time0000 = MoxyData.getTimestampTo0000(timestamp: timestamp)
            if (self.dictionary[time0000] != nil) {
                return self.dictionary[time0000]!
            }

            // For this day there are no registered balances, look for the
            // last recorded balance or zero if there are no previous records
            // per requested day
            var index = -1
            var hasActivity = false
            for time in self.arrayMap {
                if (time >= time0000  ) {
                    hasActivity = true
                    break
                }
                index = index + 1
            }
            if (index < 0) {
                // No previous activity
                return 0.0
            }
            return self.dictionary[self.arrayMap[index]]!
        }

        pub fun getValueFor(timestamp: UFix64): UFix64 {
            let time0000 = MoxyData.getTimestampTo0000(timestamp: timestamp)
            if (self.dictionary[time0000] == nil) {
                return 0.0
            }
            return self.dictionary[time0000]!
        }

        pub fun getValueForToday(): UFix64 {
            let balance = self.getValueOrMostRecentFor(timestamp: getCurrentBlock().timestamp)
            if (balance == nil) {
                return 0.0
            }
            return balance
        }

        pub fun getValueChangeForToday(): UFix64 {
            return self.getValueChange(timestamp: getCurrentBlock().timestamp)
        }

        pub fun getValueChange(timestamp: UFix64): UFix64 {
            let time0000 = MoxyData.getTimestampTo0000(timestamp: timestamp)

            if (self.dictionary.length < 1) {
                // No records > no change
                return 0.0
            }
            if (self.arrayMap[0] > time0000 ) {
                // Date is previous to the first registered
                return 0.0
            }
            var lastTimestamp = self.getLastKeyAdded()
            if (time0000 > lastTimestamp!) {
                // Date is over last timestamp
                return 0.0
            }

            // Balance en la fecha consultada
            var timestamp = self.dictionary[time0000]
            
            if (timestamp == nil) {
                // No records > no changes
                return 0.0
            }

            // Look for last balance
            if (self.arrayMap[0] == time0000 ) {
                // No previous > change is balance total
                return timestamp!
            }

            // There is a balance, we have to look for the previous balance to see
            // what was the change
            var index = 0
            for time in self.arrayMap {
                if (time == time0000) {
                    break
                }
                index = index + 1
            }
            let indexBefore = index - 1
            var timestampBefore = self.dictionary[self.arrayMap[indexBefore]]

            return timestamp! - timestampBefore!
        }

        pub fun getValueChanges(): {UFix64:UFix64} {
            let resu: {UFix64:UFix64} = {}
            var timeBefore = 0.0
            for time in self.arrayMap {
                resu[time] = self.dictionary[time]! - timeBefore
                timeBefore = self.dictionary[time]!
            }

            return resu
        }

        pub fun getLastKeyAdded(): UFix64? {
            let pos = self.dictionary.length - 1
            if (pos < 0) {
                return nil
            }
            return self.arrayMap[pos]
        }

        pub fun getFirstKeyAdded(): UFix64? {
            if (self.arrayMap.length == 0) {
                return nil
            }
            return self.arrayMap[0]
        }

        pub fun getLastValue(): UFix64 {
            let pos = self.dictionary.length - 1
            if (pos < 0) {
                return 0.0
            }
            return self.dictionary[self.arrayMap[pos]!]!
        }


        access(account) fun setAmountFor(timestamp: UFix64, amount: UFix64) {
            let time0000 = MoxyData.getTimestampTo0000(timestamp: timestamp)
            let lastTimestamp = self.getLastKeyAdded()
            // Check if timestamp to add exists and that is greater than
            // the last timestamp added, to keep order on arrayMap
            if (lastTimestamp == nil || time0000 > lastTimestamp!) {
                // Assign last value as initial amount for required timestamp
                self.dictionary[time0000] = self.getLastValue()
                self.arrayMap.append(time0000)
            }
            self.dictionary[time0000] = self.dictionary[time0000]! + amount           
        }

        pub fun canUpdateTo(timestamp: UFix64): Bool {

            let time0000 = MoxyData.getTimestampTo0000(timestamp: timestamp)
            let lastTimestamp = self.getLastKeyAdded()

            // Returns true if there are no registered timestamp yet or
            // if the time to add is equal or greater than the las timestamp added.
            return lastTimestamp == nil || time0000 >= lastTimestamp!
        }

        access(account) fun withdrawValueFromOldest(amount: UFix64) {
            var amountToWithdraw = amount
            while(amountToWithdraw > 0.0 && self.arrayMap.length > 0) {
                let timestamp = self.arrayMap[0]!
                let balance = self.dictionary[timestamp]!
                if (amountToWithdraw > balance ) {
                    //balance of the day is not enough for total withdraw
                    amountToWithdraw = amountToWithdraw - balance
                    //remove daily balance
                    self.dictionary.remove(key: timestamp)
                    self.arrayMap.remove(at: 0)
                } else {
                    //balance is enough to complete total withdraw
                    self.dictionary[timestamp] = balance - amountToWithdraw
                    amountToWithdraw = 0.0
                }
            }
            if (amountToWithdraw > 0.0) {
                panic("Not enaugh amount to withdraw from dictionary.")
            }
        }

        access(account) fun destroyWith(orderedDictionary: @OrderedDictionary) {
            let dict = orderedDictionary.getDictionary()
            for timestamp in dict.keys {
                self.dictionary[timestamp] = self.dictionary[timestamp]! - dict[timestamp]!
            }

            destroy orderedDictionary
        }


        init() {
            self.dictionary = {}
            self.arrayMap = []
        }

    }

    pub resource interface OrderedDictionaryInfo {
        pub fun getDictionary(): {UFix64: UFix64}
    }

    pub fun getTimestampTo0000(timestamp: UFix64): UFix64 {
        let days = timestamp / 86400.0
        return UFix64(UInt64(days)) * 86400.0
    }

    pub fun createNewOrderedDictionary(): @OrderedDictionary {
        return <-create OrderedDictionary()
    }

    
    init() {

    }
}
 