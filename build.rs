use std::env;

fn main() {
    // This tells Cargo to add the project root (CARGO_MANIFEST_DIR) to the native library search path.
    let manifest_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    println!("cargo:rustc-link-search=native={}", manifest_dir);
}
