class Solution:
    def maxArea(self, height: list[int]) -> int:
        m = 0   # max tracker
        i = 0
        j = len(height) - 1

        # O(n) solution works towards middle
        while i < j:
            start = height[i]
            end = height[j]
            width = j - i
            area = min(start, end) * width
            if area > m:
                m = area

            # walk forward
            if start <= end:
                i += 1
            else:
                # walk back
                j -= 1
        return m
