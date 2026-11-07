import AppKit
import SwiftUI
import Testing
@testable import GPTMonitorBar

@MainActor
struct PanelRenderingTests {
    @Test func darkBackgroundStaysDarkOverLightAndDarkSurfaces() throws {
        let overWhite = try backgroundPixel(over: .white)
        let overBlack = try backgroundPixel(over: .black)
        #expect(overWhite.redComponent < 0.20)
        #expect(overWhite.greenComponent < 0.20)
        #expect(overWhite.blueComponent < 0.20)
        #expect(abs(overWhite.redComponent - overBlack.redComponent) < 0.01)
        #expect(abs(overWhite.greenComponent - overBlack.greenComponent) < 0.01)
        #expect(abs(overWhite.blueComponent - overBlack.blueComponent) < 0.01)
    }

    private func backgroundPixel(over backing: Color) throws -> NSColor {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: PanelBackground()
            .frame(width: 32, height: 32)
            .background(backing)
            .environment(\.colorScheme, .dark))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.appearance = host.appearance
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let pixel = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
        return try #require(pixel.usingColorSpace(.sRGB))
    }
}
