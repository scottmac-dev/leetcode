# Not very efficient but solid one shot
# Definition for singly-linked list.
# class ListNode:
#     def __init__(self, val=0, next=None):
#         self.val = val
#         self.next = next
class Solution:
    def mergeKLists(self, lists: list[ListNode | None]) -> ListNode | None:
        if not lists:
            return None
        if len(lists) == 1:
            return lists[0]
        
        ret = None
        cur = None
        while True:
            nn = None
            ni = -1
            for i in range(len(lists)):
                n = lists[i]
                if n:
                    if not nn:
                        nn = n
                        ni = i
                    elif nn and n.val < nn.val:
                        nn = n
                        ni = i
            if not nn:
                break
            
            lists[ni] = nn.next
            nn.next = None

            if not ret:
                ret = nn
                cur = nn
            else:
                cur.next = nn
                cur = cur.next
            
        return ret
        
