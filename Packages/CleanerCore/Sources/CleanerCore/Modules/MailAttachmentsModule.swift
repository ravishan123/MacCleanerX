import Foundation

/// Attachments Mail saved when you opened or previewed them. The originals
/// stay in your mailbox, but these are files you may have opened, so they are
/// marked Review. Reading Mail's folder requires Full Disk Access.
public struct MailAttachmentsModule: CleanupModule {
    public let category = CleanupCategory.mailAttachments
    public static let groupName = "Mail"

    private let support: PathModuleSupport
    private let roots: [URL]

    public init(context: ModuleContext) {
        roots = Self.roots(for: context)
        support = PathModuleSupport(category: category, context: context, roots: roots)
    }

    static func roots(for context: ModuleContext) -> [URL] {
        [
            context.library.appending(path: "Containers/com.apple.mail/Data/Library/Mail Downloads", directoryHint: .isDirectory),
            context.library.appending(path: "Mail Downloads", directoryHint: .isDirectory), // pre-sandbox Mail
        ]
    }

    public func scan() async -> [Finding] {
        await support.scan(roots.map {
            .topLevel($0, risk: .review, accessGroup: Self.groupName, group: { _ in Self.groupName })
        })
    }

    public func clean(_ findings: [Finding], mode: RemovalMode) async -> CleanResult {
        support.clean(findings, mode: mode)
    }
}
