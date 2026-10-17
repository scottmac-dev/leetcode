# Original
class Solution(object):
    def isPalindrome(self, x):
        """
        :type x: int
        :rtype: bool
        """
        string = str(x)
        length = len(string)
        mid = length / 2
        
        i = 0
        while (i <= mid):
            head = string[i]
            tail = string[length - 1 - i]

# Smarter
class Solution2(object):
    def isPalindrome(self, x):
        """
        :type x: int
        :rtype: bool
        """
        xstr = str(x)
        rxstr = xstr[::-1]

        if xstr == rxstr:
            return True
        else :
            return False
