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
