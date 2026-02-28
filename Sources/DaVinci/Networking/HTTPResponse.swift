import Foundation

internal struct HTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let data: Data
}
