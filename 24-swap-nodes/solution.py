# Definition for singly-linked list.
# class ListNode:
#     def __init__(self, val=0, next=None):
#         self.val = val
#         self.next = next
class Solution:
    def swapPairs(self, head: Optional[ListNode]) -> Optional[ListNode]:
        if not head:
            return None
        
        if not head.next:
            return head
        
        prev = None
        temp = head

        r = head.next

        while temp and temp.next:
            left = temp
            right = temp.next 

            t2 = right.next
            right.next = left 
            left.next = t2 

            if prev:
                prev.next = right

            prev = left
            temp = t2 

        return r
