// Original
impl SolutionBad {
    pub fn my_atoi(s: String) -> i32 {
        let trimmed = s.trim();
        let mut first: bool = true;
        let stripped: String = trimmed
            .chars()
            .take_while(|c| {
                if c.is_numeric() {
                    first = false;
                    true
                } else if (*c == '-' || *c == '+') && first {
                    first = false;
                    true
                } else {
                    false
                }
            })
            .filter(|c| {
                if *c == '0' {
                    false
                } else {
                    true
                }
            })
            .collect();
        println!("{}", stripped);
        let n: Result<i32,_> = stripped.parse();
        match n {
            Ok(num) => return num,
            Err(e) => println!("{}", e),
        }
        return 0
    }
}

// Manual build digit from string logic
// Iter over single chars 
// Skip non numeric 
// Convert digit using 'as'
// res = res * 10 + digit
//
// So for 42543
// res = 4
// res = 40 + 2
// res = 420 + 5
// res = 4250 + 4
// res = 42540 + 3
//
// Cap at i32:MIN || i32::MAX
//
// Need to store res as i64 incase of overflow before capping

// Better
impl Solution {
    pub fn my_atoi(s: String) -> i32 {
        let mut chars = s.chars().peekable();   // iter
        
        // SKip white spaces 
        while let Some(&c) = chars.peek() {
            if c == ' ' {
                chars.next();
            } else {
                break;
            }
        }

        // Determine sign
        let mut sign: i64 = 1;

        if let Some(&c) = chars.peek() {
            if c == '-' {
                sign = -1;
                chars.next();
            } else if c == '+' {
                chars.next();
            }
        }

        // Manual build of number
        let mut result: i64 = 0;

        while let Some(&c) = chars.peek() {
            if !c.is_ascii_digit() {
                break;
            }

            let digit = (c as i64) - ('0' as i64);
            result = result * 10 + digit;

            // prevent overflow 
            if result * sign < i32::MIN as i64 {
                return i32::MIN
            }

            if result * sign > i32::MAX as i64 {
                return i32::MAX
            }
            chars.next()
        }

        (result * sign) as i32
    }
}
