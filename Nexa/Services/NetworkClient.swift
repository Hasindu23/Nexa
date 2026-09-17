import Foundation

enum NetworkClient {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
    static func checked(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NexaError.message(code == 401 ? "The API key was not accepted." : code == 429 ? "The provider’s usage limit was reached. Try again later." : "The provider returned an error (\(code)).")
        }
    }
}
