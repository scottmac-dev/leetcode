enum Token {
    I,
    V,
    X,
    L,
    C,
    D,
    M,
    Error,
}

impl Token {
    fn from_char(c: &char) -> Token {
        match c {
            'I' => Token::I,
            'V' => Token::V,
            'X' => Token::X,
            'L' => Token::L,
            'C' => Token::C,
            'D' => Token::D,
            'M' => Token::M,
            _ => Token::Error,
        }
    }

    fn to_i32(&self) -> i32 {
        match self {
            Token::I => 1,
            Token::V => 5,
            Token::X => 10,
            Token::L => 50,
            Token::C => 100,
            Token::D => 500,
            Token::M => 1000,
            Token::Error => 0,
        }
    }
}

impl Solution {
    pub fn roman_to_int(s: String) -> i32 {
        let mut res: i32 = 0;
        let mut chars = s.chars().peekable();

        while let Some(c) = chars.next() {
            let rt: Token = Token::from_char(&c);

            // Check error in real case, not needed for given constraints

            if let Some(&next) = chars.peek() {
                let nt: Token = Token::from_char(&next);
                match rt {
                    Token::I => {
                        match nt {
                            Token::V => {
                                res += 4;
                                chars.next();
                                continue
                            },
                            Token::X => {
                                res += 9;
                                chars.next();
                                continue
                            },
                            _ => {},
                        }
                    },
                    Token::X => {
                        match nt {
                            Token::L => {
                                res += 40;
                                chars.next();
                                continue
                            },
                            Token::C => {
                                res += 90;
                                chars.next();
                                continue
                            },
                            _ => {},
                        }
                    },
                    Token::C => {
                        match nt {
                            Token::D => {
                                res += 400;
                                chars.next();
                                continue
                            },
                            Token::M => {
                                res += 900;
                                chars.next();
                                continue
                            },
                            _ => {},
                        }
                    },
                    _ => {},
                }
            }
            res += rt.to_i32();
        }
        res
    }
}

