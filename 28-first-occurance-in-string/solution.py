# Inital attempt, pass but inefficient
class Solution:

    def strStr(self, haystack: str, needle: str) -> int:
        # iterate
        for i, c in enumerate(haystack):
            j = 0

            # if match start of needle, explore
            if c == needle[j]:
                k = i

                # keep exploring while matching
                while k < len(haystack):
                    if j == len(needle):
                        return i
                    if haystack[k] == needle[j]:
                        k += 1
                        j += 1
                        continue
                    break

                # edge case for needle matches last char in haystack
                if j == len(needle):
                        return i
        return -1 # base case

# More efficient from leetcode solutions 
class Solution:
    def strStr(self, haystack: str, needle: str) -> int:
        l=len(needle) # len needle to match

        # iter over haystack
        for i in range(len(haystack)):

            # attempt match on full substring
            if haystack[i:l]==needle:
                return i
            l+=1

        # base case
        return -1
