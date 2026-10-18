class Solution:
    def numTrees(self, n):
        dp = [1] + [0] * n # dp[0] = 1, empty subtree is one valid arrangement

        # build up from small trees to big ones

        for size in range(1, n + 1):

            # try every value k (1..size) as the root
            for k in range(1, size + 1):

                left_nodes = k - 1       # values 1..k-1
                right_nodes = size - k   # values k+1..size

                # any left shape can pair with any right shape, so multiply counts
                trees_with_root_k = dp[left_nodes] * dp[right_nodes]

                # each root gives a different set of trees, so add them up
                dp[size] += trees_with_root_k
            

            #print(dp)
        return dp[n]    # dp[n] = number unique BSTs of length 1..n
