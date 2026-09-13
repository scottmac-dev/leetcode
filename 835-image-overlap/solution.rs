use std::collections::HashMap;

impl Solution {
    pub fn largest_overlap(img1: Vec<Vec<i32>>, img2: Vec<Vec<i32>>) -> i32 {
        let n = img1.len();
        let mut a: Vec<(usize, usize)> = Vec::new();
        let mut b: Vec<(usize, usize)> = Vec::new();

        for i in 0..n {
            for j in 0..n {
                if img1[i][j] == 1 {
                    a.push((i,j));
                }
                if img2[i][j] == 1 {
                    b.push((i,j));
                }                
            }

        }


        let mut map: HashMap<(usize, usize), i32> = HashMap::new();
        let mut res: i32 = 0;
        for (ai, aj) in &a {
            for (bi, bj) in &b {
                let r = (bi - ai, bj - aj);
                if map.contains_key(&r) {
                    let prev = map[&r];
                    let new = prev + 1;
                    if new > res {
                        res = new;
                    }
                    map.insert(r, new);
                } else {
                    if res == 0 {

                        res = 1;
                    }
                    map.insert(r, 1);
                }
            }
        }
        return res
    }
}
