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
        FileManager.default.changeCurrentDirectoryPath("../../tests/fixtures/nested/deeper")
        let parsed = try sdk.parse(["app", "--debug=t", "--port", "8181"])

        if parsed["DEBUG"] != "true" || parsed["PORT"] != "8181" || parsed["COLOR"] != "true" {
            fputs("unexpected parsed map: \(parsed)\n", stderr)
            exit(1)
        }
    }
}
