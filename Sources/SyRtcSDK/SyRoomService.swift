//
//  SyRoomService.swift
//  SyRtcSDK
//
//  Room management and token fetching via HTTP calls to the backend API.
//

import Foundation

// MARK: - SyRoomInfo

/// Room information model returned by the room API.
public struct SyRoomInfo {

    /// Unique channel identifier.
    public let channelId: String

    /// Host user ID, if any.
    public let hostUid: String?

    /// Room status (e.g., "active", "closed").
    public let status: String

    /// Current number of users online.
    public let onlineCount: Int

    /// Maximum allowed seats in the room.
    public let maxSeats: Int

    /// Room creation timestamp.
    public let createTime: Date?

    /// Creates a `SyRoomInfo` from a dictionary (e.g., JSON response).
    /// - Parameter dict: Dictionary with keys: channelId, hostUid (optional), status, onlineCount, maxSeats, createTime (optional).
    public init?(from dict: [String: Any]) {
        guard let channelId = dict["channelId"] as? String,
              let status = dict["status"] as? String else {
            return nil
        }
        self.channelId = channelId
        self.hostUid = dict["hostUid"] as? String
        self.status = status
        self.onlineCount = dict["onlineCount"] as? Int ?? 0
        self.maxSeats = dict["maxSeats"] as? Int ?? 0

        if let createTimeValue = dict["createTime"] {
            if let timestamp = createTimeValue as? TimeInterval {
                self.createTime = Date(timeIntervalSince1970: timestamp / 1000)
            } else if let timestamp = createTimeValue as? Int {
                self.createTime = Date(timeIntervalSince1970: Double(timestamp) / 1000)
            } else {
                self.createTime = nil
            }
        } else {
            self.createTime = nil
        }
    }
}

// MARK: - SyRoomService

/// Companion service to the RTC engine for room management and token fetching.
public final class SyRoomService {

    private let apiBaseUrl: String
    private let appId: String
    private var authToken: String?
    private var appSecret: String?

    private let session: URLSession
    private let decoder = JSONDecoder()

    /// Creates a room service with the given API base URL and app ID.
    /// - Parameters:
    ///   - apiBaseUrl: Base URL for the room API (e.g., "https://api.example.com").
    ///   - appId: Application identifier.
    public init(apiBaseUrl: String, appId: String) {
        self.apiBaseUrl = apiBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.appId = appId
        self.session = URLSession.shared
    }

    /// Sets the JWT auth token for authenticated API requests.
    /// - Parameter token: JWT string.
    public func setAuthToken(_ token: String) {
        authToken = token
    }

    /// Sets the app secret for demo or server-side signing (use with caution).
    /// - Parameter secret: App secret string.
    public func setAppSecret(_ secret: String) {
        appSecret = secret
    }

    // MARK: - Private Helpers

    private func url(path: String, queryItems: [URLQueryItem]? = nil) -> URL? {
        var components = URLComponents(string: "\(apiBaseUrl)/\(path)")
        components?.queryItems = queryItems
        return components?.url
    }

    private func request(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        queryItems: [URLQueryItem]? = nil
    ) -> URLRequest? {
        guard let url = url(path: path, queryItems: queryItems) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(appId, forHTTPHeaderField: "X-App-Id")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let secret = appSecret {
            request.setValue(secret, forHTTPHeaderField: "X-App-Secret")
        }

        if let body = body, let data = try? JSONSerialization.data(withJSONObject: body) {
            request.httpBody = data
        }
        return request
    }

    private func perform<T>(
        _ request: URLRequest?,
        parse: @escaping (Data) throws -> T,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        guard let request = request else {
            DispatchQueue.main.async {
                completion(.failure(SyRoomServiceError.invalidRequest))
            }
            return
        }

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(SyRoomServiceError.noData)) }
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                DispatchQueue.main.async {
                    completion(.failure(SyRoomServiceError.httpError(statusCode: http.statusCode, message: message)))
                }
                return
            }
            do {
                let result = try parse(data)
                DispatchQueue.main.async { completion(.success(result)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    // MARK: - Public API

    /// Fetches the list of active rooms.
    /// - Parameter completion: Called on the main queue with the result.
    public func getRoomList(completion: @escaping (Result<[SyRoomInfo], Error>) -> Void) {
        let req = request(path: "rooms")
        perform(req) { (data: Data) throws -> [SyRoomInfo] in
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let list = json?["rooms"] as? [[String: Any]] ?? json?["data"] as? [[String: Any]] ?? (json as? [[String: Any]])
            let rooms = (list ?? []).compactMap { SyRoomInfo(from: $0) }
            return rooms
        } completion: { completion($0) }
    }

    /// Creates a new room with the given channel ID.
    /// - Parameters:
    ///   - channelId: Channel identifier for the room.
    ///   - completion: Called on the main queue with the result.
    public func createRoom(_ channelId: String, completion: @escaping (Result<SyRoomInfo, Error>) -> Void) {
        let req = request(path: "rooms", method: "POST", body: ["channelId": channelId])
        perform(req) { (data: Data) throws -> SyRoomInfo in
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let roomDict = json?["room"] as? [String: Any] ?? json?["data"] as? [String: Any] ?? json
            guard let dict = roomDict as? [String: Any], let room = SyRoomInfo(from: dict) else {
                throw SyRoomServiceError.parseError
            }
            return room
        } completion: { completion($0) }
    }

    /// Closes a room by channel ID.
    /// - Parameters:
    ///   - channelId: Channel identifier of the room to close.
    ///   - completion: Called on the main queue with the result.
    public func closeRoom(_ channelId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let req = request(path: "rooms/\(channelId)/close", method: "POST")
        perform(req) { (_: Data) in () } completion: { completion($0) }
    }

    /// Fetches detailed information for a room.
    /// - Parameters:
    ///   - channelId: Channel identifier.
    ///   - completion: Called on the main queue with the result.
    public func getRoomDetail(_ channelId: String, completion: @escaping (Result<SyRoomInfo, Error>) -> Void) {
        let req = request(path: "rooms/\(channelId)")
        perform(req) { (data: Data) throws -> SyRoomInfo in
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let roomDict = json?["room"] as? [String: Any] ?? json?["data"] as? [String: Any] ?? json
            guard let dict = roomDict as? [String: Any], let room = SyRoomInfo(from: dict) else {
                throw SyRoomServiceError.parseError
            }
            return room
        } completion: { completion($0) }
    }

    /// Fetches the current online user count for a room.
    /// - Parameters:
    ///   - channelId: Channel identifier.
    ///   - completion: Called on the main queue with the result.
    public func getOnlineCount(_ channelId: String, completion: @escaping (Result<Int, Error>) -> Void) {
        let req = request(path: "rooms/\(channelId)/online-count")
        perform(req) { (data: Data) throws -> Int in
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let count = json?["onlineCount"] as? Int { return count }
            if let count = json?["count"] as? Int { return count }
            if let count = json?["data"] as? Int { return count }
            throw SyRoomServiceError.parseError
        } completion: { completion($0) }
    }

    /// Fetches an RTC token for joining a channel.
    /// - Parameters:
    ///   - channelId: Channel identifier.
    ///   - uid: User identifier.
    ///   - expireHours: Token validity in hours (default: 24).
    ///   - completion: Called on the main queue with the result.
    public func fetchToken(
        channelId: String,
        uid: String,
        expireHours: Int = 24,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let body: [String: Any] = [
            "channelId": channelId,
            "uid": uid,
            "expireHours": expireHours
        ]
        let req = request(path: "token", method: "POST", body: body)
        perform(req) { (data: Data) throws -> String in
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let token = json?["token"] as? String { return token }
            if let token = json?["data"] as? String { return token }
            throw SyRoomServiceError.parseError
        } completion: { completion($0) }
    }
}

// MARK: - Errors

private enum SyRoomServiceError: LocalizedError {
    case invalidRequest
    case noData
    case parseError
    case httpError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest: return "Invalid request URL"
        case .noData: return "No data received"
        case .parseError: return "Failed to parse response"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        }
    }
}
