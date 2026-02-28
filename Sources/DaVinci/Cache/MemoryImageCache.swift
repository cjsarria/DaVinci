import Foundation

#if canImport(UIKit)
import UIKit
#endif

public final class MemoryImageCache {
    private final class Node {
        let key: CacheKey
        var image: DVImage
        var cost: Int
        var prev: Node?
        var next: Node?

        init(key: CacheKey, image: DVImage, cost: Int) {
            self.key = key
            self.image = image
            self.cost = cost
        }
    }

    private let lock = NSLock()
    private var nodes: [CacheKey: Node] = [:]
    private var head: Node?
    private var tail: Node?

    public var totalCost: Int {
        lock.lock(); defer { lock.unlock() }
        return _totalCost
    }

    public var maxCost: Int {
        get { lock.lock(); defer { lock.unlock() }; return _maxCost }
        set { lock.lock(); _maxCost = max(0, newValue); lock.unlock(); trimIfNeeded() }
    }

    private var _totalCost: Int = 0
    private var _maxCost: Int

    public init(maxCost: Int = 50 * 1024 * 1024) {
        self._maxCost = max(0, maxCost)

        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        #endif
    }

    deinit {
        #if canImport(UIKit)
        NotificationCenter.default.removeObserver(self)
        #endif
    }

    public func get(_ key: CacheKey) -> DVImage? {
        lock.lock(); defer { lock.unlock() }
        guard let node = nodes[key] else { return nil }
        moveToFront(node)
        return node.image
    }

    public func set(_ image: DVImage, for key: CacheKey, costBytes: Int) {
        let cost = max(0, costBytes)

        lock.lock()
        if let node = nodes[key] {
            _totalCost -= node.cost
            node.image = image
            node.cost = cost
            _totalCost += cost
            moveToFront(node)
            lock.unlock()
        } else {
            let node = Node(key: key, image: image, cost: cost)
            nodes[key] = node
            insertAtFront(node)
            _totalCost += cost
            lock.unlock()
        }

        trimIfNeeded()
    }

    public func remove(_ key: CacheKey) {
        lock.lock(); defer { lock.unlock() }
        guard let node = nodes.removeValue(forKey: key) else { return }
        _totalCost -= node.cost
        removeNode(node)
    }

    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        nodes.removeAll(keepingCapacity: false)
        head = nil
        tail = nil
        _totalCost = 0
    }

    public func trim(toCost targetCost: Int) {
        let target = max(0, targetCost)

        lock.lock()
        while _totalCost > target, let tail {
            nodes.removeValue(forKey: tail.key)
            _totalCost -= tail.cost
            removeNode(tail)
        }
        lock.unlock()
    }

    public func trimIfNeeded() {
        let maxCost = self.maxCost
        guard maxCost > 0 else {
            removeAll()
            return
        }
        trim(toCost: maxCost)
    }

    private func insertAtFront(_ node: Node) {
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
        if tail == nil { tail = node }
    }

    private func moveToFront(_ node: Node) {
        if head === node { return }
        removeNode(node)
        insertAtFront(node)
    }

    private func removeNode(_ node: Node) {
        let prev = node.prev
        let next = node.next

        if let prev { prev.next = next } else { head = next }
        if let next { next.prev = prev } else { tail = prev }

        node.prev = nil
        node.next = nil
    }

    #if canImport(UIKit)
    @objc private func didReceiveMemoryWarning() {
        trim(toCost: maxCost / 4)
    }
    #endif
}
