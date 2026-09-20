# Initial
class Solution:
    def reverseDegree(self, s: str) -> int:
        alpha = "abcdefghijklmnopqrstuvwxyz"
        v = 26
        cv = {}
        for a in alpha:
            cv[a] = v
            v -= 1
        
        r = 0
        for i, c in enumerate(s):
            r += cv[c] * (i + 1)
        
        return r

# More efficient
class Solution:
    def reverseDegree(self, s: str) -> int:

        ans, idx = 0, 1
        for ch in s:
            ans+= (123 - ord(ch)) * idx
            idx+= 1


        return ans
