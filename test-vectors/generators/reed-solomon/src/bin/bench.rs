//! Опорный замер для 0.5.3: скорость reed-solomon-erasure (чистый Rust,
//! без SIMD) на сегменте 16 МиБ в одном потоке. Запуск:
//! cargo run --release --bin bench

use reed_solomon_erasure::galois_8::ReedSolomon;
use std::time::Instant;

fn main() {
    const SEGMENT: usize = 16 * 1024 * 1024;
    println!("| k | n | Кодирование, МБ/с | Восстановление, МБ/с |");
    println!("|---|---|---|---|");
    for &(k, n) in &[(10usize, 16usize), (10, 20), (10, 30), (20, 40), (32, 64)] {
        let size = (SEGMENT + k - 1) / k;
        let mut shards: Vec<Vec<u8>> = (0..n)
            .map(|i| vec![if i < k { (i * 37 + 1) as u8 } else { 0 }; size])
            .collect();
        let rs = ReedSolomon::new(k, n - k).unwrap();
        rs.encode(&mut shards).unwrap();
        let start = Instant::now();
        let mut runs = 0;
        while start.elapsed().as_millis() < 2000 {
            rs.encode(&mut shards).unwrap();
            runs += 1;
        }
        let enc = runs as f64 * SEGMENT as f64 / 1e6 / start.elapsed().as_secs_f64();

        let lost = k.min(n - k);
        let mut total = 0f64;
        let mut runs = 0;
        while total < 2.0 {
            let mut partial: Vec<Option<Vec<u8>>> = shards.iter().cloned().map(Some).collect();
            for i in 0..lost {
                partial[i] = None;
            }
            let t = Instant::now();
            rs.reconstruct(&mut partial).unwrap();
            total += t.elapsed().as_secs_f64();
            runs += 1;
        }
        let dec = runs as f64 * SEGMENT as f64 / 1e6 / total;
        println!("| {} | {} | {:.1} | {:.1} |", k, n, enc, dec);
    }
}
