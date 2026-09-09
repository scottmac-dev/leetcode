impl Solution {
    pub fn count_commas(n: i64) -> i64 {
        let mut a: i64 = 0;
        let mut t: i64 = 1000;

        while t <= n {
            a += n - t + 1;
            t *= 1000;
        }
        a

    }
}
