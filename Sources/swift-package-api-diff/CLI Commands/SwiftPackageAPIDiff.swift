import Foundation
import ArgumentParser
import Files
import TSCBasic

struct SwiftPackageAPIDiff: ParsableCommand {
    
    enum Error: Swift.Error {
        case optionsValidationFailed
        case nonZeroExit(code: Int32)
        case signalExit(signal: Int32)
    }
    
    struct Report: CustomStringConvertible {

        enum ChangesType: String {
            case breaking
            case minor
        }

        var changesType: ChangesType {
            Self.keyPaths.allSatisfy { self[keyPath: $0].isEmpty } ? .minor : .breaking
        }

        var description: String {
            Self.map
                .mapValues { self[keyPath: $0] }
                .filter { !$0.value.isEmpty }
                .reduce("") {
                $0 + $1.key + "\n" + $1.value.reduce("", { $0 + " - " + $1 + "\n" })
            }
        }
        
        private(set) var genericSignatureChanges: [String] = []
        private(set) var rawRepresentableChanges: [String] = []
        private(set) var removedDeclarations: [String] = []
        private(set) var addedDeclarations: [String] = []
        private(set) var movedDeclarations: [String] = []
        private(set) var renamedDeclarations: [String] = []
        private(set) var typeChanges: [String] = []
        private(set) var declAttributeChanges: [String] = []
        private(set) var fixedLayoutTypeChanges: [String] = []
        private(set) var protocolConformanceChanges: [String] = []
        private(set) var protocolRequirementChanges: [String] = []
        private(set) var classInheritanceChanges: [String] = []
        private(set) var otherChanges: [String] = []

        init(reportFile: File, reversedReportFile: File) throws {
            try self.init(reportFile: reportFile)
            let reversedReport = try Report(reportFile: reversedReportFile)
            self.addedDeclarations += reversedReport.removedDeclarations.map {
                $0.replacingOccurrences(of: "removed", with: "added")
            }
        }
        
        private init(reportFile: File) throws {
            let rawString = try String(contentsOf: reportFile.url,
                                       encoding: .utf8)
            let components = rawString.components(separatedBy: .newlines)
                                      .filter { !$0.isEmpty }
            
            var currentKeyPath: WritableKeyPath<Report, [String]>? = nil
            loop: for i in 0 ..< components.count {
                let line = components[i]
                if Self.map.keys.contains(line) {
                    currentKeyPath = Self.map[line]
                    continue loop
                }
                if let currentKeyPath = currentKeyPath {
                    self[keyPath: currentKeyPath].append(line)
                }
            }
        }

        private static let keyPaths: [KeyPath<Report, [String]>] = [
            \.genericSignatureChanges,
            \.rawRepresentableChanges,
            \.removedDeclarations,
            \.addedDeclarations,
            \.movedDeclarations,
            \.renamedDeclarations,
            \.typeChanges,
            \.declAttributeChanges,
            \.fixedLayoutTypeChanges,
            \.protocolConformanceChanges,
            \.protocolRequirementChanges,
            \.classInheritanceChanges,
            \.otherChanges
        ]
        
        private static let map: [String: WritableKeyPath<Report, [String]>] = [
            "/* Generic Signature Changes */": \.genericSignatureChanges,
            "/* RawRepresentable Changes */": \.rawRepresentableChanges,
            "/* Removed Decls */": \.removedDeclarations,
            "/* Added Decls */": \.addedDeclarations,
            "/* Moved Decls */": \.movedDeclarations,
            "/* Renamed Decls */": \.renamedDeclarations,
            "/* Type Changes */": \.typeChanges,
            "/* Decl Attribute changes */": \.declAttributeChanges,
            "/* Fixed-layout Type Changes */": \.fixedLayoutTypeChanges,
            "/* Protocol Conformance Change */": \.protocolConformanceChanges,
            "/* Protocol Requirement Change */": \.protocolRequirementChanges,
            "/* Class Inheritance Change */": \.classInheritanceChanges,
            "/* Others */": \.otherChanges,
        ]
    }

    struct Options: ParsableArguments {
        @Option(name: .shortAndLong,
                help: "Old Package Path.")
        var oldPackage: String
        
        @Option(name: .shortAndLong,
                help: "New Package Path.")
        var newPackage: String
        
        @Option(name: .shortAndLong,
                help: "Package Module Name.")
        var module: String

        @Option(name: .shortAndLong,
                help: "Xcode Application Path.")
        var xcodePath = "/Applications/Xcode-beta.app"
        
        @Flag(name: .shortAndLong,
              help: "Print diagnostic messages.")
        var verbose: Bool = false
    }
    
    static func validateOptions(_ options: Options) throws {
        guard !options.module.isEmpty,
              (try? Folder(path: options.oldPackage).containsFile(named: "Package.swift")) ?? false,
              (try? Folder(path: options.newPackage).containsFile(named: "Package.swift")) ?? false
        else { throw Error.optionsValidationFailed }
    }

    // TODO: add target sdk check
    static func comparePackages(options: Options) throws -> Report {
        let sdkPath = options.xcodePath.appendingPathComponent("Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/")
        let binPath = options.xcodePath.appendingPathComponent("Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/")
        let compilerPath = binPath.appendingPathComponent("swiftc")
        let apiDigesterPath = binPath.appendingPathComponent("swift-api-digester")
        
        let temporaryFolder = try Folder.temporary.createSubfolder(named: "swift_package_version")
        defer { try? temporaryFolder.delete() }
        let oldBuildFolder = try temporaryFolder.createSubfolder(named: "build_old")
        let newBuildFolder = try temporaryFolder.createSubfolder(named: "build_new")
        
        let oldModuleDumpPath = temporaryFolder.path.appendingPathComponent("old.json")
        let newModuleDumpPath = temporaryFolder.path.appendingPathComponent("new.json")
        
        let reportFile = try temporaryFolder.createFile(named: "old_vs_new_report.txt")
        let reversedReportFile = try temporaryFolder.createFile(named: "new_vs_old_report.txt")

        let stdoutClosure: TSCBasic.Process.OutputClosure = { bytes in
            if options.verbose,
               let stdout = String(bytes: bytes, encoding: .utf8) {
                print(stdout)
            }
        }
        
        if options.verbose {
            print("Compiling old package ...")
        }

        try Self.process(
            arguments: [
                "swift", "build",
                "--package-path", options.oldPackage,
                "--build-path", oldBuildFolder.path,
            ],
            environment: ["SWIFT_EXEC": compilerPath],
            stdout: stdoutClosure
        )
        
        if options.verbose {
            print("Compiling new package ...")
        }

        try Self.process(
            arguments: [
                "swift", "build",
                "--package-path", options.newPackage,
                "--build-path", newBuildFolder.path
            ],
            environment: ["SWIFT_EXEC": compilerPath],
            stdout: stdoutClosure
        )
        
        if options.verbose {
            print("Dumping old package module ...")
        }

        try Self.process(
            arguments: [
                apiDigesterPath,
                "--dump-sdk",
                "-sdk", sdkPath,
                "-module", options.module,
                "-I", oldBuildFolder.path.appendingPathComponent("debug"),
                "-o", oldModuleDumpPath
            ],
            stdout: stdoutClosure
        )
        
        if options.verbose {
            print("Dumping new package module ...")
        }

        try Self.process(
            arguments: [
                apiDigesterPath,
                "--dump-sdk",
                "-sdk", sdkPath,
                "-module", options.module,
                "-I", newBuildFolder.path.appendingPathComponent("debug"),
                "-o", newModuleDumpPath
            ],
            stdout: stdoutClosure
        )
        
        if options.verbose {
            print("Comparing module dumps ...")
        }

        var reportBuffer = [UInt8]()
        try Self.process(
            arguments: [
                apiDigesterPath,
                "-diagnose-sdk",
                "-sdk", sdkPath,
                "--input-paths", oldModuleDumpPath,
                "-input-paths", newModuleDumpPath
            ],
            stdout: stdoutClosure,
            stderr: { reportBuffer.append(contentsOf: $0) }
        )
        try Data(reportBuffer).write(to: reportFile.url)

        var reversedReportBuffer = [UInt8]()
        try Self.process(
            arguments: [
                apiDigesterPath,
                "-diagnose-sdk",
                "-sdk", sdkPath,
                "--input-paths", newModuleDumpPath,
                "-input-paths", oldModuleDumpPath
            ],
            stdout: stdoutClosure,
            stderr: { reversedReportBuffer.append(contentsOf: $0) }
        )
        try Data(reversedReportBuffer).write(to: reversedReportFile.url)
        
        return try .init(reportFile: reportFile,
                         reversedReportFile: reversedReportFile)
    }

    static var configuration = CommandConfiguration(
        abstract: "A utility for autoversioning of Swift Packages.",
        subcommands: [APIChangesType.self, APIChangesDescription.self],
        defaultSubcommand: APIChangesType.self
    )

    private static func process(arguments: [String],
                                environment: [String: String] = [:],
                                stdout: @escaping TSCBasic.Process.OutputClosure = { _ in },
                                stderr: @escaping TSCBasic.Process.OutputClosure = { _ in }) throws {
        let process = Process(arguments: arguments,
                              environment: ProcessEnv.vars.merging(environment) { (_, new) in new },
                              outputRedirection: .stream(stdout: stdout, stderr: stderr))

        try process.launch()
        let result = try process.waitUntilExit()

        switch result.exitStatus {
        case let .terminated(code: code):
            if code != .zero {
                throw Error.nonZeroExit(code: code)
            }
        case let .signalled(signal: signal):
            throw Error.signalExit(signal: signal)
        }
    }
    
}
