# Initial attempt, not efficient enough
# Essentially O(n)^2 with inned min calculation
# O(n) x O(n-i)
class Solution:
    def firstStableIndex(self, nums: list[int], k: int) -> int:
        ret_i = -1

        if not nums:
            return ret_i

        maximum = nums[0]   # efficient maximum O(1) only incremented when needed
        for i, n in enumerate(nums):
            back = nums[i:]

            if n > maximum:
                maximum = n

            minimum = min(back) # inefficient minimum recalculating O(i..N) each loop

            i_score = maximum - minimum

            if i_score <= k:
                return i

        return ret_i

# Next attempt much more efficient
# Doesnt recalculate minimum every loop, only when known minimum is pushed out of back
# O(N) + O(N) with occasional O(N-i) when recalculating, equals out to O(2N) ~ O(N) no constants
# I suppose could approach solution 1 if the list was ordered as a list in ascending order would 
# recalculate each loop. eg 1,2,3,4, the minimum is pushed out each loop
class Solution:
    def firstStableIndex(self, nums: list[int], k: int) -> int:
        ret_i = -1

        if not nums:
            return ret_i

        maximum = nums[0]

        # Find minimum upfront once before hot loop
        minimum = min(nums)

        # Track the last position of the minimum (closest to back)
        min_pos = len(nums) - 1 - nums[::-1].index(minimum)
        
        for i, n in enumerate(nums):

            if n > maximum:
                maximum = n

            # Once exceeding the last min position recalculate
            if i > min_pos:

                # Remaining values
                back = nums[i:]

                # Recalculate minimum and update last min pos
                minimum = min(back)
                min_pos = len(back) - 1 - back[::-1].index(minimum)


            i_score = maximum - minimum

            if i_score <= k:
                return i

        return ret_i

# Most efficient (from leetcode stats not mine)
# Visualised
# nums:     [7] [4] [9] [2] [6]
#            ↓   ↓   ↓   ↓   ↓
# prefix:    7   7   9   9   9    ← maximum going →
#            ↑   ↑   ↑   ↑   ↑
# suffix:    2   2   2   2   6    ← minimum coming ←
#
# Pure O(N) + O(N) no catch ~ O(2N) ~ O(N)
class Solution:
    def firstStableIndex(self, nums: list[int], k: int) -> int:
        n = len(nums)
        mini = [0] * n  # zeroed array

        # calculate minimum for each i right -> left first
        mint = float('inf')
        for i in range(n - 1, -1, -1):
            if nums[i] < mint:
                mint = nums[i]
            mini[i] = mint

        # iterate left -> right to find max and calculate stable index
        maxt = 0
        for i in range(n):
            if nums[i] > maxt:
                maxt = nums[i]
            if maxt - mini[i] <= k:
                return i

        return -1
