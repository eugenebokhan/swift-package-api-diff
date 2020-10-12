import ArgumentParser

extension SwiftPackageAPIDiff {

    struct APIChangesType: ParsableCommand {

        @OptionGroup()
        var options: Options

        func validate() throws {
            try SwiftPackageAPIDiff.validateOptions(self.options)
        }

        func run() throws {
            try print(SwiftPackageAPIDiff.comparePackages(options: self.options).changesType.rawValue)
        }

        static var configuration = CommandConfiguration(abstract: "Get majority of api changes: breaking or non-breaking")
    }

}
