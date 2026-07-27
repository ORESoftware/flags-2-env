fn main() {
    println!("cargo:rerun-if-changed=native/parser.c");
    println!("cargo:rerun-if-changed=native/parser.h");

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
