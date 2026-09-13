class Solution:
    def largestOverlap(self, img1: List[List[int]], img2: List[List[int]]) -> int:
        img1_pos = []   # all (x,y) in img1 where val = 1
        img2_pos = []   # all (x,y) in img2 where val = 1
        
        # O(n) pass over both images to log 1 positions
        for i, row in enumerate(img1):
            for j, col in enumerate(row):
                if col == 1:
                    img1_pos.append((i, j))
                

                if img2[i][j] == 1:
                    img2_pos.append((i, j))
        
        # print(img1_pos)
        # print(img2_pos)

        # A rotation is where a 1 in img1 changes position to match img2 
        # fomula = rotation = (p2[x] - p[x], p2[y] - p[y])
        # Eg. a 1 at (1,2) in img1 and a 1 at (2,2) in img 2
        # rotation is (2 - 1, 2 - 2) = (1, 0)
        # which with (0,0) being top right indicates a shift right on x-axis
        rotations = {}
        res = 0

        # Iterate over and find the rotation that macthes the most 1s from img1 
        # to 1s on img2, this rotation count indicates the largest overlap from one
        # rotation
        for p in img1_pos:
            for p2 in img2_pos:
                r = (p2[0] - p[0], p2[1] - p[1])
                if r in rotations:
                    c = rotations[r]
                    new = c + 1

                    if new > res:
                        res = new

                    rotations[r] = new
                else:
                    if res == 0:
                        res = 1
                    rotations[r] = 1

        return res

# More succinctly, and slightly more efficient (from leetcode)
from typing import List
from collections import Counter


class Solution:
    def largestOverlap(self, img1: List[List[int]], img2: List[List[int]]) -> int:
        n = len(img1) 
        a = [(i, j) for i in range(n) for j in range(n) if img1[i][j]]  # build all img1 1 positions
        b = [(i, j) for i in range(n) for j in range(n) if img2[i][j]]  # build all img2 1 positions

        # Counter abstraction counts all instances of the same rotation
        cnt = Counter((i - di, j - dj) for i, j in a for di, dj in b)
        return max(cnt.values()) if cnt else 0
