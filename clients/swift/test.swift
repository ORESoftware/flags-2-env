import Foundation

@main
struct Flags2EnvSmokeTest {
    static func main() throws {
        let suffix = {
            #if os(macOS)
            return "dylib"
            #else
            return "so"
            #endif
        }()

        let sdk = try Flags2Env(libraryPath: "../../build/libflags2env.\(suffix)")
        guard FileManager.default.changeCurrentDirectoryPath("../../tests/fixtures/nested/deeper") else {
            fputs("failed to change into fixture directory\n", stderr)
            exit(1)
        }
        let parsed = try sdk.parse(["app", "--debug=t", "--port", "8181"])

        if parsed["DEBUG"] != "true" || parsed["PORT"] != "8181" || parsed["COLOR"] != "true" {
            fputs("unexpected parsed map: \(parsed)\n", stderr)
            exit(1)
        }

        let explicit = try sdk.parse(["app", "--debug=f"], configPath: "../../.cli-flags.toml")
        if explicit["DEBUG"] != "false" || explicit["PORT"] != "3000" {
            fputs("unexpected explicit config map: \(explicit)\n", stderr)
            exit(1)
        }

        let combined = try sdk.apply(env: ["PORT": "env", "KEEP": "1"], argv: ["app", "--port", "8181"])
        if combined["PORT"] != "8181" || combined["KEEP"] != "1" || combined["COLOR"] != "true" {
            fputs("unexpected combined map: \(combined)\n", stderr)
            exit(1)
        }
    }
}
