class Solution:

    def helper(self, combos: set, options: list, cur: str):
        if len(cur) == len(options):

            combos.add(cur)

            return
        vals = options[len(cur)]
        for v in vals:
            next_cur = cur + v
            self.helper(combos, options, next_cur)
        
    def letterCombinations(self, digits: str) -> List[str]:
        mapping = {
            "2": ["a", "b", "c"],
            "3": ["d", "e", "f"],
            "4": ["g", "h", "i"],
            "5": ["j", "k", "l"],
            "6": ["m", "n", "o"],
            "7": ["p", "q", "r", "s"],
            "8": ["t", "u", "v"],

            "9": ["w", "x", "y", "z"]
        }


        if len(digits) == 0:
            return []
        if len(digits) == 1:
            return mapping[digits]

        options = []
        for i, d in enumerate(digits):
            vals = mapping[d]
            options.append(vals)
        #print(options)

        combos = set()
        self.helper(combos, options, "")

        #print(combos)

        return list(combos)

        
