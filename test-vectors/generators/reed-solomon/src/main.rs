//! Генератор test-vectors/reed-solomon.json (см. docs/spec/test-vectors.md).
//!
//! Эталон — крейт reed-solomon-erasure 6.0.0 (поле GF(2^8), модуль galois_8).
//! Данные фрагментов детерминированы: генератор splitmix64 с зерном из
//! номера случая, поэтому повторный запуск даёт тот же файл.
//!
//! Запуск: cargo run --release > ../../reed-solomon.json

use reed_solomon_erasure::galois_8::ReedSolomon;

struct SplitMix64(u64);

impl SplitMix64 {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

fn main() {
    // (k, n, длина фрагмента, номера стираемых фрагментов для reconstruct)
    let cases: &[(usize, usize, usize, &[usize])] = &[
        (1, 2, 16, &[0]),
        (2, 3, 32, &[1]),
        (3, 5, 1, &[0, 4]),
        (4, 6, 64, &[0, 3]),
        (10, 16, 128, &[0, 2, 4, 6, 8, 15]),
        (10, 30, 64, &[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 21, 22, 23, 24, 25, 26, 27, 28]),
        (17, 21, 33, &[16, 17, 18, 19]),
        (32, 64, 16, &[5, 10, 15, 20, 25, 30, 33, 40]),
        (128, 256, 4, &[0, 127, 128, 255]),
    ];

    println!("{{");
    println!("  \"spec\": \"reed-solomon\",");
    println!("  \"specVersion\": 1,");
    println!("  \"generator\": \"test-vectors/generators/reed-solomon (reed-solomon-erasure 6.0.0, galois_8)\",");
    println!("  \"cases\": [");
    for (index, &(k, n, len, erased)) in cases.iter().enumerate() {
        let mut rng = SplitMix64(index as u64 + 1);
        let mut shards: Vec<Vec<u8>> = (0..n)
            .map(|i| {
                if i < k {
                    (0..len).map(|_| rng.next() as u8).collect()
                } else {
                    vec![0u8; len]
                }
            })
            .collect();
        let rs = ReedSolomon::new(k, n - k).unwrap();
        rs.encode(&mut shards).unwrap();

        // Проверка, что эталон восстанавливает стёртые фрагменты.
        let mut partial: Vec<Option<Vec<u8>>> = shards.iter().cloned().map(Some).collect();
        for &e in erased {
            partial[e] = None;
        }
        rs.reconstruct(&mut partial).unwrap();
        for (i, s) in partial.iter().enumerate() {
            assert_eq!(s.as_ref().unwrap(), &shards[i]);
        }

        let data: Vec<String> = shards[..k].iter().map(|s| format!("\"{}\"", hex(s))).collect();
        let parity: Vec<String> = shards[k..].iter().map(|s| format!("\"{}\"", hex(s))).collect();
        let erased: Vec<String> = erased.iter().map(|e| e.to_string()).collect();
        println!("    {{");
        println!("      \"name\": \"k{}_n{}_len{}\",", k, n, len);
        println!("      \"input\": {{");
        println!("        \"dataShards\": {},", k);
        println!("        \"totalShards\": {},", n);
        println!("        \"data\": [{}]", data.join(", "));
        println!("      }},");
        println!("      \"expected\": {{");
        println!("        \"parity\": [{}]", parity.join(", "));
        println!("      }},");
        println!("      \"reconstruct\": {{ \"erased\": [{}] }}", erased.join(", "));
        print!("    }}");
        println!("{}", if index + 1 < cases.len() { "," } else { "" });
    }
    println!("  ]");
    println!("}}");
}
