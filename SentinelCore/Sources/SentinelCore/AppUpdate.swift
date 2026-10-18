import Foundation

/// The check for a newer version of the app on GitHub.
///
/// The app only reads the latest release: the version of its tag decides
/// whether the sidebar and the 通知 page show a newer version, and the release
/// page is where the user downloads it. Nothing is installed here.
///
/// Every function is pure: the version comparison and the reading of the GitHub
/// answer are tested without a network and without a release.
public enum AppUpdate {
    /// The latest published release, as far as it concerns the app.
    public struct Release: Equatable, Sendable {
        /// Version of the tag without the leading `v`, for example `0.3`.
        public let version: String
        /// The release page (`html_url`), where the user downloads the update.
        public let pageURL: URL

        public init(version: String, pageURL: URL) {
            self.version = version
            self.pageURL = pageURL
        }
    }

    // MARK: - Endpoint

    /// The `releases/latest` endpoint of a GitHub repository.
    ///
    /// The app keeps only its repository address (`AppInfo.repositoryURL`), so
    /// the owner and the repository name are read from it instead of being
    /// written a second time.
    ///
    /// - Parameter repositoryURL: `https://github.com/owner/repository`.
    /// - Returns: `https://api.github.com/repos/owner/repository/releases/latest`,
    ///   or `nil` for an address without an owner and a repository.
    public static func latestReleaseEndpoint(for repositoryURL: URL) -> URL? {
        // `pathComponents` of an absolute URL starts with `/`; the last two
        // components are the owner and the repository.
        let path = repositoryURL.pathComponents.filter { $0 != "/" }
        guard path.count >= 2 else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(path[path.count - 2])/\(path[path.count - 1])/releases/latest"
        return components.url
    }

    // MARK: - Version

    /// `true` when `candidate` is a newer version than `current`.
    ///
    /// Both sides are split at the dots and compared segment by segment as whole
    /// numbers, so `0.10` is newer than `0.2` and `0.2.0` is the same as `0.2`.
    /// A leading `v` of a tag is ignored. A text that is no dotted number — an
    /// empty text, `0.3-beta`, `vNext` — is no version at all and never counts
    /// as newer, so a tag the app cannot read cannot ask the user to update.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let candidate = versionNumbers(candidate),
              let current = versionNumbers(current) else {
            return false
        }

        for index in 0..<max(candidate.count, current.count) {
            // A missing segment counts as zero: `0.2` and `0.2.0` are equal.
            let left = index < candidate.count ? candidate[index] : 0
            let right = index < current.count ? current[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }

    /// The numbers of a version text, or `nil` for a text that is no version.
    ///
    /// A tag may carry a leading `v` (`v0.3`); the rest has to be dot-separated
    /// ASCII digits, at least one.
    private static func versionNumbers(_ text: String) -> [Int]? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }
        guard !value.isEmpty else { return nil }

        var numbers: [Int] = []
        for part in value.split(separator: ".", omittingEmptySubsequences: false) {
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(part) else {
                return nil
            }
            numbers.append(number)
        }
        return numbers
    }

    // MARK: - Answer

    /// Reads the answer of `releases/latest`.
    ///
    /// A draft or a prerelease is not offered to the user, and an answer without
    /// a readable `tag_name` or `html_url` is no release at all. The version is
    /// normalized, so `v0.03` and `v0.3` both read `0.3`.
    ///
    /// - Parameter data: the JSON of the GitHub API.
    /// - Returns: the release, or `nil` when the answer has none.
    public static func release(fromLatestRelease data: Data) -> Release? {
        guard let payload = try? JSONDecoder().decode(LatestRelease.self, from: data),
              payload.draft != true,
              payload.prerelease != true,
              let version = versionNumbers(payload.tagName),
              let pageURL = URL(string: payload.htmlURL),
              let scheme = pageURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              pageURL.host != nil else {
            return nil
        }

        return Release(
            version: version.map { String($0) }.joined(separator: "."),
            pageURL: pageURL
        )
    }

    /// The fields of `releases/latest` the app reads; the rest is ignored.
    private struct LatestRelease: Decodable {
        let tagName: String
        let htmlURL: String
        let draft: Bool?
        let prerelease: Bool?

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
        }
    }
}
