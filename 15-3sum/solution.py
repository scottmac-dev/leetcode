# Inefficient O(n^2) solution
# Fixes i and solves two sum on j, k
class Solution:

    def two_sum(
        self, 
        i:int, 
        nums: list[int], 
        seen: set(),
        res: list[int], 
        target: int) -> Optional[(int, int)]:

        prev = {}
        for k, n in enumerate(nums):
            if k == i:
                continue
            remaining = target - n
            if remaining in prev:
                j = prev[remaining]
                ni, nj, nk = nums[i], nums[j], nums[k]
                triplet = tuple(sorted((ni, nj, nk)))
                if triplet not in seen:
                    res.append([ni, nj, nk])
                    seen.add(triplet)
                    #print(ni, nj, nk)
            prev[n] = k

  
    def threeSum(self, nums: list[int]) -> list[list[int]]:
        seen = set()
        unique = set()
        res = []
        for i, n in enumerate(nums):
            if n not in unique:
                target = -n
                self.two_sum(i, nums, seen, res, target)
            unique.add(n)

        return res

# Most common solution 
class Solution:
    def threeSum(self, nums: list[int]) -> list[list[int]]:
        res = []
        nums.sort() # sort upfront

        # Iter over len - 2
        for p1 in range(len(nums) - 2):

            # Skip duplicate p1, already calculated for 
            if p1 == 0 or nums[p1] != nums[p1 - 1]:

                # Take next and last value from sorted nums
                p2, p3 = p1 + 1, len(nums) - 1

                # Loop until they meet
                while p2 < p3:

                    # sum
                    s = nums[p1] + nums[p2] + nums[p3]
                    if s == 0:

                        # match for 0 target
                        res.append([nums[p1], nums[p2], nums[p3]])

                        # skip duplicates forward and backward
                        while p2 < p3 and nums[p2] == nums[p2 + 1]:
                            p2 += 1
                        while p2 < p3 and nums[p3] == nums[p3 - 1]:
                            p3 -= 1
                        p2 += 1
                        p3 -= 1

                    # less than 0 step forward
                    elif s < 0:
                        p2 += 1
                    # greater than 0 step back from end
                    else:
                        p3 -= 1

        return res
