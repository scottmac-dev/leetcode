class Solution:
    def coinChange(self, coins: list[int], amount: int) -> int:
        dp = [0] + [float("inf")] * amount  # base case, inf = no solution
        # for each coin
        for c in coins:
            #print(c)
            # iter over range c -> amount
            for t in range(c, amount + 1):
                # get new min
                dp[t] = min(dp[t], dp[t - c] + 1)
                #print(dp)

        # dp[amount] = minimum coins amount summing to amount
        # inf = not possible
        return dp[amount] if dp[amount] != float("inf") else -1
