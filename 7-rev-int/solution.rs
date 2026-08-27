// Bad solution, violates i64 constraint
impl Solution {
    pub fn reverse(x: i32) -> i32 {

        let mut divisor: i32 = 1;
        let mut ret: i64 = 0;
        while x % divisor != x {
            divisor *= 10;
            let digit = ((x % divisor) / (divisor/10)) ;
            ret = ret * 10 + digit as i64;
        }


        if ret < i32::MIN as i64 {
            return 0
        }

        if ret > i32::MAX as i64 {
            return 0
        }

        ret as i32
    }
}

// Better
// only uses i32 
impl Solution {
    pub fn reverse(x: i32) -> i32 {
        let mut num = x;
        let mut ret = 0;

        while num != 0 {
            // get end digit
            let digit = num % 10;

            // div by 10
            num /= 10;

            // check overflow before ret * 10 + digit
            if ret > i32::MAX / 10
                || (ret == i32::MAX / 10 && digit > 7)
            {
                return 0;
            }

            if ret < i32::MIN / 10
                || (ret == i32::MIN / 10 && digit < -8)
            {
                return 0;
            }

            ret = ret * 10 + digit;
        }

        ret
    }
}
