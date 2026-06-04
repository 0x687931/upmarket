import SwiftUI
import QuartzCore
import AppKit

/// Animated version of the Upmarket icon.
/// Plays a looping conversion animation: amber doc shrinks → arrow travels → markdown swells.
/// Used in the shelf header and Dock tile during conversion.
struct ConversionIconView: View {

    let isAnimating: Bool
    var size: CGFloat = 64

    var body: some View {
        ConversionIconNSView(isAnimating: isAnimating)
            .frame(width: size, height: size)
    }
}

// MARK: - NSViewRepresentable wrapper

struct ConversionIconNSView: NSViewRepresentable {
    let isAnimating: Bool

    func makeNSView(context: Context) -> ConversionIconLayerView {
        ConversionIconLayerView()
    }

    func updateNSView(_ view: ConversionIconLayerView, context: Context) {
        if isAnimating {
            view.startAnimation()
        } else {
            view.stopAnimation()
        }
    }
}

// MARK: - The actual animated view

final class ConversionIconLayerView: NSView {

    private var tileLayer      = CALayer()
    private var glowLayer      = CALayer()
    private var inputDocLayer  = CALayer()
    private var arrowLayer     = CALayer()
    private var outputDocLayer = CALayer()
    private var hashLayer      = CALayer()

    private var isRunning = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // Load the icon SVGs as images for each layer
        // Each layer gets the correct portion of the composition
        let _ : [(CALayer, String)] = [
            (tileLayer,      "icon_layer_tile"),
            (glowLayer,      "icon_layer_glow"),
            (inputDocLayer,  "icon_layer_input"),
            (arrowLayer,     "icon_layer_arrow"),
            (outputDocLayer, "icon_layer_output"),
            (hashLayer,      "icon_layer_hash"),
        ]

        // For now, use the full composed icon as a single layer
        // and animate the whole thing. Individual layer animation
        // requires separate SVG assets per layer.
        tileLayer.frame = bounds
        tileLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        if let img = NSImage(named: "AppIcon") {
            tileLayer.contents = img
        }

        layer?.addSublayer(tileLayer)

        // Individual animatable sublayers — positioned over the base
        for (l, _) in [(inputDocLayer, ""), (arrowLayer, ""), (outputDocLayer, ""), (hashLayer, "")] {
            l.backgroundColor = NSColor.clear.cgColor
            layer?.addSublayer(l)
        }

        layoutLayers()
    }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    private func layoutLayers() {
        let s = bounds.width

        // Base icon fills entire view
        tileLayer.frame = bounds

        // Input document: left ~20%, vertically centred low
        inputDocLayer.frame = CGRect(x: s*0.20, y: s*0.37, width: s*0.22, height: s*0.30)

        // Arrow: centre
        arrowLayer.frame = CGRect(x: s*0.43, y: s*0.46, width: s*0.13, height: s*0.07)

        // Output document: right, taller
        outputDocLayer.frame = CGRect(x: s*0.53, y: s*0.27, width: s*0.30, height: s*0.43)

        // Hash: on output doc
        hashLayer.frame = CGRect(x: s*0.63, y: s*0.40, width: s*0.15, height: s*0.17)
    }

    // MARK: - Animation

    func startAnimation() {
        guard !isRunning else { return }
        isRunning = true
        playConversionLoop()
    }

    func stopAnimation() {
        isRunning = false
        removeAllAnimations()
        // Reset to resting state
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        inputDocLayer.transform  = CATransform3DIdentity
        arrowLayer.transform     = CATransform3DIdentity
        outputDocLayer.transform = CATransform3DIdentity
        hashLayer.opacity        = 1.0
        CATransaction.commit()
    }

    private func removeAllAnimations() {
        for layer in [inputDocLayer, arrowLayer, outputDocLayer, hashLayer, glowLayer] {
            layer.removeAllAnimations()
        }
    }

    private func playConversionLoop() {
        guard isRunning else { return }

        let duration: CFTimeInterval = 2.0
        let now = CACurrentMediaTime()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Reset to start state
        inputDocLayer.transform  = CATransform3DIdentity
        arrowLayer.transform     = CATransform3DMakeTranslation(-bounds.width * 0.06, 0, 0)
        arrowLayer.opacity       = 0
        outputDocLayer.transform = CATransform3DMakeScale(0.88, 0.88, 1)
        hashLayer.opacity        = 0

        CATransaction.commit()

        // Phase 1 (0.0→0.5s): Input doc shrinks
        animate(layer: inputDocLayer, keyPath: "transform.scale", values: [1.0, 0.78, 0.72],
                keyTimes: [0, 0.35, 0.5], duration: duration, beginTime: now)

        // Phase 2 (0.3→0.9s): Arrow travels right and fades
        animate(layer: arrowLayer, keyPath: "opacity", values: [0, 0, 1.0, 1.0, 0],
                keyTimes: [0, 0.15, 0.3, 0.7, 0.9], duration: duration, beginTime: now)
        animate(layer: arrowLayer, keyPath: "transform.translation.x",
                values: [Float(-bounds.width * 0.06), Float(-bounds.width * 0.06),
                         0, Float(bounds.width * 0.06), Float(bounds.width * 0.1)],
                keyTimes: [0, 0.15, 0.45, 0.75, 0.9], duration: duration, beginTime: now)

        // Phase 3 (0.55→1.0s): Output doc swells, hash appears
        animate(layer: outputDocLayer, keyPath: "transform.scale",
                values: [0.88, 0.88, 0.94, 1.02, 1.0],
                keyTimes: [0, 0.4, 0.6, 0.85, 1.0], duration: duration, beginTime: now)

        animate(layer: hashLayer, keyPath: "opacity", values: [0, 0, 0, 0.6, 1.0],
                keyTimes: [0, 0.45, 0.6, 0.8, 1.0], duration: duration, beginTime: now)

        // Schedule next loop
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.15) { [weak self] in
            self?.playConversionLoop()
        }
    }

    private func animate(layer: CALayer, keyPath: String, values: [Any],
                         keyTimes: [NSNumber], duration: CFTimeInterval, beginTime: CFTimeInterval) {
        let anim = CAKeyframeAnimation(keyPath: keyPath)
        anim.values = values
        anim.keyTimes = keyTimes
        anim.duration = duration
        anim.beginTime = beginTime
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        anim.timingFunctions = (0..<(values.count-1)).map { _ in
            CAMediaTimingFunction(name: .easeInEaseOut)
        }
        layer.add(anim, forKey: keyPath)
    }
}

// MARK: - Dock progress bar

extension ConversionIconLayerView {

    private static let progressTrackHeight: CGFloat = 8
    private static let progressTrackInset: CGFloat  = 6

    func setProgress(_ fraction: Double) {
        let w = bounds.width
        let inset = Self.progressTrackInset
        let barH  = Self.progressTrackHeight
        let trackW = w - inset * 2
        let y: CGFloat = 2

        if progressTrackLayer.superlayer == nil {
            progressTrackLayer.cornerRadius = barH / 2
            progressTrackLayer.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
            layer?.addSublayer(progressTrackLayer)

            progressFillLayer.cornerRadius = barH / 2
            progressFillLayer.backgroundColor = NSColor.white.cgColor
            progressFillLayer.shadowColor = NSColor.white.cgColor
            progressFillLayer.shadowOpacity = 0.5
            progressFillLayer.shadowRadius = 3
            progressFillLayer.shadowOffset = .zero
            layer?.addSublayer(progressFillLayer)
        }

        progressTrackLayer.frame = CGRect(x: inset, y: y, width: trackW, height: barH)

        let fillW = max(barH, trackW * CGFloat(fraction))
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        progressFillLayer.frame = CGRect(x: inset, y: y, width: fillW, height: barH)
        CATransaction.commit()
    }

    func removeProgress() {
        progressTrackLayer.removeFromSuperlayer()
        progressFillLayer.removeFromSuperlayer()
    }
}

// MARK: - Dock tile integration

private var progressTrackKey: UInt8 = 0
private var progressFillKey:  UInt8 = 1

extension ConversionIconLayerView {

    fileprivate var progressTrackLayer: CALayer {
        if let l = objc_getAssociatedObject(self, &progressTrackKey) as? CALayer { return l }
        let l = CALayer()
        objc_setAssociatedObject(self, &progressTrackKey, l, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return l
    }

    fileprivate var progressFillLayer: CALayer {
        if let l = objc_getAssociatedObject(self, &progressFillKey) as? CALayer { return l }
        let l = CALayer()
        objc_setAssociatedObject(self, &progressFillKey, l, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return l
    }

    /// The shared dock tile view — retained for the lifetime of a conversion.
    private static var activeDockView: ConversionIconLayerView?

    static func startDockAnimation() {
        let view = ConversionIconLayerView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        view.startAnimation()
        activeDockView = view
        NSApp.dockTile.contentView = view
        NSApp.dockTile.display()
    }

    static func stopDockAnimation() {
        activeDockView?.removeProgress()
        activeDockView = nil
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.display()
    }

    static func updateDockProgress(_ fraction: Double) {
        guard let view = activeDockView else { return }
        view.setProgress(fraction)
        NSApp.dockTile.display()
    }
}
