import Foundation
import ArgumentParser
import Files

struct SwiftPackageAPIDiff: ParsableCommand {
    
    enum Error: Swift.Error {
        case optionsValidationFailed
    }
    
    struct Report {
        
        enum ChangesType: String {
            case breaking
            case minor
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
        
        var changesType: ChangesType {
            Self.map.values.allSatisfy { self[keyPath: $0].isEmpty } ? .minor : .breaking
        }

        init(reportFile: File, reversedReportFile: File) throws {
            try self.init(reportFile: reportFile)
            self.addedDeclarations = (try? Report(reportFile: reversedReportFile).removedDeclarations) ?? []
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
        
        private static let map: [String: WritableKeyPath<Report, [String]>] = [
            "/* Generic Signature Changes */": \.genericSignatureChanges,
            "/* RawRepresentable Changes */": \.rawRepresentableChanges,
            "/* Removed Decls */": \.removedDeclarations,
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
        var oldPackagePath: String
        
        @Option(name: .shortAndLong,
                help: "New Package Path.")
        var newPackagePath: String
        
        @Option(name: .shortAndLong,
                help: "Package Module Name.")
        var moduleName: String
        
        @Flag(name: .shortAndLong,
              help: "Print diagnostic messages.")
        var verbose: Bool = false
    }
    
    static func validateOptions(_ options: Options) throws {
        guard !options.moduleName.isEmpty,
              (try? Folder(path: options.oldPackagePath).containsFile(named: "Package.swift")) ?? false,
              (try? Folder(path: options.newPackagePath).containsFile(named: "Package.swift")) ?? false
        else { throw Error.optionsValidationFailed }
    }
    
    static func comparePackages(options: Options) throws -> Report {
        let binPath = #file.deletingLastPathComponent
                           .deletingLastPathComponent
                           .appendingPathComponent("Utils")
                           .appendingPathComponent("swift-macosx-x86_64")
                           .appendingPathComponent("bin")
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
        
        if options.verbose {
            print("Compiling old package ...")
        }
        
        Self.shell(
            """
            SWIFT_EXEC=\(compilerPath) \
            swift build \
            --package-path \(options.oldPackagePath) \
            --build-path \(oldBuildFolder.path)
            """
        )
        
        if options.verbose {
            print("Compiling new package ...")
        }
        
        Self.shell(
            """
            SWIFT_EXEC=\(compilerPath) \
            swift build \
            --package-path \(options.newPackagePath) \
            --build-path \(newBuildFolder.path)
            """
        )
        
        if options.verbose {
            print("Dumping old package module ...")
        }
        
        Self.shell(
            """
            \(apiDigesterPath) \
            --dump-sdk \
            -sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
            -module \(options.moduleName) \
            -I \(oldBuildFolder.path.appendingPathComponent("debug")) \
            -o \(oldModuleDumpPath) \
            2> /dev/null
            """
        )
        
        if options.verbose {
            print("Dumping new package module ...")
        }
        
        Self.shell(
            """
            \(apiDigesterPath) \
            --dump-sdk \
            -sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
            -module \(options.moduleName) \
            -I \(newBuildFolder.path.appendingPathComponent("debug")) \
            -o \(newModuleDumpPath) \
            2> /dev/null
            """
        )
        
        if options.verbose {
            print("Comparing module dumps ...")
        }
        
        Self.shell(
            """
            \(apiDigesterPath) \
            -diagnose-sdk \
            -sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
            --input-paths \(oldModuleDumpPath) \
            -input-paths \(newModuleDumpPath) \
            2>&1 > \(reportFile.path) 2>&1
            """
        )
        
        Self.shell(
            """
            \(apiDigesterPath) \
            -diagnose-sdk \
            -sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
            --input-paths \(newModuleDumpPath) \
            -input-paths \(oldModuleDumpPath) \
            2>&1 > \(reversedReportFile.path) 2>&1
            """
        )
        
        return try .init(reportFile: reportFile,
                         reversedReportFile: reversedReportFile)
    }

    static var configuration = CommandConfiguration(
        abstract: "A utility for autoversioning of Swift Packages.",
        subcommands: [APIChangesType.self, APIChangesDescription.self],
        defaultSubcommand: APIChangesType.self
    )
    
    @discardableResult
    private static func shell(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()

        task.standardOutput = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/bash"
        task.launch()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)!

        return output
    }
    
}
