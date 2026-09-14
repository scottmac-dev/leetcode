class Solution:
    def isRectangleOverlap(self, rec1: List[int], rec2: List[int]) -> bool:
        r1bl = (rec1[0], rec1[1]) # r1 bottom left
        r1tr = (rec1[2], rec1[3]) # r1 top right

        r2bl = (rec2[0], rec2[1]) # r2 bottom left
        r2tr = (rec2[2], rec2[3]) # r2 top right

        # For an overlap in rectangle area to occur the following must be True
        #   - r2s top right (x, y) position is greater than r1s bottom left (x, y) position
        #   - r1s top bottom left (x, y) position is less than r2s top right (x, y) position
        if r2tr[0] > r1bl[0] and r2tr[1] > r1bl[1] and r2bl[0] < r1tr[0] and r2bl[1] < r1tr[1]:
            return True


        return False
