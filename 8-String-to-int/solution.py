# Original
class Solution:
    def myAtoi(self, s: str) -> int:
        min_i32 = -2147483648
        max_i32 = 2147483647

        stripped = s.strip() # strip whitespace
        
        if len(stripped) == 0:
            return 0

        sign = 1
        if stripped[0] == '-':
            sign = -1
            stripped = stripped[1:]
        elif stripped[0] == '+':
            stripped = stripped[1:]

        result = 0

        for char in stripped:
            if not char.isdigit():
                break
            digit = int(char)
            result = result * 10 + digit 
        
        res = result * sign
        if res < min_i32:
            res = min_i32
        elif res > max_i32:
            res = max_i32
        return res
