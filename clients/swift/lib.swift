import Foundation

public typealias F2EParseFn = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
public typealias F2EParseProcessFn = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
public typealias F2EFreeFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

public final class Flags2Env {
    private let handle: UnsafeMutableRawPointer
    private let parseFn: F2EParseFn
    private let parseProcessFn: F2EParseProcessFn
    private let freeFn: F2EFreeFn

    public init(libraryPath: String = Flags2Env.defaultLibraryPath()) throws {
        guard let handle = dlopen(libraryPath, RTLD_NOW | RTLD_LOCAL) else {
            throw NSError(domain: "Flags2Env", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: dlerror())])
        }
        guard let parseSymbol = dlsym(handle, "f2e_parse_json_argv_from_file"),
              let parseProcessSymbol = dlsym(handle, "f2e_parse_process_from_file"),
              let freeSymbol = dlsym(handle, "f2e_free") else {
            dlclose(handle)
            throw NSError(domain: "Flags2Env", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing flags2env symbols"])
        }
        self.handle = handle
        self.parseFn = unsafeBitCast(parseSymbol, to: F2EParseFn.self)
        self.parseProcessFn = unsafeBitCast(parseProcessSymbol, to: F2EParseProcessFn.self)
        self.freeFn = unsafeBitCast(freeSymbol, to: F2EFreeFn.self)
    }

    deinit {
        dlclose(handle)
    }

    public func parse(_ argv: [String], configPath: String = "\(FileManager.default.currentDirectoryPath)/.cli-flags.toml") throws -> [String: String] {
        let argvData = try JSONSerialization.data(withJSONObject: argv, options: [])
        let argvJSON = String(data: argvData, encoding: .utf8)!
        guard let result = configPath.withCString({ configPtr in
            argvJSON.withCString { argvPtr in
                parseFn(configPtr, argvPtr)
            }
        }) else {
            return [:]
        }
        defer { freeFn(result) }

        let data = String(cString: result).data(using: .utf8)!
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: String]
        return decoded ?? [:]
    }

    public func parseProcess(configPath: String = "\(FileManager.default.currentDirectoryPath)/.cli-flags.toml") throws -> [String: String] {
        guard let result = configPath.withCString({ configPtr in
            parseProcessFn(configPtr)
        }) else {
            return [:]
        }
        defer { freeFn(result) }

        let data = String(cString: result).data(using: .utf8)!
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: String]
        return decoded ?? [:]
    }

    public func apply(env: [String: String] = ProcessInfo.processInfo.environment, argv: [String] = CommandLine.arguments) throws -> [String: String] {
        return env.merging(try parse(argv)) { _, cli in cli }
    }

    public func applyProcess(env: [String: String] = ProcessInfo.processInfo.environment) throws -> [String: String] {
        return env.merging(try parseProcess()) { _, cli in cli }
    }

    private static func defaultLibraryPath() -> String {
        #if os(macOS)
        return "libflags2env.dylib"
        #elseif os(Windows)
        return "flags2env.dll"
        #else
        return "libflags2env.so"
        #endif
    }
}
