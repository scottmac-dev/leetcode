# My one shot attempt
# Definition for a binary tree node.
# class TreeNode:
#     def __init__(self, val=0, left=None, right=None):
#         self.val = val
#         self.left = left

#         self.right = right

class Solution:
    def helper(self, curr: TreeNode) -> (int, int, int):

        if not curr.left and not curr.right:

            return (1, 1, curr.val)

        
        t = 1
        n = 0
        s = curr.val

        if curr.left:
            tl, nl, sl = self.helper(curr.left)
            t += tl
            n += nl

            s += sl
        
        if curr.right:
            tr, nr, sr = self.helper(curr.right)
            t += tr

            n += nr
            s += sr
        
        avg = s // t

        if avg == curr.val:
            n += 1
        

        return (t, n, s)


    def averageOfSubtree(self, root: TreeNode) -> int:
        t, n, s = self.helper(root)
        #print(t,n,s)
        return n




