class Solution:
    def jump(self, nums: list[int]) -> int:

        l = len(nums)
        if l == 1: return 0

        dp = [0] * l
        for i in range(l - 1, -1, -1):

            n = nums[i]
            if n == 0:
                dp[i] = float('inf')
            elif i + n >= l - 1:
                dp[i] = 1
            else:
                dp[i] = 1 + min(dp[i + 1: i + n + 1])
        #print(dp)

        return dp[0]

