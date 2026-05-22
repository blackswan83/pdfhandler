//
//  UndoCoordinator.swift
//  PDFHandler
//
//  Thin wrapper over AppKit's UndoManager that operates on our
//  Placement array. Every placement mutation (add, update, delete)
//  goes through one of the three entry points below, which also
//  registers the inverse operation so ⌘Z / ⌘⇧Z just work.
//

import Foundation
import AppKit

@MainActor
final class UndoCoordinator {

    private let manager = UndoManager()
    private var placements: () -> [Placement]
    private var replace: ([Placement]) -> Void

    init(
        placements: @escaping () -> [Placement],
        replace: @escaping ([Placement]) -> Void
    ) {
        self.placements = placements
        self.replace = replace
    }

    var canUndo: Bool { manager.canUndo }
    var canRedo: Bool { manager.canRedo }

    func undo() { manager.undo() }
    func redo() { manager.redo() }

    /// Register any mutation by snapshotting the current placements,
    /// applying the change, and queuing the snapshot as the inverse.
    func apply(_ label: String, _ mutate: () -> Void) {
        let snapshot = placements()
        mutate()
        manager.registerUndo(withTarget: self) { target in
            Task { @MainActor in
                target.applyReplacement(label, snapshot: snapshot)
            }
        }
        manager.setActionName(label)
    }

    private func applyReplacement(_ label: String, snapshot: [Placement]) {
        let current = placements()
        replace(snapshot)
        manager.registerUndo(withTarget: self) { target in
            Task { @MainActor in
                target.applyReplacement(label, snapshot: current)
            }
        }
        manager.setActionName(label)
    }
}
