use std::env;
use std::path::PathBuf;

fn main() {
    let _ = std::fs::remove_file("target/release/version");
    let manifest_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let lib_path = PathBuf::from(format!("{}/{}", &manifest_dir, "go"));
    let static_lib = lib_path.join("libkubectl_go.a");

    println!("cargo:rerun-if-changed={}", static_lib.display());
    println!("cargo:rustc-link-search=native={}", lib_path.display());
    println!("cargo:rustc-link-lib=static=kubectl_go");
    // println!("cargo:rustc-link-lib=dylib=kubedescribe");
    // println!("cargo:rustc-link-arg=-Wl,-rpath,{}", lib_path.display());
}
