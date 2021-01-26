//
//  The MIT License (MIT)
//
//  Copyright (c) 2019 DeclarativeHub/Bond
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

private var TableViewBinderDataSourceAssociationKey = "TableViewBinderDataSource"

open class TableViewBinderDataSource<Changeset: FlatDataSourceChangeset>: NSObject, NSTableViewDataSource {

    open var rowInsertionAnimation: NSTableView.AnimationOptions = [.effectFade, .slideLeft]
    open var rowRemovalAnimation: NSTableView.AnimationOptions = [.effectFade, .slideLeft]

    /// Local clone of the bound collection
    public var collection: [Changeset.Collection.Item] = []

    public var changeset: Changeset? = nil {
        didSet {
            if let changeset = changeset {
                if oldValue != nil {
                    apply(changeset: changeset)
                } else {
                    collection = clone(changeset.collection)
                    tableView?.reloadData()
                }
            } else {
                collection = []
                tableView?.reloadData()
            }
        }
    }

    public weak var tableView: NSTableView? = nil {
        didSet {
            guard let tableView = tableView else { return }
            associateWithTableView(tableView)
        }
    }

    // MARK: - NSTableViewDataSource

    @objc(numberOfRowsInTableView:)
    open func numberOfRows(in tableView: NSTableView) -> Int {
        return collection.count
    }

    @objc(tableView:objectValueForTableColumn:row:)
    open func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        return collection[row]
    }

    open func apply(changeset: Changeset) {
        guard let tableView = tableView else { return }
        let patch = changeset.patch
        if patch.isEmpty {
            collection = clone(changeset.collection)
            tableView.reloadData()
        } else {
            tableView.beginUpdates()
            patch.forEach(apply)
            tableView.endUpdates()
        }
    }

    open func apply(operation: Changeset.Operation) {
        guard let tableView = tableView else { return }

        switch operation.asOrderedCollectionOperation {
        case .insert(let element, let index):
            collection.apply(.insert(element, at: index.asFlatDataIndex))
            tableView.insertRows(at: IndexSet([index.asFlatDataIndex]), withAnimation: rowInsertionAnimation)
        case .delete(let index):
            collection.apply(.delete(at: index.asFlatDataIndex))
            tableView.removeRows(at: IndexSet([index.asFlatDataIndex]), withAnimation: rowRemovalAnimation)
        case .update(let index, let element):
            collection.apply(.update(at: index.asFlatDataIndex, newElement: element))
            let allColumnIndexes = IndexSet(tableView.tableColumns.enumerated().map { $0.0 })
            tableView.reloadData(forRowIndexes: IndexSet([index.asFlatDataIndex]), columnIndexes: allColumnIndexes)
        case .move(let from, let to):
            collection.apply(.move(from: from.asFlatDataIndex, to: to.asFlatDataIndex))
            tableView.moveRow(at: from.asFlatDataIndex, to: to.asFlatDataIndex)
        }
    }

    private func associateWithTableView(_ tableView: NSTableView) {
        objc_setAssociatedObject(tableView, &TableViewBinderDataSourceAssociationKey, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        if tableView.reactive.hasProtocolProxy(for: NSTableViewDataSource.self) {
            tableView.reactive.dataSource.forwardTo = self
        } else {
            tableView.dataSource = self
        }
    }

    private func clone(_ collection: Changeset.Collection) -> [Changeset.Collection.Item] {
        return (0..<collection.numberOfItems).map { collection.item(at: $0) }
    }
}

extension TableViewBinderDataSource {
    public class ReloadingBinder: TableViewBinderDataSource {
        public override func apply(changeset: Changeset) {
            tableView?.reloadData()
        }
    }
}

extension SignalProtocol where Element: FlatDataSourceChangesetConvertible, Error == Never {

    /// Binds the signal of data source elements to the given table view.
    ///
    /// - parameters:
    ///     - tableView: A table view that should display the data from the data source.
    ///     - animated: Animate partial or batched updates. Default is `true`.
    ///     - rowAnimation: Row animation for partial or batched updates. Relevant only when `animated` is `true`. Default is `[.effectFade, .slideLeft]`.
    /// - returns: A disposable object that can terminate the binding. Safe to ignore - the binding will be automatically terminated when the table view is deallocated.
    @discardableResult
    public func bind(to tableView: NSTableView, animated: Bool = true, rowAnimation: NSTableView.AnimationOptions = [.effectFade, .slideLeft]) -> Disposable {
        if animated {
            let binder = TableViewBinderDataSource<Element.Changeset>()
            binder.rowInsertionAnimation = rowAnimation
            binder.rowRemovalAnimation = rowAnimation
            return bind(to: tableView, using: binder)
        } else {
            let binder = TableViewBinderDataSource<Element.Changeset>.ReloadingBinder()
            return bind(to: tableView, using: binder)
        }
    }

    /// Binds the signal of data source elements to the given table view.
    ///
    /// - parameters:
    ///     - tableView: A table view that should display the data from the data source.
    ///     - binder: A `TableViewBinder` or its subclass that will manage the binding.
    /// - returns: A disposable object that can terminate the binding. Safe to ignore - the binding will be automatically terminated when the table view is deallocated.
    @discardableResult
    public func bind(to tableView: NSTableView, using binder: TableViewBinderDataSource<Element.Changeset>) -> Disposable {
        binder.tableView = tableView
        return bind(to: tableView) { (_, changeset) in
            binder.changeset = changeset.asFlatDataSourceChangeset
        }
    }
}

#endif
