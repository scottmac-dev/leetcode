# Definition for singly-linked list.
# class ListNode:
#     def __init__(self, val=0, next=None):
#         self.val = val
#         self.next = next
class Solution:
    def reverseKGroup(self, head: ListNode | None, k: int) -> ListNode | None:

        if not head:
            return None

        ret = None
        prev_tail = None
        old_head = head

        while True:
            # kth node from the start of current group.
            kth = old_head


            for _ in range(k - 1):
                if not kth:
                    break
                kth = kth.next


            # not enough nodes remaining to reverse 
            if not kth:
                break

            # node after kth
            after = kth.next


            # reverse k nodes.
            prev = after 
            curr = old_head

            for _ in range(k):
                temp = curr.next
                curr.next = prev
                prev = curr
                curr = temp

            # connect previous group to reversed group
            if prev_tail:
                prev_tail.next = prev
            else:
                # first group becomes the new head to return 
                ret = prev

            # old head is now the tail.
            # eg. 1 (head) -> 2 -> 3 -> after 
            # 3 -> 2 -> 1 (tail) -> after
            prev_tail = old_head


            # move to next group.
            old_head = curr


        return ret






