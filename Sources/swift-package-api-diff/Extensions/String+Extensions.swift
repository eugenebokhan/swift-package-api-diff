import Foundation

extension String {
    var pathExtension: String { (self as NSString).pathExtension }
    var deletingLastPathComponent: String { NSString(string: self).deletingLastPathComponent }
    func appendingPathComponent(_ str: String) -> String {
        return NSString(string: self).appendingPathComponent(str)
    }
}
