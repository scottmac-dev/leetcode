// Definition for singly-linked list.
// #[derive(PartialEq, Eq, Clone, Debug)]
// pub struct ListNode {
//   pub val: i32,
//   pub next: Option<Box<ListNode>>
// }
// 
// impl ListNode {
//   #[inline]
//   fn new(val: i32) -> Self {
//     ListNode {
//       next: None,
//       val
//     }
//   }
// }
impl Solution {
    pub fn remove_nth_from_end(
        head: Option<Box<ListNode>>, 
        n: i32) -> Option<Box<ListNode>> 
    {
        let mut head = head;

        let mut l_len: i32 = 0;
        let mut current = head.as_ref();    // dont assume ownership


        while let Some(node) = current {
            l_len += 1;
            current = node.next.as_ref();
        } 

        if l_len <= 1 {
            return None
        }

        let r_pos = l_len - n;


        if r_pos == 0 {
            return head.unwrap().next
        }

        let mut current = head.as_mut().unwrap();

        for _ in 1..r_pos {
            current = current.next.as_mut().unwrap();
        }


        if let Some(mut node) = current.next.take() {
            current.next = node.next.take();
        }

        head
    }
}
