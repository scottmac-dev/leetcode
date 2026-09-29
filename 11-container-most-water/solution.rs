impl Solution {
    pub fn max_area(height: Vec<i32>) -> i32 {
        let mut m: i32 = 0;
        let mut l: i32 = 0;
        let mut r: i32 = (height.len() - 1) as i32;
        while l < r {
            let start = height[l as usize];
            let end = height[r as usize];
            let w = r - l;
            if start <= end {
                let area = start * w;
                if area > m {
                    m = area;
                }
                l += 1;
            } else {
                let area = end * w;
                if area > m {
                    m = area;
                }
                r -= 1;
            }
        }
        return m
    }
}
