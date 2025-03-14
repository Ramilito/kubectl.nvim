use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    let _ = std::fs::remove_file("target/release/version");
    let status = Command::new("go")
        .args(&[
            "build",
            "-C",
            "go",        // change to the "go" directory
            "-trimpath", // remove file system paths from the build
            "-ldflags",
            "-s -w", // strip debug info and symbol tables
            "-o",
            "libkubedescribe.so",
            "-buildmode=c-shared",
        ])
        .status()
        .expect("Failed to execute Go build");

    if !status.success() {
        panic!("Go build failed");
    }

    let manifest_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let lib_path = PathBuf::from(format!("{}/{}", &manifest_dir, "go"));

    println!("cargo:rustc-link-search=native={}", lib_path.display());
    // println!("cargo:rustc-link-lib=static=kubedescribe");
    println!("cargo:rustc-link-lib=dylib=kubedescribe");

    println!("cargo:rustc-link-arg=-Wl,-rpath,{}", lib_path.display());
}
