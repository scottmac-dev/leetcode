# Not efficient enough, worst case O(n^2)
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
        return longest

# 2n approach, scan left -> right and right -> left to find longest
# efficient enough to submit but still bottom 20%
class Solution:
    def longestValidParentheses(self, s: str) -> int:
        longest = 0

        opens = 0
        closes = 0
        for c in s:
            if c == '(':
                opens += 1

            else:
                closes += 1
            print(opens, closes)
            if opens == closes:
                longest = max(longest, 2 * closes)
            elif closes > opens:
                opens = closes = 0

        opens = 0
        closes = 0
        for c in reversed(s):
            if c == '(':
                opens += 1

            else:
                closes += 1
            if opens == closes:
                longest = max(longest, 2 * opens)
            elif opens > closes:
                opens = closes = 0


        return longest

# Reasonably efficient O(n) stack approach
class Solution:
    def longestValidParentheses(self, s: str) -> int:
        stack = [-1] # bottom element is cutoff wall of longest valid substr
        longest = 0
        for i, c in enumerate(s):
            if c == '(':
                # stack open index
                stack.append(i)

            else:
                # pop stack, essentially matching to a open
                stack.pop()
                if not stack:
                    # new wall found, close had no matching open
                    stack.append(i)
                else:
                    # assess gap between bottom stack and macthed close
                    # if new longest update
                    longest = max(longest, i - stack[-1])
            #print(stack, longest)
        return longest

