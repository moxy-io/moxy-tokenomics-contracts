
pub contract MoxyProcessQueue {

    pub resource Run {
        pub var startTime: UFix64
        pub var startTime0000: UFix64
        pub var lastUpdateTime: UFix64
        pub var endTime: UFix64
        pub var executions: Int
        pub var index: Int

        pub fun hasFinished(): Bool {
            return self.endTime > 0.0
        }

        pub fun isAtBeginning(): Bool {
            return self.index == 0
        }

        pub fun completeNextAddresses(quantity: Int) {
            self.index = self.index + quantity
            self.executions = self.executions + 1
            self.lastUpdateTime = getCurrentBlock().timestamp
        }

        pub fun finish() {
            self.endTime = getCurrentBlock().timestamp
        }

        pub fun accountsProcessed(): Int {
            return self.index
        }
        

        init() {
            self.startTime = getCurrentBlock().timestamp
            self.startTime0000 = MoxyProcessQueue.getTimestampTo0000(timestamp: getCurrentBlock().timestamp)
            self.lastUpdateTime = getCurrentBlock().timestamp
            self.endTime = 0.0
            self.executions = 0
            self.index = 0
        }

    }

    pub struct CurrentRunStatus {
        pub var totalAccounts: Int
        pub var startTime: UFix64
        pub var lastUpdated: UFix64
        pub var accountsProcessed: Int
        pub var accountsRemaining: Int
        pub var hasFinished: Bool

        init(totalAccounts: Int, startTime: UFix64, lastUpdated: UFix64, accountsProcessed: Int, accountsRemaining: Int, hasFinished: Bool) {
            self.totalAccounts = totalAccounts
            self.startTime = startTime
            self.lastUpdated = lastUpdated
            self.accountsProcessed = accountsProcessed
            self.accountsRemaining = accountsRemaining
            self.hasFinished = hasFinished
        }

    }

    pub resource Queue: QueueInfo {
        access(contract) var accounts: [Address]
        access(contract) var accountsDict: {Address:Int}
        pub var accountsQuantity: Int
        access(contract) var runs: @[Run]
        pub var currentRun: @Run

        pub fun addAccount(address: Address) {
            if (self.accountsDict[address] != nil) {
                log("Account already added to queue")
                return
            }
            self.accounts.append(address)
            self.accountsDict[address] = self.accounts.length - 1
            self.accountsQuantity = self.accountsQuantity + 1
        }

        pub fun removeAccount(address: Address) {
            self.accounts[self.accountsDict[address]!] = 0x0
            self.accountsQuantity = self.accountsQuantity - 1
        }
        
        access(contract) fun createNewRun() {
            let run <- self.currentRun <- create Run()
            self.runs.append(<-run)
        }

        pub fun isAtBeginning(): Bool {
            return self.currentRun.isAtBeginning()
        }

        pub fun hasFinished(): Bool {
            return self.currentRun.hasFinished()
        }

        pub fun isEmptyQueue(): Bool {
            return self.accountsQuantity < 1
        }

        pub fun getAccountsQuantity(): Int {
            return self.accountsQuantity
        }

        pub fun getNextAddresses(cant: Int): [Address] {
            let time0000 = MoxyProcessQueue.getTimestampTo0000(timestamp: getCurrentBlock().timestamp)
            if (self.currentRun.hasFinished() && self.currentRun.startTime0000 == time0000) {
                return []
            }

            if (self.currentRun.hasFinished()) {
                self.createNewRun()
            }

            var index = self.currentRun.index
            var added = 0
            let res: [Address] = []
            while (added < cant && index < self.accounts.length ) {
                if (self.accounts[index] != 0x0) {
                    res.append(self.accounts[index])
                    added = added + 1
                }
                index = index + 1
            }
            return res
        }

        pub fun completeNextAddresses(quantity: Int) {
            self.currentRun.completeNextAddresses(quantity: quantity)
            if (self.currentRun.index >= self.accounts.length) {
                self.currentRun.finish()
            }
        }

        pub fun getRemainings(): Int {
            return (self.accounts.length - self.currentRun.accountsProcessed()) 
        }

        pub fun getCurrentRunStatus(): CurrentRunStatus {
            return CurrentRunStatus(totalAccounts: self.accounts.length, startTime: self.currentRun.startTime, 
                        lastUpdated: self.currentRun.lastUpdateTime, accountsProcessed: self.currentRun.accountsProcessed(), 
                        accountsRemaining: self.getRemainings(), hasFinished: self.hasFinished())
        }

        init() {
            self.accounts = []
            self.accountsDict = {}
            self.accountsQuantity = 0
            self.runs <- []
            self.currentRun <- create Run()
        }

        destroy() {
            destroy self.runs
            destroy self.currentRun
        }
    }

    pub fun getTimestampTo0000(timestamp: UFix64): UFix64 {
        let days = timestamp / 86400.0
        return UFix64(UInt64(days)) * 86400.0
    }

    pub fun createNewQueue(): @Queue {
        return <- create Queue()
    }

    pub resource interface QueueInfo {
        pub fun getCurrentRunStatus(): CurrentRunStatus
    }


}
 