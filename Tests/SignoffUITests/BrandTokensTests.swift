import XCTest
import SwiftUI
@testable import SignoffUI
@testable import SignoffCore

/// Verifies the `Brand` design-token surface in `Sources/SignoffUI/Components/Brand.swift`.
///
/// Post-consolidation: the old `Brand.Semantic`, `Brand.amber`, `Palette.amber`,
/// and `Color.signoffAmber` APIs were retired in favor of `Brand.ember`,
/// `Brand.Surface`, and `Brand.Ink`. These tests exercise the tokens that
/// actually ship, including the per-scheme surface/text colors, the ember
/// accent, layout tokens, and per-bucket accent mapping.
final class BrandTokensTests: XCTestCase {

    // MARK: - Brand accent

    func testBrandEmberResolvesOnBothSchemes() {
        XCTAssertFalse(Brand.ember(for: .light).description.isEmpty)
        XCTAssertFalse(Brand.ember(for: .dark).description.isEmpty)
    }

    func testBrandEmberDiffersBetweenSchemes() {
        // Light ember is muted; dark ember is bright — must not be identical so
        // the accent stays readable on both paper and ink.
        XCTAssertNotEqual(Brand.ember(for: .light).description,
                          Brand.ember(for: .dark).description)
    }

    // MARK: - Layout

    func testCornerRadiusIsReasonable() {
        // Brand.Layout now uses continuous radius scale; radiusM is the default card radius.
        XCTAssertGreaterThan(Brand.Layout.radiusM, 0)
        XCTAssertLessThanOrEqual(Brand.Layout.radiusM, 16)
    }

    func testControlCornerRadiusSmallerThan() {
        // Tighter radius for controls should be <= card radius.
        XCTAssertLessThanOrEqual(Brand.Layout.radiusXS,
                                 Brand.Layout.radiusM)
    }

    func testHairlineIsThinAndPositive() {
        XCTAssertGreaterThan(Brand.Layout.hairline, 0)
        XCTAssertLessThan(Brand.Layout.hairline, 1.0)
    }

    func testLayoutUnitIsPositive() {
        XCTAssertGreaterThan(Brand.Layout.unit, 0)
    }

    // MARK: - Surfaces (ColorScheme-aware)

    func testSurfacePageDiffersBetweenSchemes() {
        let light = Brand.Surface.page(for: .light)
        let dark  = Brand.Surface.page(for: .dark)
        XCTAssertNotEqual(light.description, dark.description,
                          "Paper (light) and ink (dark) must differ")
    }

    func testSurfaceRaisedResolvesOnBothSchemes() {
        XCTAssertFalse(Brand.Surface.raised(for: .light).description.isEmpty)
        XCTAssertFalse(Brand.Surface.raised(for: .dark).description.isEmpty)
    }

    func testSurfaceCardResolvesOnBothSchemes() {
        XCTAssertFalse(Brand.Surface.card(for: .light).description.isEmpty)
        XCTAssertFalse(Brand.Surface.card(for: .dark).description.isEmpty)
    }

    func testTextPrimaryResolvesOnBothSchemes() {
        XCTAssertFalse(Brand.Ink.primary(for: .light).description.isEmpty)
        XCTAssertFalse(Brand.Ink.primary(for: .dark).description.isEmpty)
    }

    func testTextSecondaryResolvesOnBothSchemes() {
        XCTAssertFalse(Brand.Ink.secondary(for: .light).description.isEmpty)
        XCTAssertFalse(Brand.Ink.secondary(for: .dark).description.isEmpty)
    }

    func testTextTertiaryResolvesOnBothSchemes() {
        XCTAssertFalse(Brand.Ink.tertiary(for: .light).description.isEmpty)
        XCTAssertFalse(Brand.Ink.tertiary(for: .dark).description.isEmpty)
    }

    func testDividerResolvesOnBothSchemes() {
        XCTAssertFalse(Brand.Surface.divider(for: .light).description.isEmpty)
        XCTAssertFalse(Brand.Surface.divider(for: .dark).description.isEmpty)
    }

    // MARK: - Tint wash (replaces old surfaceSelected)

    func testSurfaceTintDiffersFromBase() {
        // The amber-tinted wash should visibly differ from the plain page.
        let tintedLight = Brand.Surface.tint(for: .light, opacity: 0.12)
        let baseLight   = Brand.Surface.page(for: .light)
        XCTAssertFalse(tintedLight.description.isEmpty)
        XCTAssertNotEqual(tintedLight.description, baseLight.description)
    }

    func testSurfaceTintForDarkIsNonEmpty() {
        XCTAssertFalse(Brand.Surface.tint(for: .dark, opacity: 0.16).description.isEmpty)
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

    func testUnknownBucketFallsToEmber() {
        // Unknown ids must not crash; they resolve to the brand ember.
        let odd   = Brand.accent(for: "does-not-exist", scheme: .light)
        let amber = Brand.ember(for: .light)
        XCTAssertEqual(odd.description, amber.description)
    }

    // MARK: - Brand ember accent properties

    func testBrandEmberConstantsAreNonEmpty() {
        // Brand.ember is defined from the private Palette — verify the public
        // tokens map out.
        XCTAssertFalse(Brand.ember.description.isEmpty)
        XCTAssertFalse(Brand.emberBright.description.isEmpty)
        XCTAssertFalse(Brand.emberDim.description.isEmpty)
    }

    func testEmberHelperResolvesOnBothSchemes() {
        XCTAssertFalse(Brand.ember(for: .light).description.isEmpty)
        XCTAssertFalse(Brand.ember(for: .dark).description.isEmpty)
    }

    // MARK: - Typography (SignoffFont)

    func testSignatureFontIsNonEmpty() {
        XCTAssertFalse(String(describing: SignoffFont.signature()).isEmpty)
        XCTAssertFalse(String(describing: SignoffFont.display()).isEmpty)
        XCTAssertFalse(String(describing: SignoffFont.heading()).isEmpty)
        XCTAssertFalse(String(describing: SignoffFont.mono()).isEmpty)
    }
}