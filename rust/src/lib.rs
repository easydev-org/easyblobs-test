//! A real crate the toolchain must compile.

pub fn greet(name: &str) -> String {
    format!("hello {name}")
}

#[cfg(test)]
mod tests {
    #[test]
    fn greets() {
        assert_eq!(super::greet("easyblobs"), "hello easyblobs");
    }
}
