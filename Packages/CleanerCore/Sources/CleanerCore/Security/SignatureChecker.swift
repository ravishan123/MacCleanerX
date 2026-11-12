import Foundation
import Security

/// Code-signature status of a binary or app bundle, from the Security
/// framework (the same checks `codesign --verify` performs).
public enum SignatureStatus: Sendable, Hashable {
    case apple
    case appStore(team: String?)
    case developerID(team: String?)
    /// Valid signature from some other certificate (e.g. a development cert).
    case otherCertificate(team: String?)
    /// Valid ad-hoc signature: no identity, not from an identified developer.
    case adHoc
    case unsigned
    /// Signature present but broken: the code was changed after signing.
    case invalid(OSStatus)

    public var isTrustedDeveloper: Bool {
        switch self {
        case .apple, .appStore, .developerID: true
        default: false
        }
    }

    public var displayName: String {
        switch self {
        case .apple: "Signed by Apple"
        case .appStore: "Mac App Store"
        case .developerID(let team): "Developer ID" + (team.map { " (\($0))" } ?? "")
        case .otherCertificate(let team): "Signed" + (team.map { " (\($0))" } ?? "")
        case .adHoc: "Ad-hoc signature"
        case .unsigned: "Not signed"
        case .invalid: "Broken signature"
        }
    }
}

public enum SignatureChecker {
    /// - Parameter validateResources: Also hash every file inside a bundle.
    ///   Thorough but slow for large apps, so app scans leave it off.
    public static func status(of url: URL, validateResources: Bool = false) -> SignatureStatus {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode
        else { return .unsigned }

        var flags: SecCSFlags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures)
        if !validateResources { flags.insert(SecCSFlags(rawValue: kSecCSDoNotValidateResources)) }
        let validity = SecStaticCodeCheckValidity(code, flags, nil)
        if validity == errSecCSUnsigned { return .unsigned }
        guard validity == errSecSuccess else { return .invalid(validity) }

        var info: CFDictionary?
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        let dict = info as? [String: Any] ?? [:]
        let team = dict[kSecCodeInfoTeamIdentifier as String] as? String
        let codeFlags = (dict[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        if codeFlags & SecCodeSignatureFlags.adhoc.rawValue != 0 { return .adHoc }

        if satisfies(code, "anchor apple") { return .apple }
        if satisfies(code, "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.9] exists") {
            return .appStore(team: team)
        }
        if satisfies(code, "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists") {
            return .developerID(team: team)
        }
        return .otherCertificate(team: team)
    }

    private static func satisfies(_ code: SecStaticCode, _ requirementText: String) -> Bool {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSDoNotValidateResources), requirement) == errSecSuccess
    }
}
