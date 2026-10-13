# 2D approach failed
#class Solution:
#    def canJump(self, nums: list[int]) -> bool:

        # dp = [[False] * len(nums) for n in nums]
        # for i in range(len(nums), -1, -1):
        #     for j in range(len(nums) - 1, -1, -1):
        #         if j < i:
        #             continue
        #         if i == len(nums) - 1:
        #             dp[i][j] = True
        #             continue
        #         n = nums[i]
        #         if i + n >= j and i != j:
        #             dp[i][j] = True

        # # for r in dp:
        # #     print(r)
        # return False
        

# 1D approach passes, but inefficient
class Solution:
    def canJump(self, nums: list[int]) -> bool:
        dp = [False for _ in nums]
        for i in range(len(nums) - 1, -1 , -1):
            if i == len(nums) - 1:
                dp[i] = True
            else:
                n = nums[i]
                if n == 0:
                    continue
                for j in range(i + 1, i + n + 1):
                    #print(i, n, "can reach", j)
                    if j <= len(nums) - 1:
                        if dp[j]:
                            dp[i] = True
                            break
                    else:
                        break
        #print(dp)
        return dp[0]

# Efficient solution from answers
class Solution:
    def canJump(self, nums: list[int]) -> bool:
        petrol = 0  # how far it can jump
        for p in nums:
            # out of petrol, cannot reach end idx
            if petrol < 0: 
                return False
            # current reachable n has more jump space than current
            if p > petrol:
                petrol = p
            # decrement petrol each iter
            petrol -= 1

        # not out of petrol, can reach
        return True
