impl Solution {
    pub fn is_palindrome(x: i32) -> bool {
        let x_str: String = x.to_string();
        let rev_x_str: String = x_str.chars().rev().collect();
        return x_str == rev_x_str;
    }
}
