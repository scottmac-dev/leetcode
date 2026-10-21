# brute force, poor efficiency
class Solution:
    def minOperations(self, s: str) -> int:
        l = len(s)
        start, end = s[0], s[-1]
        
        is_sorted = True
        start_min = True

        start_max = True
        start_repeated = False

        end_min = True
        end_max = True
        end_repeated = False

        for i, c in enumerate(s):
            if i > 0 and c < s[i - 1]:
                is_sorted = False
            if i > 0 and c == start:

                start_repeated = True
            if i < l - 1 and c == end:
                end_repeated = True
            if c < start:
                start_min = False
            if c > end:
                end_max = False
            if c > start:
                start_max = False
            if c < end:
                end_min = False
        

        # sorted = 0 changes

        if is_sorted:
            return 0
        # two characters and not sorted, no way to sort
        if l == 2:
            return -1
        # min start = sort [1:], end max = sort[:-1], 1 substr sort
        if start_min or end_max:
            return 1

        # 3 ops required is start is unique max and end unique min
        if start_max and end_min and not start_repeated and not end_repeated:
            return 3
        # else always 2, get start min or end max and repeat 1 case
        return 2


