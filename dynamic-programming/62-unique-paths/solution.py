class Solution:
    def uniquePaths(self, m: int, n: int) -> int:
        # m x n grid init to 0s
        # +1 for 0s on the outside preventing index overflow
        grid = [[0 for _ in range(m + 1)] for _ in range(n + 1)]
        
        # Iter backwards from start point
        for row in range(n - 1, -1, -1):
            for col in range(m - 1, -1, -1):

                # Get grid value to right and bottom, the only ways to move
                right = grid[row][col + 1]
                down = grid[row + 1][col]
                
                # Both zero = finish pos = 1 possible path
                if right == 0 and down == 0:
                    grid[row][col] = 1
                else:
                    # Else possible paths from pos is sum
                    grid[row][col] = right + down
        
        # for g in grid:
        #     print(g)
        
        # Return start pos (top left)
        return grid[0][0] 
