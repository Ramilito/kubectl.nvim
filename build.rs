use std::process::Command;
use std::env;
use std::path::PathBuf;

fn main() {
    let status = Command::new("go")
        .args(&["build", "-C", "go", "-o", "libkubedescribe.a", "-buildmode=c-archive"])
        .status()
        .expect("Failed to execute Go build");

    if !status.success() {
        panic!("Go build failed");
    }

    let manifest_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let lib_path = PathBuf::from(format!("{}/{}",&manifest_dir, "go"));
    
    println!("cargo:rustc-link-search=native={}", lib_path.display());
    println!("cargo:rustc-link-lib=static=kubedescribe");
}
