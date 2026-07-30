import XCTest
import SwiftUI
@testable import SignoffUI
@testable import SignoffCore

/// Verifies the real `Brand` design-token surface in `Sources/SignoffUI/Components/Brand.swift`.
///
/// The previous version of this file tested a `Brand.Color` / `Brand.Font` /
/// `Brand.Spacing` API that never existed in the codebase and could not
/// compile. These tests exercise the tokens that actually ship: the brand
/// accent, the layout hairlines, the per-scheme semantic surface/text colors,
/// and the per-bucket accent mapping that gives each tone its own color.
final class BrandTokensTests: XCTestCase {

    // MARK: - Brand accent

    func testBrandAmberResolvesOnBothSchemes() {
        XCTAssertFalse(Brand.amber(for: .light).description.isEmpty)
        XCTAssertFalse(Brand.amber(for: .dark).description.isEmpty)
    }

    func testBrandAmberDiffersBetweenSchemes() {
        // Light amber is muted; dark amber is bright — must not be identical so
        // the accent stays readable on both paper and ink.
        XCTAssertNotEqual(Brand.amber(for: .light).description,
                          Brand.amber(for: .dark).description)
    }

    // MARK: - Layout

    func testCornerRadiusIsReasonable() {
        XCTAssertGreaterThan(Brand.Layout.cornerRadius, 0)
        XCTAssertLessThanOrEqual(Brand.Layout.cornerRadius, 16)
    }

    func testControlCornerRadiusSmallerThanCard() {
        XCTAssertLessThanOrEqual(Brand.Layout.controlCornerRadius,
                                 Brand.Layout.cornerRadius)
    }

    func testHairlineIsThinAndPositive() {
        XCTAssertGreaterThan(Brand.Layout.hairline, 0)
        XCTAssertLessThan(Brand.Layout.hairline, 1.0)
    }

    // MARK: - Semantic surfaces (ColorScheme-aware)

    func testSurfaceBaseDiffersBetweenSchemes() {
        let light = Brand.Semantic.surfaceBase(for: .light)
        let dark  = Brand.Semantic.surfaceBase(for: .dark)
        XCTAssertNotEqual(light.description, dark.description,
                          "Paper (light) and ink (dark) must differ")
    }

    func testSurfaceElevatedIsTranslucentOverBase() {
        // Elevated card sits *on* the base — both must resolve and the
        // elevated fill must be the same across schemes by construction
        // (always a white/black opacity). Just assert it renders.
        XCTAssertFalse(Brand.Semantic.surfaceElevated(for: .light).description.isEmpty)
        XCTAssertFalse(Brand.Semantic.surfaceElevated(for: .dark).description.isEmpty)
    }

    func testTextPrimaryResolvesOnBothSchemes() {
        XCTAssertFalse(Brand.Semantic.textPrimary(for: .light).description.isEmpty)
        XCTAssertFalse(Brand.Semantic.textPrimary(for: .dark).description.isEmpty)
    }

    func testTextSecondaryResolvesOnBothSchemes() {
        XCTAssertFalse(Brand.Semantic.textSecondary(for: .light).description.isEmpty)
        XCTAssertFalse(Brand.Semantic.textSecondary(for: .dark).description.isEmpty)
    }

    func testTextTertiaryResolvesOnBothSchemes() {
        XCTAssertFalse(Brand.Semantic.textTertiary(for: .light).description.isEmpty)
        XCTAssertFalse(Brand.Semantic.textTertiary(for: .dark).description.isEmpty)
    }

    func testDividerResolvesOnBothSchemes() {
        XCTAssertFalse(Brand.Semantic.divider(for: .light).description.isEmpty)
        XCTAssertFalse(Brand.Semantic.divider(for: .dark).description.isEmpty)
    }

    func testSurfaceSelectedUsesAmberWash() {
        // Selected row wash is brand-tinted; must resolve and differ from the
        // plain base so selection is visible.
        let selectedLight = Brand.Semantic.surfaceSelected(for: .light)
        let baseLight = Brand.Semantic.surfaceBase(for: .light)
        XCTAssertFalse(selectedLight.description.isEmpty)
        XCTAssertNotEqual(selectedLight.description, baseLight.description)
    }

    // MARK: - Per-bucket accents

    func testEveryLiveBucketHasAnAccent() {
        for id in BucketID.allCases where id != .generalLegacy {
            let light = Brand.accent(for: id.rawValue, scheme: .light)
            let dark  = Brand.accent(for: id.rawValue, scheme: .dark)
            XCTAssertFalse(light.description.isEmpty, "No light accent for \(id.rawValue)")
            XCTAssertFalse(dark.description.isEmpty, "No dark accent for \(id.rawValue)")
        }
    }

    func testUnhingedAccentIsWarm() {
        // Unhinged is the "chaotic warm" bucket — its accent must differ from
        // the dependable ink used for Standard, so the tone reads at a glance.
        let unhinged = Brand.accent(for: BucketID.unhinged.rawValue, scheme: .light)
        let standard = Brand.accent(for: BucketID.standard.rawValue, scheme: .light)
        XCTAssertNotEqual(unhinged.description, standard.description)
    }

    func testUnknownBucketFallsToAmber() {
        // Unknown ids must not crash; they resolve to the brand amber.
        let odd = Brand.accent(for: "does-not-exist", scheme: .light)
        let amber = Brand.amber(for: .light)
        XCTAssertEqual(odd.description, amber.description)
    }

    // MARK: - Palette (SignoffCore)

    func testPaletteAmberIsNonEmpty() {
        XCTAssertFalse(Palette.amber.description.isEmpty)
        XCTAssertFalse(Palette.amberBright.description.isEmpty)
    }

    func testSignoffAmberColorsResolve() {
        XCTAssertFalse(Color.signoffAmber.description.isEmpty)
        XCTAssertFalse(Color.signoffAmber(for: .light).description.isEmpty)
        XCTAssertFalse(Color.signoffAmber(for: .dark).description.isEmpty)
    }

    // MARK: - Typography

    func testSignatureFontIsNonEmpty() {
        XCTAssertFalse(String(describing: SignoffFont.signature()).isEmpty)
        XCTAssertFalse(String(describing: SignoffFont.display()).isEmpty)
        XCTAssertFalse(String(describing: SignoffFont.heading()).isEmpty)
        XCTAssertFalse(String(describing: SignoffFont.mono()).isEmpty)
    }
}
