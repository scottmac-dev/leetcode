# Definition for singly-linked list.
# class ListNode:
#     def __init__(self, val=0, next=None):
#         self.val = val
#         self.next = next
class Solution:
    def removeNthFromEnd(self, head: Optional[ListNode], n: int) -> Optional[ListNode]:
        list_len = 0
        temp = head
        while temp != None:
            temp = temp.next 
            list_len += 1

        if list_len <= 1:
            return None

        r_pos = list_len - n

        if r_pos == 0:
            return head.next

        c_pos = 1
        temp = head
        
        while c_pos < r_pos:
            temp = temp.next 
            c_pos += 1

        if temp.next != None:
            temp.next = temp.next.next 

        return head
        
