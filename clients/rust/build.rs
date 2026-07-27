fn main() {
    println!("cargo:rerun-if-changed=native/parser.c");
    println!("cargo:rerun-if-changed=native/parser.h");

    if std::env::var("CARGO_CFG_WINDOWS").is_ok() {
        // parser.c uses CommandLineToArgvW to obtain the real wide-character
        // process command line. That API is exported by Shell32.dll.
        println!("cargo:rustc-link-lib=shell32");
    }

    let mut build = cc::Build::new();
    build
        .file("native/parser.c")
        .include("native")
        .warnings(true)
        .flag_if_supported("-std=c99")
        .flag_if_supported("-Wall")
        .flag_if_supported("-Wextra")
        .compile("flags2env_bundled");
}
