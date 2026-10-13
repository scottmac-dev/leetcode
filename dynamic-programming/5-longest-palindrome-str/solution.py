# inefficient brute force
class Solution:
    def longestPalindrome(self, s: str) -> str:
        if not s:
            return ""
        
        longest = ""
        
        for i in range(len(s)):
            for j in range(i, len(s)):
                if s[i] == s[j]:
                    # same index
                    if i == j:
                        if not longest:
                            longest = str(s[i])
                    # one apart, palindrome if matching next char
                    elif j - i == 1:
                        if s[j] == s[j - 1]:
                            if len(longest) < 2:
                                longest = str(s[i] + s[j])
                    # else multiple apart, resolve determine if substr is palindrome
                    else:
                        k = i + 1
                        l = j - 1

                        isP = True
                        while k <= l:
                            if s[k] == s[l]:
                                k += 1
                                l -= 1
                                continue
                            else:
                                isP = False
                                break
                        if isP:
                            p = s[i : j + 1]
                            if len(p) > len(longest):
                                longest = p
        #print(longest)
        return longest 

# DP approach, much more efficient
class Solution:
    def longestPalindrome(self, s: str) -> str:
        n = len(s)

        # Single char always palindrome
        if n < 2:
            return s
        
        # Represents [i_start][i_end] = true if palindrome
        dp = [[False] * n for _ in range(n)]
        
        start = 0
        max_len = 1

        # Every single character is a palindrome
        for i in range(n):
            dp[i][i] = True

        # Check substrings of increasing length
        for length in range(2, n + 1):

            for i in range(n - length + 1):
                j = i + length - 1  # end idx

                # current char matches end char
                if s[i] == s[j]:
                    # determine middle contents are palindrome
                    # length 2 requires match, eg aa, bb
                    # above length 2 requires match internal substr to be true
                    substr_is_p = dp[i + 1][j - 1]
                    if length == 2 or substr_is_p:
                        dp[i][j] = True

                        if length > max_len:
                            start = i
                            max_len = length
        # for p in dp:
        #     print(p)

        return s[start:start + max_len]

