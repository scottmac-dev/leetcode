class Solution:
    def longestCommonSubsequence(self, text1: str, text2: str) -> int:
        # grid representing both strings + 1 empty for index
        grid = [[0 for _ in range(len(text1) + 1)] for _ in range(len(text2) + 1)]
        
        # iter over rows and cols to find matching chars
        for row in range(len(text2) - 1, -1, -1):
            for col in range(len(text1) - 1, -1, -1):

                # matched text1 char to text 2 char at row x col
                if text1[col] == text2[row]:
                    grid[row][col] = 1  # match
                    grid[row][col] += grid[row + 1][col + 1] # add the diagonal (running total)
                else:
                    # no match, carry forward the max of bottom and right (prev matched)
                    grid[row][col] = max(grid[row + 1][col], grid[row][col + 1]) 
                # print(text1[col])
                # print(text2[row])
        
        # for g in grid:
        #     print(g)
        
        # badabim badaboom, longest substr len 
        return grid[0][0]
