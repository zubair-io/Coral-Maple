import Foundation

public enum XMPError: Error, Sendable, Equatable {
    case malformedXML
    case missingFile(URL)
    case writeFailure(String)
    case concurrentWrite
}
