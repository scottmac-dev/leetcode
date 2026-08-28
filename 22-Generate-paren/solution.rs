impl Solution {

    fn helper(
        res: &mut Vec<String>, 
        curr: String,  
        n:i32, 
        opens: i32, 
        closes: i32
    ) {
        if closes == n {
            res.push(curr);
            return;
        }

        if opens < n {
            let mut next = curr.clone();
            next.push('(');
            Self::helper(
                res,
                next,
                n, 
                opens + 1,
                closes,
            );
        }

        if closes < opens {
            let mut next = curr.clone();
            next.push(')');
            Self::helper(
                res,
                next,
                n, 
                opens,
                closes + 1,
            );
        }

    }
    pub fn generate_parenthesis(n: i32) -> Vec<String> {
        let mut res = Vec::new();

        Self::helper(
            &mut res,
            String::new(),
            n,
            0,
            0,
        );

        res
    }
}
