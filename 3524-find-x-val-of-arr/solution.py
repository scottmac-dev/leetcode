# Inefficient sliding window brute force solution
class Solution:
    def resultArray(self, nums: List[int], k: int) -> List[int]:
        res = [0] * k 
        max_window = len(nums)
        c_window = 1

        while c_window <= max_window:
            start_idx = 0
            end_idx = start_idx + c_window

            while end_idx <= max_window:
                sub = nums[start_idx:end_idx]
                if len(sub) == 1:

                    r = sub[0] % k
                    res[r] = res[r] + 1
                
                else:
                    prod = sub[0]
                    for i in range(1, len(sub)):
                        prod *= sub[i]
                    r = prod % k
                    res[r] = res[r] + 1
                
                start_idx += 1

                end_idx += 1

            c_window += 1
        return res

# Next attempt, more efficient iterative prod instead of slding window 
# Still to inefficient for submission
class Solution:
    def resultArray(self, nums: List[int], k: int) -> List[int]:
        res = [0] * k 
        pos = 0
        while pos < len(nums):
            start_idx = pos
            end_idx = start_idx + 1
            prod = nums[pos]
            r = prod % k
            res[r] = res[r] + 1


            while end_idx < len(nums):
                prod *= nums[end_idx]
                r = prod % k
                res[r] = res[r] + 1
                end_idx += 1
            
            pos +=1
        return res

# More efficient and passable solution 
# for each n, extend previous sub arrays ending at prev poition and add all sub arrays ending at n 
# EG.
# nums = [2,3,4] k = 5
# pos 0, new [2] -> rem 2, prev = { 2: 1 }
# pos 1, new [3] -> rem 3, extend [2] -> [2,3] -> (2 * 3) % 5 -> rem 1, curr = { 3: 1, 1: 1 }
# pos 2, new [4] -> rem 4, extend [3] -> [3,4] -> (3 * 4) % 5 -> rem 2, extend [2, 3] -> [2,3,4] -> (1 (rem of 2 * 3) * 4) % 5 -> rem 4, curr = { 4: 2, 2: 1 }
class Solution:
    def resultArray(self, nums: List[int], k: int) -> List[int]:
        result = [0] * k
        prev = [0] * k

        for num in nums:
            curr = [0] * k

            # subarray starting with [num]
            curr[num % k] += 1

            # extend subarrays ending at prev position
            for r in range(k):
                if prev[r]:

                    new_r = (r * num) % k
                    curr[new_r] += prev[r]


            # add subarrays ending here to res
            for r in range(k):
                result[r] += curr[r]

            prev = curr

        return result
