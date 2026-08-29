# Initial solution
class Solution:
    def removeDuplicates(self, nums: List[int]) -> int:
        unique = set()
        duplicates = {}
        for n in nums:
            if n in unique:
                if n in duplicates:
                    cur = duplicates[n]
                    duplicates[n] = cur + 1
                else:
                    duplicates[n] = 1
            else:
                unique.add(n)
        

        for k, v in duplicates.items():
            for i in range(0, v):

                nums.remove(k)
        return len(unique)

# Better solution, dont remove, shift forward
# Solution doesnt require actually removing, just aligning unique at start
class Solution:
    def removeDuplicates(self, nums: List[int]) -> int:
        i,k = 0,1
        for i in range(1, len(nums)):
            if nums[i] != nums[i - 1]:
                nums[k] = nums[i]  # Move the unique element forward
                k += 1
        return k
