class Solution:
    def searchInsert(self, nums: list[int], target: int) -> int:
        i = 0 # start
        j = len(nums) - 1 # end
        
        # while not exhausted
        while i <= j:
            half = (i + j) // 2 # midpoint
            n = nums[half] # value at midpoint

            if n == target:
                return half
            elif n < target:
                # less than target, must be to right
                i = half + 1
            else:
                # greater than target must be to left
                j = half - 1

        return i
            
