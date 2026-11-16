#if canImport(Photos)
import Foundation
import Photos

/// Debounces PhotoKit change notifications and calls a handler on change.
public final class ChangeObserver: NSObject, PHPhotoLibraryChangeObserver, Sendable {
    private let onChange: @Sendable () -> Void
    private let debounceInterval: TimeInterval
    private let pendingWork = LockedBox<DispatchWorkItem?>(nil)

    /// Creates an observer that calls `onChange` (debounced) when the photo library changes.
    public init(debounceInterval: TimeInterval = 2.0, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        self.debounceInterval = debounceInterval
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    public func photoLibraryDidChange(_ changeInstance: PHChange) {
        let work = DispatchWorkItem { [onChange] in onChange() }
        let old = pendingWork.swap(work)
        old?.cancel()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}

/// A simple lock-protected box for Sendable conformance.
private final class LockedBox<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ value: T) { self.value = value }
    func swap(_ new: T) -> T {
        lock.lock()
        defer { lock.unlock() }
        let old = value
        value = new
        return old
    }
}
#endif
