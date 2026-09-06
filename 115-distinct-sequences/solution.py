# Correct but inefficient enough to submit
class Solution:
    def helper(self, s: str, t: str, i: int, j: int) -> int:
        # j == len(t) implies all of t has been matched
        if j == len(t):
            return 1

        # prevent index overflow, s is exhausted no match 
        if i >= len(s):
            return 0

        # on char max
        if s[i] == t[j]:
            # choose to use and skip the match to allow all combos
            # on match 
            #   -> use and consumer
            #   -> purposefully skip to explore other options
            use = self.helper(s, t, i + 1, j + 1)
            skip = self.helper(s, t, i + 1, j)

            # return sum of both cases
            return  use + skip
        else:
            # else just skip
            return self.helper(s, t, i + 1, j)
        
        
    def numDistinct(self, s: str, t: str) -> int:
        return self.helper(s, t, 0, 0)

# Same as above but with memoization
# cache every i, j result to avoid recalculating i, j in every recursion
# just passes benchmark for submission but still inefficient
class Solution:

    memo = {}

    def helper(self, s: str, t: str, i: int, j: int) -> int:
        if (i, j) in self.memo:
            return self.memo[(i, j)]

        if j == len(t):
            return 1
        if i >= len(s):
            return 0

        res = None
        if s[i] == t[j]:
            use = self.helper(s, t, i + 1, j + 1)
            skip = self.helper(s, t, i + 1, j)
            res = use + skip
        else:
            res = self.helper(s, t, i + 1, j)

        # self.memo cache result 
        self.memo[(i, j)] = res 
        return res
        
    def numDistinct(self, s: str, t: str) -> int:
        self.memo = {}
        return self.helper(s, t, 0, 0)

# More efficient alternative (from leetcode)
class Solution:
    def numDistinct(self, s: str, t: str) -> int:
        # edge case
        if len(t) > len(s):
            return 0

        memo = {} # same memo but at function level

        # sub helper for recursion
        def dfs(i, j):
            # i == len(s) = exhausted search
            # j == len(t) = matched target
            # len(s) - i < len(t) - j = not enough remaining s char to fill target
            if i == len(s) or j == len(t) or len(s) - i < len(t) - j:

                # bool -> int conversion
                # j == len(t) = match = True = 1
                # else 0 False
                return int(j == len(t))

            # not break case search memo dictionary for O(1) lookup
            if (i, j) in memo:
                return memo[(i, j)]

            # calculate answer for (i + 1, j) = the skip case used above
            ans = dfs(i + 1, j)
            
            # match on index
            if s[i] == t[j]:

                # answer becomes the use case
                ans += dfs(i + 1, j + 1)

            # cache the answer calculated in memo
            memo[(i, j)] = ans
            return ans
        
        # recursive call from (0,0)
        return dfs(0, 0)
