impl Solution {
    pub fn str_str(haystack: String, needle: String) -> i32 {
        let mut len: usize = needle.len();

        if len > haystack.len() {
            return -1
        }

        for i in 0..haystack.len() {
            if i + len > haystack.len() {
                break
            }
            
            if haystack[i..i + len] == needle {
                return i as i32
            }
        }

        return -1
    }
}
