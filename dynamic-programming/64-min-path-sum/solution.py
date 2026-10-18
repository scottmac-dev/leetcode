# Solid one shot on this one, similar to 62 but working forward
class Solution:
    def minPathSum(self, grid: list[list[int]]) -> int:
        m = len(grid)
        n = len(grid[0])
        #print(m, n)

        for i in range(m):
            for j in range(n):
                # top row
                if i == 0:
                    # skip top left

                    if j == 0:
                        continue
                    # min is prev left + current
                    grid[i][j] = grid[i][j] + grid[i][j - 1]
                
                # first of each row, can only access from top
                elif j == 0:
                    grid[i][j] = grid[i][j] + grid[i - 1][j]
                
                # else determins min(left, top) + current
                else:
                    l = grid[i][j - 1]
                    t = grid[i - 1][j]
                    grid[i][j] = grid[i][j] + min(l, t)
        
        #for g in grid:
        #    print(g)
        
        # bottom right corner contains min path sum
        return grid[m - 1][n - 1]
        
