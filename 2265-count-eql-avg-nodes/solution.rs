// Definition for a binary tree node.
// #[derive(Debug, PartialEq, Eq)]
// pub struct TreeNode {
//   pub val: i32,
//   pub left: Option<Rc<RefCell<TreeNode>>>,
//   pub right: Option<Rc<RefCell<TreeNode>>>,
// }
// 
// impl TreeNode {
//   #[inline]
//   pub fn new(val: i32) -> Self {
//     TreeNode {

//       val,

//       left: None,
//       right: None
//     }
//   }

// }

use std::rc::Rc;

use std::cell::RefCell;

impl Solution {
    pub fn helper(curr: Rc<RefCell<TreeNode>>) -> (i32, i32, i32) {
        let c_ref = curr.borrow();

        if c_ref.left.is_none() && c_ref.right.is_none() {
            return (1, 1, c_ref.val)
        }

        let mut t: i32 = 1;
        let mut n: i32 = 0;
        let mut s: i32 = c_ref.val;


        if let Some(node) = c_ref.left.as_ref() {
            let (tl, nl, sl) = Solution::helper(node.clone());
            t += tl;
            n += nl;
            s += sl;
        }

        if let Some(node) = c_ref.right.as_ref() {
            let (tr, nr, sr) = Solution::helper(node.clone());
            t += tr;
            n += nr;
            s += sr;
        }

        let avg: i32 = s / t;
        if avg == c_ref.val {

            n += 1;
        }
        (t, n, s)
    }

    pub fn average_of_subtree(root: Option<Rc<RefCell<TreeNode>>>) -> i32 {
        if let Some(r) = root {
            let (_, n, _) = Solution::helper(r);
            return n;
        }
        0
    }

}
