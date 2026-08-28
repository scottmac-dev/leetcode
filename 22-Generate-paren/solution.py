# When have I found a complete answer? 
#   when closed = n 
# When am I allowed to add (? 
#   when opens < n
# When am I allowed to add )? 
#   when closed < n and closed < opens
# What state do I pass into the next recursive call?
#  current

# ( -> (( -> ((( -> ((() -> (((()) -> ((()))
#   -> (() -> (()( 

# Original recursive method
class Solution:
    def generate(self, res: set, curr: str,  n: int, opens: int, closes: int):
        if n == closes:
            res.add(curr)
            return

        if opens < n:
            next_str = curr + "("
            o = opens + 1

            self.generate(res, next_str, n, o, closes)
        if closes < opens:
            next_str = curr + ")"
            c = closes + 1
            self.generate(res, next_str, n, opens, c)
        return

    def generateParenthesis(self, n: int) -> List[str]:
        res = set()
        self.generate(res, "", n, 0, 0)

        return list(res)


# More efficient solution 
class Solution:
    def generateParenthesis(self, n: int) -> List[str]:
        res = []
        def helper(cur, ln, rn):
            if ln == n and rn == n:
                res.append("".join(cur))
                return
            if ln == n:
                res.append("".join(cur+[")"]*(n-rn)))

                return
            helper(cur+["("], ln+1, rn)
            if rn != ln:
                helper(cur+[")"], ln, rn+1)
        helper([], 0, 0)
        return res


