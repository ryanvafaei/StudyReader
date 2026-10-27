import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Dark-mode look of PDF pages (SPEC F-04): lightness inverted, hues kept. The filters are applied to the layer of
/// the PDF view's document view, so only what is on screen changes; snapshots and covers render from `PDFPage` and
/// never see them.
enum PDFInversion {
    /// True when the appearance best-matches `.darkAqua` and the setting is on.
    static func shouldInvert(appearance: NSAppearance, settingEnabled: Bool) -> Bool {
        settingEnabled && appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// `CIColorInvert` followed by `CIHueAdjust` (angle pi): inverting turns every hue into its complement, rotating
    /// the hue by half a turn turns it back, so only the lightness is inverted.
    static func filters() -> [CIFilter] {
        let invert = CIFilter.colorInvert()
        let hue = CIFilter.hueAdjust()
        hue.angle = .pi
        return [invert, hue]
    }
}

extension PDFReaderController {
    /// Re-evaluates the decision from the view's effective appearance and the setting.
    func refreshInversion() {
        setInverted(PDFInversion.shouldInvert(appearance: pdfView.effectiveAppearance, settingEnabled: invertSettingEnabled))
    }

    /// Called when "Invert PDF colors in dark mode" changes.
    func setInversionEnabled(_ enabled: Bool) {
        invertSettingEnabled = enabled
        refreshInversion()
    }

    /// Applies or removes the filters on the PDF view's document view layer.
    func setInverted(_ inverted: Bool) {
        isInverted = inverted
        applyInversionToDocumentView()
    }

    /// Puts the current state on the document view. PDFKit may replace that view (display mode change, new
    /// document), so this runs again after those.
    func applyInversionToDocumentView() {
        guard let documentView = pdfView.documentView else { return }
        if isInverted {
            documentView.wantsLayer = true
            documentView.layerUsesCoreImageFilters = true
            documentView.layer?.filters = PDFInversion.filters()
        } else {
            documentView.layer?.filters = nil
        }
    }
}
