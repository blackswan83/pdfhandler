//
//  MainThreadAssumption.swift
//  PDFHandler
//
//  Restates a runtime main-thread guarantee to the compiler for
//  callbacks that AppKit always delivers on the main thread but whose
//  block types are nonisolated (NSEvent local monitors, UndoManager
//  undo handlers). MainActor.assumeIsolated needs a newer runtime
//  than this app targets, hence the cast.
//

import Foundation

func assumingMainActor<T>(_ body: @MainActor () -> T) -> T {
    precondition(Thread.isMainThread, "assumingMainActor called off the main thread")
    return withoutActuallyEscaping(body) { escapable in
        unsafeBitCast(escapable, to: (() -> T).self)()
    }
}
