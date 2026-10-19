class Solution:
    def change(self, amount: int, coins: list[int]) -> int:
        # Unbounded knapsack, infinite reuse allowed
        dp = [[0] * (amount + 1) for _ in coins]

        for i in range(len(coins) - 1, -1, -1):
            coin = coins[i]
            for j in range(amount, -1, -1):
                # j == amount = 0 = reached target, aka base case

                if j == amount:
                    dp[i][j] = 1
                # i == len(coins) - 1 == bottom row = no below option
                elif i == len(coins) - 1:

                    val = amount - j
                    remains = val - coin
                    if remains >= 0:
                        dp[i][j] = dp[i][amount - remains]

                    else:
                        dp[i][j] = 0
                # else must have values to right and bottom
                else:
                    val = amount - j
                    remains = val - coin
                    # + right and bottom
                    if remains >= 0:
                        dp[i][j] = dp[i][amount - remains] + dp[i + 1][j]
                    else:
                        # only plus bottom
                        dp[i][j] = dp[i + 1][j]

                
        return dp[0][0]
