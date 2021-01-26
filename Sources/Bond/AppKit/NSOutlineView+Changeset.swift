//
//  The MIT License (MIT)
//
//  Copyright (c) 2018 DeclarativeHub/Bond
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#if canImport(AppKit) && !targetEnvironment(macCatalyst)

import AppKit
import ReactiveKit

open class OutlineViewBinder<Changeset: TreeChangesetProtocol>: NSObject, NSOutlineViewDataSource {

    // NSOutlineView display a tree data structure that does not have a single root.
    //
    // "Items" of type `Any` that NSOutlineView asks for in the data source methods are tree nodes themselves, in our case `TreeNode`.
    // Note that we can't use value types here because NSOutlineView is a ObjC type so we need to use TreeArray.Object and TreeNode.Object variants.
    
    public typealias IsItemExpandable = (Changeset.Collection.Children.Element, NSOutlineView) -> Bool
    public typealias ObjectValueForItem = (Changeset.Collection.Children.Element) -> Any?

    public var isItemExpandable: IsItemExpandable? = nil
    public var objectValueForItem: ObjectValueForItem

    /// Local clone of the bound data tree wrapped into a class based tree type.
    public var rootNode = ObjectTreeArray<Changeset.Collection.Children.Element>()

    public var changeset: Changeset? = nil {
        didSet {
            if let changeset = changeset {
                if oldValue != nil {
                    applyChangeset(changeset)
                }  else {
                    rootNode = clone(changeset.collection)
                    outlineView?.reloadData()
                }
            } else {
                rootNode.children = []
                outlineView?.reloadData()
            }
        }
    }

    public weak var outlineView: NSOutlineView? = nil {
        didSet {
            guard let outlineView = outlineView else { return }
            associate(with: outlineView)
        }
    }

    open var itemInsertionAnimation: NSOutlineView.AnimationOptions = [.effectFade, .slideUp]
    open var itemDeletionAnimation: NSOutlineView.AnimationOptions = [.effectFade, .slideUp]

    /// Default initializer.
    ///
    /// - parameters:
    ///     - objectValueForItem: A closure that returns object value for the given node to be used in NSOutlineViewDataSource.
    public init(objectValueForItem: @escaping ObjectValueForItem) {
        self.objectValueForItem = objectValueForItem
        super.init()
    }

    public func item(at indexPath: IndexPath) -> ObjectTreeNode<Changeset.Collection.Children.Element> {
        return rootNode[childAt: indexPath]
    }

    public func treeNode(forItem item: Any) -> Changeset.Collection.Children.Element? {
        return (item as? ObjectTreeNode<Changeset.Collection.Children.Element>)?.value
    }

    // MARK: - NSOutlineViewDataSource

    @objc(outlineView:isItemExpandable:)
    open func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let item = item as? ObjectTreeNode<Changeset.Collection.Children.Element> else { return false }
        return isItemExpandable?(item.value, outlineView) ?? item.children.isEmpty == false
    }

    @objc(outlineView:numberOfChildrenOfItem:)
    open func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let item = item as? ObjectTreeNode<Changeset.Collection.Children.Element> {
            return item.children.count
        } else {
            return rootNode.children.count
        }
    }

    @objc(outlineView:child:ofItem:)
    open func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let item = item as? ObjectTreeNode<Changeset.Collection.Children.Element> {
            return item[[index]]
        } else {
            return rootNode[childAt: [index]]
        }
    }

    @objc(outlineView:objectValueForTableColumn:byItem:)
    open func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        if let item = item as? ObjectTreeNode<Changeset.Collection.Children.Element> {
            return objectValueForItem(item.value)
        } else {
            return nil
        }
    }

    open func applyChangeset(_ changeset: Changeset) {
        guard let outlineView = outlineView else { return }
        let patch = changeset.patch
        if patch.isEmpty {
            rootNode = clone(changeset.collection)
            outlineView.reloadData()
        } else {
            outlineView.beginUpdates()
            patch.forEach { applyOperation($0.asOrderedCollectionOperation) }
            outlineView.endUpdates()
        }
    }

    open func applyOperation(_ operation: OrderedCollectionOperation<Changeset.Collection.Children.Element, IndexPath>) {
        guard let outlineView = outlineView else { return }

        switch operation {
        case .insert(_, let at):
            rootNode.apply(operation.asOrderedCollectionOperation.mapElement { clone($0) })
            let parent = parentNode(forPath: at) // parent after the tree is patched
            outlineView.insertItems(at: IndexSet(integer: at.last!), inParent: parent, withAnimation: itemInsertionAnimation)
        case .delete(let at):
            let parent = parentNode(forPath: at) // parent before the tree is patched
            rootNode.apply(operation.asOrderedCollectionOperation.mapElement { clone($0) })
            outlineView.removeItems(at: IndexSet(integer: at.last!), inParent: parent, withAnimation: itemDeletionAnimation)
        case .update(let at, _):
            let parent = parentNode(forPath: at)  // parent before the tree is patched
            rootNode.apply(operation.asOrderedCollectionOperation.mapElement { clone($0) })
            outlineView.removeItems(at: IndexSet(integer: at.last!), inParent: parent, withAnimation: itemDeletionAnimation)
            outlineView.insertItems(at: IndexSet(integer: at.last!), inParent: parent, withAnimation: itemInsertionAnimation)
        case .move(let from, let to):
            let fromParent = parentNode(forPath: from) // parent before the tree is patched
            rootNode.apply(operation.asOrderedCollectionOperation.mapElement { clone($0) })
            let toParent = parentNode(forPath: to) // parent after the tree is patched
            outlineView.moveItem(at: from.last!, inParent: fromParent, to: to.last!, inParent: toParent)
        }
    }

    public func parentNode(forPath path: IndexPath) -> ObjectTreeNode<Changeset.Collection.Children.Element>? {
        guard path.count > 1 else {
            return nil
        }
        return rootNode[childAt: path.dropLast()]
    }

    private func associate(with outlineView: NSOutlineView) {
        objc_setAssociatedObject(outlineView, &OutlineViewBinderDataSourceAssociationKey, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        if outlineView.reactive.hasProtocolProxy(for: NSOutlineViewDataSource.self) {
            outlineView.reactive.dataSource.forwardTo = self
        } else {
            outlineView.dataSource = self
        }
    }

    private func clone(_ array: Changeset.Collection) -> ObjectTreeArray<Changeset.Collection.Children.Element> {
        return ObjectTreeArray(array.children.map { clone($0) })
    }

    private func clone(_ node: Changeset.Collection.Children.Element) -> ObjectTreeNode<Changeset.Collection.Children.Element> {
        var newNode = ObjectTreeNode(node)
        for index in node.breadthFirst.indices.dropFirst() {
            newNode.insert(ObjectTreeNode(node[childAt: index]), at: index)
        }
        return newNode
    }
}

private var OutlineViewBinderDataSourceAssociationKey = "OutlineViewBinderDataSource"

extension OutlineViewBinder {

    public class ReloadingBinder: OutlineViewBinder {
        public override func applyChangeset(_ changeset: Changeset) {
            rootNode = clone(changeset.collection)
            outlineView?.reloadData()
        }
    }
}

extension SignalProtocol where Element: OutlineChangesetConvertible, Error == Never {
    /// Binds the signal of data source elements to the given outline view.
    ///
    /// - parameters:
    ///     - outlineView: An outline view that should display the data from the data source.
    ///     - animated: Animate partial or batched updates. Default is `true`.
    ///     - rowAnimation: Row animation for partial or batched updates. Relevant only when `animated` is `true`. Default is `[.effectFade, .slideUp]`.
    ///     - objectValueForItem: A closure that returns object value for the given node to be used in NSOutlineViewDataSource.
    /// - returns: A disposable object that can terminate the binding. Safe to ignore - the binding will be automatically terminated when the table view is deallocated.
    @discardableResult
    public func bind(to outlineView: NSOutlineView, animated: Bool = true, rowAnimation: NSOutlineView.AnimationOptions = [.effectFade, .slideUp], objectValueForItem: @escaping (Element.Changeset.Collection.Children.Element) -> Any?) -> Disposable {
        if animated {
            let binder = OutlineViewBinder<Element.Changeset>(objectValueForItem: objectValueForItem)
            binder.itemInsertionAnimation = rowAnimation
            binder.itemDeletionAnimation = rowAnimation
            binder.objectValueForItem = objectValueForItem
            return bind(to: outlineView, using: binder)
        } else {
            let binder = OutlineViewBinder<Element.Changeset>.ReloadingBinder(objectValueForItem: objectValueForItem)
            return bind(to: outlineView, using: binder)
        }
    }

    /// Binds the signal of data source elements to the given outline view.
    ///
    /// - parameters:
    ///     - outlineView: An outline view that should display the data from the data source.
    ///     - binder: A `OutlineViewBinder` or its subclass that will manage the binding.
    /// - returns: A disposable object that can terminate the binding. Safe to ignore - the binding will be automatically terminated when the outline view is deallocated.
    @discardableResult
    public func bind(to outlineView: NSOutlineView, using binder: OutlineViewBinder<Element.Changeset>) -> Disposable {
        binder.outlineView = outlineView
        return bind(to: outlineView) { (_, changeset) in
            binder.changeset = changeset.asTreeArrayChangeset
        }
    }
}

extension SignalProtocol where Element: OutlineChangesetConvertible, Element.Changeset.Collection.Children.Element: TreeNodeWithValueProtocol, Error == Never {

    /// Binds the signal of data source elements to the given outline view.
    ///
    /// - parameters:
    ///     - outlineView: An outline view that should display the data from the data source.
    ///     - animated: Animate partial or batched updates. Default is `true`.
    ///     - rowAnimation: Row animation for partial or batched updates. Relevant only when `animated` is `true`. Default is `[.effectFade, .slideUp]`.
    /// - returns: A disposable object that can terminate the binding. Safe to ignore - the binding will be automatically terminated when the table view is deallocated.
    @discardableResult
    public func bind(to outlineView: NSOutlineView, animated: Bool = true, rowAnimation: NSOutlineView.AnimationOptions = [.effectFade, .slideUp]) -> Disposable {
        return bind(to: outlineView, animated: animated, rowAnimation: rowAnimation, objectValueForItem: { $0.value })
    }
}

#endif
