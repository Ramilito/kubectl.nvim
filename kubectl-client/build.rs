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

    emit_k8s_client_version();
}

fn emit_k8s_client_version() {
    println!("cargo:rerun-if-env-changed=K8S_OPENAPI_ENABLED_VERSION");

    let encoded: u32 = env::vars_os()
        .find_map(|(key, value)| {
            let key = key.into_string().ok()?;
            if key.starts_with("DEP_K8S_OPENAPI_") && key.ends_with("_VERSION") {
                value.into_string().ok()
            } else {
                None
            }
        })
        .expect("DEP_K8S_OPENAPI_*_VERSION must have been set by k8s-openapi")
        .parse()
        .expect("DEP_K8S_OPENAPI_*_VERSION is malformed");

    println!("cargo:rustc-env=K8S_CLIENT_MAJOR={}", (encoded >> 16) & 0xff);
    println!("cargo:rustc-env=K8S_CLIENT_MINOR={}", (encoded >> 8) & 0xff);
}
