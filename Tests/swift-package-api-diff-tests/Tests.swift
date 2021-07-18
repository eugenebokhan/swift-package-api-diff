import XCTest
import TSCBasic
import Files

final class SwiftPackageAPIDiffTests: XCTestCase {

    enum Error: Swift.Error {
        case dataCreationfailed
        case folderCreationFailed
    }

    var temporaryFolder: Folder?

    override func setUpWithError() throws {
        let temporaryFolder = try Folder.temporary.createSubfolder(named: "swift_package_api_diff_tests")
        self.temporaryFolder = temporaryFolder

        let currentFile = try File(path: #file)
        guard let packagePath = currentFile.parent?.parent?.parent
        else { throw Error.folderCreationFailed }

        Self.shell("""
        cd \(packagePath.path);
        swift build -c release --disable-sandbox;
        cp .build/release/swift-package-api-diff \(temporaryFolder.path);
        """)
    }
    override func tearDownWithError() throws {
        try self.temporaryFolder?.delete()
    }

    func testMinor() throws {
        guard let temporaryFolder = self.temporaryFolder
        else { throw Error.folderCreationFailed }

        let packageName = "Package"
        let oldPackageName = "Old"
        let newPackageName = "New"

        let oldPackageFolder = try temporaryFolder.createSubfolder(named: oldPackageName)
        let newPackageFolder = try temporaryFolder.createSubfolder(named: newPackageName)
        let resultFile = try temporaryFolder.createFile(at: "result.txt")

        Self.shell("""
        cd \(oldPackageFolder.path);
        swift package init --name \(packageName);
        cd \(newPackageFolder.path);
        swift package init --name \(packageName)
        """)

        let newDeclaration = """

        public struct NewStruct {
            let newValue = Float.zero
        }
        """

        let modifiedFile = try File(path: newPackageFolder.url.appendingPathComponent("Sources/Package/Package.swift").path)
        var modifiedString = try String(contentsOf: modifiedFile.url)
        modifiedString += newDeclaration

        guard let modifiedStringData = modifiedString.data(using: .utf8)
        else { throw Error.dataCreationfailed }
        try modifiedStringData.write(to: modifiedFile.url)

        Self.shell("""
        \(temporaryFolder.path)/swift-package-api-diff -o \(oldPackageFolder.path) -n \(newPackageFolder.path) -m \(packageName) >> \(resultFile.path)
        """)

        let result = try String(contentsOfFile: resultFile.path)

        XCTAssertEqual(result, "minor\n")
    }

    func testBreaking() throws {
        guard let temporaryFolder = self.temporaryFolder
        else { throw Error.folderCreationFailed }

        let packageName = "Package"
        let oldPackageName = "Old"
        let newPackageName = "New"

        let oldPackageFolder = try temporaryFolder.createSubfolder(named: oldPackageName)
        let newPackageFolder = try temporaryFolder.createSubfolder(named: newPackageName)
        let resultFile = try temporaryFolder.createFile(at: "result.txt")

        Self.shell("""
        cd \(oldPackageFolder.path);
        swift package init --name \(packageName);
        cd \(newPackageFolder.path);
        swift package init --name \(packageName)
        """)

        let modifiedFile = try File(path: newPackageFolder.url.appendingPathComponent("Sources/Package/Package.swift").path)
        let modifiedString = "import Foundation"

        guard let modifiedStringData = modifiedString.data(using: .utf8)
        else { throw Error.dataCreationfailed }
        try modifiedStringData.write(to: modifiedFile.url)

        let currentFile = try File(path: #file)
        guard let packagePath = currentFile.parent?.parent?.parent
        else { throw Error.folderCreationFailed }

        Self.shell("""
        cd \(packagePath.path);
        swift build -c release --disable-sandbox;
        cp .build/release/swift-package-api-diff \(temporaryFolder.path);
        """)
        Self.shell("""
        \(temporaryFolder.path)/swift-package-api-diff -o \(oldPackageFolder.path) -n \(newPackageFolder.path) -m \(packageName) >> \(resultFile.path)
        """)

        let result = try String(contentsOfFile: resultFile.path)

        XCTAssertEqual(result, "breaking\n")
    }

    private static func shell(_ command: String) {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/bash"
        task.launch()
        task.waitUntilExit()
    }
}
