class Solution:

    def permute(self, nums: list[int]) -> list[list[int]]:
        l = len(nums)
        lc = {0: 1}     # len to combo mapping
        for i in range(1, l + 1):
            lc[i] = i * lc[i - 1]   # cache all len -> combo 
        
        n_combos = lc[l]    # all unique combos at l

        combos = [[0] * l for _ in range(n_combos)] # premake return list init to 0

        # for each unique permutation

        for i in range(len(combos)):
            rem = nums.copy()   # mutable copy of numbers available


            # j = which position filling in permutation row
            for j in range(l):
                f = lc[l - j - 1]   # factor, amount of permutations available at current position
                idx = (i // f) % len(rem)   # index of number to select/insert

                combos[i][j] = rem.pop(idx) # pop from remaining an put in return

        return combos
        
