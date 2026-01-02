use std::env;
use std::path::PathBuf;

fn main() {
    let _ = std::fs::remove_file("target/release/version");
    let manifest_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let lib_path = PathBuf::from(format!("{}/{}", &manifest_dir, "../go"));
    let static_lib = lib_path.join("libkubectl_go.a");

    println!("cargo:rerun-if-changed={}", static_lib.display());
    println!("cargo:rustc-link-search=native={}", lib_path.display());
    println!("cargo:rustc-link-lib=static=kubectl_go");

    // On macOS, Go's CGO net package uses the system resolver (libresolv).
    // We must link it explicitly to satisfy symbols like res_9_nclose.
    #[cfg(target_os = "macos")]
    println!("cargo:rustc-link-lib=dylib=resolv");
}
