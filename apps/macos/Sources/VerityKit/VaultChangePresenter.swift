import Foundation

public final class VaultChangePresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    public let presentedItemURL: URL?
    public let presentedItemOperationQueue: OperationQueue
    private let onChange: @Sendable () -> Void

    public init(root: URL, onChange: @escaping @Sendable () -> Void) {
        self.presentedItemURL = root
        self.onChange = onChange
        let queue = OperationQueue()
        queue.name = "app.verity.native.vault-changes"
        queue.maxConcurrentOperationCount = 1
        self.presentedItemOperationQueue = queue
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    deinit {
        NSFileCoordinator.removeFilePresenter(self)
    }

    public func presentedItemDidChange() { onChange() }
    public func presentedSubitemDidChange(at url: URL) { onChange() }
    public func presentedSubitemDidAppear(at url: URL) { onChange() }
    public func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping @Sendable (Error?) -> Void) {
        onChange()
        completionHandler(nil)
    }
}
