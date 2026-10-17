# Brute force, not efficient enough
class Solution:
    def maxSubArray(self, nums: list[int]) -> int:
        if not nums:
            return 0
        if len(nums) == 1:
            return nums[0]
        
        grid = [[0 for _ in range(len(nums))] for _ in range(len(nums))]

        max_sum = nums[0]
        for i in range(len(nums)):
            for j in range(len(nums)):
                if j < i:
                    continue
                if i == 0 and j == 0:
                    grid[i][j] = nums[i]
                else:
                    prev = grid[i][j - 1]
                    new = nums[j] + prev
                    if new > max_sum:
                        max_sum = new
                    grid[i][j] = new
        # for g in grid:
        #     print(g)
        return max_sum

# 1D solution passes
class Solution:
    def maxSubArray(self, nums: list[int]) -> int:
        if not nums:
            return 0
        if len(nums) == 1:
            return nums[0]
        
        dp = [0 for _ in range(len(nums))]

        max_sum = nums[0]
        for j in range(len(nums)):
            if j == 0:
                dp[j] = nums[0]
            else:
                if dp[j - 1] + nums[j] > nums[j]:
                    dp[j] =  dp[j - 1] + nums[j]
                else:
                    dp[j] = nums[j]
            if dp[j] > max_sum:
                max_sum = dp[j]

        #print(dp)
        return max_sum

