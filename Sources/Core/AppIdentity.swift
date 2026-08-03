import Foundation
import Security

enum AppIdentity {
    static let productionBundleIdentifier = "com.wanruncong.glosspop"
    static let productionTeamIdentifier = "F4848G2W8P"
    static let installedBundlePath = "/Applications/GlossPop.app"

    static let isCurrentOfficialBuild: Bool = isOfficialBuild(
        bundleIdentifier: Bundle.main.bundleIdentifier,
        teamIdentifier: signingTeamIdentifier(at: Bundle.main.bundleURL)
    )

    static let isCurrentInstalledRelease = isCurrentOfficialBuild
        && Bundle.main.bundleURL.standardizedFileURL.path == installedBundlePath

    static func isOfficialBuild(
        bundleIdentifier: String?,
        teamIdentifier: String?
    ) -> Bool {
        bundleIdentifier == productionBundleIdentifier
            && teamIdentifier == productionTeamIdentifier
    }

    static func isInstalledRelease(
        bundleIdentifier: String?,
        teamIdentifier: String?,
        bundleURL: URL
    ) -> Bool {
        isOfficialBuild(bundleIdentifier: bundleIdentifier, teamIdentifier: teamIdentifier)
            && bundleURL.standardizedFileURL.path == installedBundlePath
    }

    private static func signingTeamIdentifier(at bundleURL: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else { return nil }

        var info: CFDictionary?
        let status = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info
        )
        guard status == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
