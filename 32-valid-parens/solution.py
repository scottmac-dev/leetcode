# Not efficient enough
class Solution:
    def longestValidParentheses(self, s: str) -> int:
        longest = 0
        for i, c in enumerate(s):
            if c == '(':
                opens = 1
                closes = 0
                run = 0
                pos = i + 1

                while opens >= closes and pos <= len(s) - 1:
                    n = s[pos]
                    if n == '(':
                        opens += 1

                    else:
                        closes += 1
                    if opens == closes:
                        run = opens * 2
                    if run > longest:
                        longest = run
                    pos += 1
                if closes == 0:
                    return 0
        return longest
