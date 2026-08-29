impl Solution {
    pub fn remove_duplicates(nums: &mut Vec<i32>) -> i32 {
        let mut k: usize = 1;
        for i in (1..nums.len()) {
            if nums[i] != nums[i - 1]{
                nums[k] = nums[i];
                k += 1;
            }
        }

        return k as i32; 
    }
}
