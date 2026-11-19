use std::hint::black_box;
use std::io::{self, BufRead, Write};
use std::time::Instant;

fn main() {
    let args: Vec<_> = std::env::args().collect();
    let source = std::fs::read_to_string(&args[2]).unwrap();
    let parse = || source.parse::<toml::Table>().unwrap();
    let mut last = parse();
    if args[1] == "verify" {
        println!("{}", serde_json::to_string(&last).unwrap());
        return;
    }
    for line in io::stdin().lock().lines() {
        let count: usize = line.unwrap().parse().unwrap();
        let start = Instant::now();
        for _ in 0..count {
            last = black_box(parse());
        }
        let elapsed = start.elapsed().as_nanos();
        println!("{} {}", elapsed, last.len());
        io::stdout().flush().unwrap();
    }
}
