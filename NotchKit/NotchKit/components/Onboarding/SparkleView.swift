//
//  SparkleView.swift
//  NotchKit
//
//  Created by Richard Kunkli on 2024. 09. 26..
//

import SwiftUI
import AppKit

final class SparkleNSView: NSView {
    private var emitterLayer: CAEmitterLayer?
    private var isEnabled: Bool
    
    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
        super.init(frame: .zero)
        self.wantsLayer = true
        setupEmitterLayer()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupEmitterLayer() {
        let emitterLayer = CAEmitterLayer()
        emitterLayer.emitterShape = .rectangle
        emitterLayer.emitterMode = .surface
        emitterLayer.renderMode = .oldestFirst
        
        let cell = CAEmitterCell()
        cell.contents = NSImage(named: "sparkle")?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        cell.birthRate = isEnabled ? 20 : 0
        cell.lifetime = 5
        cell.velocity = 10
        cell.velocityRange = 5
        cell.emissionRange = .pi * 2
        cell.scale = 0.2
        cell.scaleRange = 0.1
        cell.alphaSpeed = -0.5
        cell.yAcceleration = 10
        
        emitterLayer.emitterCells = [cell]
        
        self.layer?.addSublayer(emitterLayer)
        self.emitterLayer = emitterLayer
        
        updateEmitterForCurrentBounds()
    }
    
    private func updateEmitterForCurrentBounds() {
        guard let emitterLayer = self.emitterLayer else { return }
        
        emitterLayer.frame = self.bounds
        emitterLayer.emitterSize = self.bounds.size
        emitterLayer.emitterPosition = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        
        emitterLayer.emitterCells?.first?.birthRate = isEnabled ? 20 : 0
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateEmitterForCurrentBounds()
    }

    func setParticlesEnabled(_ isEnabled: Bool) {
        guard self.isEnabled != isEnabled else { return }
        self.isEnabled = isEnabled
        emitterLayer?.emitterCells?.first?.birthRate = isEnabled ? 20 : 0
    }
}

struct SparkleView: NSViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isEnabled = true

    func makeNSView(context: Context) -> SparkleNSView {
        SparkleNSView(isEnabled: isEnabled && !reduceMotion)
    }
    
    func updateNSView(_ nsView: SparkleNSView, context: Context) {
        nsView.setParticlesEnabled(isEnabled && !reduceMotion)
    }
}
