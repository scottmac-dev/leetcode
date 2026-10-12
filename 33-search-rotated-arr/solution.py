class Solution:
    def search(self, nums: list[int], target: int) -> int:
        # empty list
        if not nums:
            return -1
        
        # find index rotated at
        r_idx = 0
        start = nums[0]
        for i, n in enumerate(nums):

            # if found searching for r_idx, just return
            if n == target:
                return i
            if n < start:
                r_idx = i
                break
        
        # at this point it is not in the first section
        # perform binary search on r_idx -> len 
        l = r_idx
        r = len(nums) - 1
            
        while l <= r:
            mid = (l + r) // 2
            n = nums[mid]
            #print(l, r, mid, n)
            
            if n == target:
                return mid
            elif n < target:
                l = mid + 1
            else:
                r = mid - 1
        
        return -1


        
