class Solution:
    def removeElement(self, nums: List[int], val: int) -> int:
        if len(nums) == 0:
            return 0
        
        k = 0
        for i in range(0, len(nums)):
            # Not element to remove
            if nums[i] != val:

                # Push to front
                nums[k] = nums[i]
                k += 1

                # By default all val is overridden

        return k # amount of non val elements


