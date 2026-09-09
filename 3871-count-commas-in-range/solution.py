class Solution:
    def countCommas(self, n: int) -> int:
        answer = 0
        threshold = 1000

        # group into threshold ranges
        # 0 - 999 = 0
        # 1,000 - 999,999 = 1
        # 1,000,000 - 999,999,999 = 2

        # Each threshold increases by magnitude of 1000
        while threshold <= n:

            # Eg
            # n = 1,234,567, t = 1000, a = 0
            # a += 1,233,568    (counted once between 1,000 -> 1,234,567)
            # a += 1,134,568    (counted twice between 100,000 -> 1,234,567)
            # a += 234,568      (counted three times 1,000,000 -> 1,234,567)
            
            # a = 2,602,704 total commas between 1 -> 1,234,567 
            answer += n - threshold + 1
            threshold *= 1000

        return answer
