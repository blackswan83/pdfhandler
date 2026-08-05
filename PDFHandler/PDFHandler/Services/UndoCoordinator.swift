//
//  UndoCoordinator.swift
//  PDFHandler
//
//  Thin wrapper over AppKit's UndoManager that operates on our
//  Placement array. Every placement mutation goes through one of the
//  entry points below, which also registers the inverse operation so
//  ⌘Z / ⌘⇧Z just work.
//
//  The undo handlers run SYNCHRONOUSLY: UndoManager decides whether a
//  registerUndo call belongs to the undo or the redo stack from its
//  isUndoing/isRedoing state *at call time*. Deferring the handler to
//  a Task would re-register after undo() returned, putting the inverse
//  on the undo stack again — redo would never work and undo would just
//  toggle one step back and forth.
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

    /// Drop the whole stack. Called when the placement world changes
    /// out from under it (new document opened, library entry deleted)
    /// so undo can never resurrect placements that reference stale
    /// documents or deleted signatures.
    func reset() { manager.removeAllActions() }

    /// Register any mutation by snapshotting the current placements,
    /// applying the change, and queuing the snapshot as the inverse.
    func apply(_ label: String, _ mutate: () -> Void) {
        let snapshot = placements()
        mutate()
        registerReplacement(label, snapshot: snapshot)
    }

    /// Register a single undo step for a mutation that already
    /// happened, using a snapshot captured before it began. This is
    /// how drags, resizes and text-edit sessions record ONE step at
    /// the end instead of one per mouse tick / keystroke.
    func commit(_ label: String, before snapshot: [Placement]) {
        registerReplacement(label, snapshot: snapshot)
    }

    // MARK: - Internals

    private func registerReplacement(_ label: String, snapshot: [Placement]) {
        manager.registerUndo(withTarget: self) { target in
            // UndoManager fires this on the thread that calls undo()/
            // redo() — always the main thread here.
            assumingMainActor {
                target.applyReplacement(label, snapshot: snapshot)
            }
        }
        manager.setActionName(label)
    }

    private func applyReplacement(_ label: String, snapshot: [Placement]) {
        let current = placements()
        replace(snapshot)
        registerReplacement(label, snapshot: current)
    }
}
