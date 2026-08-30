# Initial solution
class Solution:
    def isValidSudoku(self, board: List[List[str]]) -> bool:
        cols = {i: set() for i in range(9)}        

        for i, r in enumerate(board):

            row = set()

            for j, c in enumerate(r):

                # Check grid on top left index
                if i % 3 == 0 and j % 3 == 0:
                    grid = set()
                    r_start = i
                    r_end = r_start + 3
                    c_start = j
                    c_end = c_start + 3
                    print(r_start, r_end, c_start, c_end)
                    for k in range(r_start, r_end):
                        for l in range(c_start, c_end):
                            val = board[k][l]

                            if val == '.':
                                continue
                            if val in grid:

                                return False

                            grid.add(val)
                
                # Skip .
                if c == '.':
                    continue
                
                # Check row
                if c in row:
                    return False
                row.add(c)

                # Check col
                column = cols[j]
                if c in column:
                    return False

                column.add(c)
                
        return True

# More efficient
class Solution:
    def isValidSudoku(self, board: List[List[str]]) -> bool:
        # All sets upfront
        vertical_checks = [set() for i in range(9)]
        horizontal_checks = [set() for i in range(9)]
        squar_checks = [set() for i in range(9)]


        for i, row in enumerate(board):
            for j, cell in enumerate(row):
                if cell == ".":
                    continue

                # Check column 
                if cell in vertical_checks[i]:
                    return False

                else:
                    vertical_checks[i].add(cell)

                # Check row
                if cell in horizontal_checks[j]:
                    return False
                else:
                    horizontal_checks[j].add(cell)

                # Grid num is i // 3 * 3 + j // 3
                # Eg middle grid 4 x 4
                # = 4 // 3 * 3 + 4 // 3
                # = 1 * 3 + 1
                # = 4 = grid number 4
                # 0 1 2
                # 3 4 5
                # 6 7 8
                if cell in squar_checks[(i // 3) * 3 + (j // 3)]:
                    return False
                else:

                    squar_checks[(i // 3) * 3 + (j // 3)].add(cell)
        
        return True
        
