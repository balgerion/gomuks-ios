import Foundation

enum VideoPlayer {
    private static let key = "player_url"
    private static let videoHosts = [
        "youtube.com", "youtu.be", "youtube-nocookie.com", "vimeo.com", "tiktok.com",
        "twitch.tv", "dailymotion.com", "dai.ly", "streamable.com",
    ]

    static var server: URL? {
        get {
            UserDefaults.standard.string(forKey: key).flatMap(Credentials.parseServer)
        }
        set {
            UserDefaults.standard.set(newValue?.absoluteString, forKey: key)
        }
    }

    static func watchURL(for link: URL) -> URL? {
        playerURL(for: link, endpoint: "watch")
    }

    static func iframeURL(for link: URL) -> URL? {
        playerURL(for: link, endpoint: "iframe")
    }

    private static func playerURL(for link: URL, endpoint: String) -> URL? {
        guard let server, isVideoLink(link),
              var components = URLComponents(url: server, resolvingAgainstBaseURL: false)
        else { return nil }
        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path + "/" + endpoint
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        guard let encoded = link.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        components.percentEncodedQuery = "url=" + encoded
        return components.url
    }

    private static func isVideoLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased()
        else { return false }
        if host == "instagram.com" || host.hasSuffix(".instagram.com") {
            return url.path.hasPrefix("/reel")
        }
        if host == "fb.watch" {
            return true
        }
        if host == "facebook.com" || host.hasSuffix(".facebook.com") {
            let path = url.path
            return ["/reel", "/share/r/", "/share/v/", "/watch"].contains { path.hasPrefix($0) } || path.contains("/videos/")
        }
        return videoHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
