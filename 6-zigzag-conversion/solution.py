# length = 14
# 0 1 2 3 4 5 6 7 8 9 10 11 12 13
# P A Y P A L I S H I R  I  N  G

# n rows = 3
# n cols = 4
# 0 4 8 12 1 3 5 7 9 11 13 2 6 10
# P A H N  A P L S I I  G  Y I R

# n rows = 4
# n cols = 3
# 0 6 12 1 5 7 9 13 2 4 8 10 3 9
# P I N  A L S I G  Y A H R  P I

# Original
class Solution:
    def convert(self, s: str, numRows: int) -> str:
        rows = {}
        length = len(s)

        if numRows >= length or numRows == 1:
            return s

        down = True
        n = 1
        for c in s:
            if n in rows:
                prev = rows[n]
                rows[n] = prev + c
            else:
                rows[n] = c
            
            #print(c, n)
            
            if down and n < numRows:
                n += 1
            elif not down and n > 1:
                n -= 1
            elif n == numRows:
                down = False
                n -= 1
            else:
                down = True
                n += 1
        
        res = ""
        for n in range(1, numRows + 1):
            res += rows[n]
        
        return res

# Better
class Solution:
    def convert(self, s: str, numRows: int) -> str:
        if numRows == 1 or numRows >= len(s):
            return s
        rows = [""] * numRows
        current_row = 0
        going_down = False
        for char in s:
            rows[current_row] += char
            if current_row == 0 or current_row == numRows - 1:
                going_down = not going_down
            if going_down:
                current_row += 1
            else:
                current_row -= 1
        return "".join(rows)

