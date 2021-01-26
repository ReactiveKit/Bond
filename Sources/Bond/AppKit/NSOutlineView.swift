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

extension ReactiveExtensions where Base: NSOutlineView {
    public var delegate: ProtocolProxy {
        return protocolProxy(for: NSOutlineViewDelegate.self, keyPath: \.delegate)
    }

    public var dataSource: ProtocolProxy {
        return protocolProxy(for: NSOutlineViewDataSource.self, keyPath: \.dataSource)
    }

    public var selectionIsChanging: SafeSignal<Void> {
        return NotificationCenter.default.reactive.notification(name: NSOutlineView.selectionIsChangingNotification, object: base).eraseType()
    }

    public var selectionDidChange: SafeSignal<Void> {
        return NotificationCenter.default.reactive.notification(name: NSOutlineView.selectionDidChangeNotification, object: base).eraseType()
    }

    public var selectedRowIndexes: Bond<IndexSet> {
        return bond { $0.selectRowIndexes($1, byExtendingSelection: false) }
    }

    public var selectedColumnIndexes: Bond<IndexSet> {
        return bond { $0.selectColumnIndexes($1, byExtendingSelection: false) }
    }

    public var selectedItems: DynamicSubject<[Any]> {
        return dynamicSubject(
            signal: self.selectionDidChange,
            triggerEventOnSetting: false,
            get: { outlineView in
                outlineView.selectedRowIndexes.compactMap { outlineView.item(atRow: $0) }
            },
            set: { outlineView, items in
                let indexes = IndexSet(items.map { outlineView.row(forItem: $0) })
                outlineView.selectRowIndexes(indexes, byExtendingSelection: false)
            }
        )
    }
}

#endif
