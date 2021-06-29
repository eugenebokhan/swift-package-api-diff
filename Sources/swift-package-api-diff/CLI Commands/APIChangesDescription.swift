import ArgumentParser

extension SwiftPackageAPIDiff {

    struct APIChangesDescription: ParsableCommand {

        @OptionGroup()
        var options: Options

        func validate() throws {
            try SwiftPackageAPIDiff.validateOptions(self.options)
        }

        func run() throws {
            try print(SwiftPackageAPIDiff.comparePackages(options: self.options))
        }

        static var configuration = CommandConfiguration(abstract: "Get api changes description")
    }

}
