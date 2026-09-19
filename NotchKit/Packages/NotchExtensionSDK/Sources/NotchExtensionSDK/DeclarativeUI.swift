//
//  DeclarativeUI.swift
//  NotchExtensionSDK
//

import Foundation

/// A host-rendered UI document. It contains data only and has no dependency on
/// SwiftUI or AppKit.
public struct DeclarativeUITree: Codable, Hashable, Sendable {
    public let root: DeclarativeUINode

    public init(root: DeclarativeUINode) {
        self.root = root
    }
}

/// Accessibility information interpreted by the host renderer.
public struct DeclarativeAccessibility: Codable, Hashable, Sendable {
    public let label: String?
    public let hint: String?
    public let value: String?
    public let hidden: Bool

    public init(
        label: String? = nil,
        hint: String? = nil,
        value: String? = nil,
        hidden: Bool = false
    ) {
        self.label = label
        self.hint = hint
        self.value = value
        self.hidden = hidden
    }
}

/// One stable, addressable node in a declarative UI tree.
public struct DeclarativeUINode: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let component: DeclarativeUIComponent
    public let accessibility: DeclarativeAccessibility?

    public init(
        id: String,
        component: DeclarativeUIComponent,
        accessibility: DeclarativeAccessibility? = nil
    ) {
        self.id = id
        self.component = component
        self.accessibility = accessibility
    }
}

/// The complete and intentionally finite host-rendered component vocabulary.
public indirect enum DeclarativeUIComponent: Hashable, Sendable {
    case text(String)
    case symbol(systemName: String)
    case image(resourceName: String)
    case spacer(minLength: Double?)
    case divider
    case progress(value: Double?)
    case hStack(spacing: Double?, children: [DeclarativeUINode])
    case vStack(spacing: Double?, children: [DeclarativeUINode])
    case button(actionID: String, label: DeclarativeUINode)
    case toggle(actionID: String, isOn: Bool, label: DeclarativeUINode)
}

extension DeclarativeUIComponent: Codable {
    private enum ComponentType: String, Codable {
        case text, symbol, image, spacer, divider, progress, hstack, vstack, button, toggle
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, systemName, resourceName, minLength, value, spacing, children
        case actionID, isOn, label
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ComponentType.self, forKey: .type) {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .symbol:
            self = .symbol(systemName: try container.decode(String.self, forKey: .systemName))
        case .image:
            self = .image(resourceName: try container.decode(String.self, forKey: .resourceName))
        case .spacer:
            self = .spacer(minLength: try container.decodeIfPresent(Double.self, forKey: .minLength))
        case .divider:
            self = .divider
        case .progress:
            self = .progress(value: try container.decodeIfPresent(Double.self, forKey: .value))
        case .hstack:
            self = .hStack(
                spacing: try container.decodeIfPresent(Double.self, forKey: .spacing),
                children: try container.decode([DeclarativeUINode].self, forKey: .children)
            )
        case .vstack:
            self = .vStack(
                spacing: try container.decodeIfPresent(Double.self, forKey: .spacing),
                children: try container.decode([DeclarativeUINode].self, forKey: .children)
            )
        case .button:
            self = .button(
                actionID: try container.decode(String.self, forKey: .actionID),
                label: try container.decode(DeclarativeUINode.self, forKey: .label)
            )
        case .toggle:
            self = .toggle(
                actionID: try container.decode(String.self, forKey: .actionID),
                isOn: try container.decode(Bool.self, forKey: .isOn),
                label: try container.decode(DeclarativeUINode.self, forKey: .label)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode(ComponentType.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case let .symbol(systemName):
            try container.encode(ComponentType.symbol, forKey: .type)
            try container.encode(systemName, forKey: .systemName)
        case let .image(resourceName):
            try container.encode(ComponentType.image, forKey: .type)
            try container.encode(resourceName, forKey: .resourceName)
        case let .spacer(minLength):
            try container.encode(ComponentType.spacer, forKey: .type)
            try container.encodeIfPresent(minLength, forKey: .minLength)
        case .divider:
            try container.encode(ComponentType.divider, forKey: .type)
        case let .progress(value):
            try container.encode(ComponentType.progress, forKey: .type)
            try container.encodeIfPresent(value, forKey: .value)
        case let .hStack(spacing, children):
            try container.encode(ComponentType.hstack, forKey: .type)
            try container.encodeIfPresent(spacing, forKey: .spacing)
            try container.encode(children, forKey: .children)
        case let .vStack(spacing, children):
            try container.encode(ComponentType.vstack, forKey: .type)
            try container.encodeIfPresent(spacing, forKey: .spacing)
            try container.encode(children, forKey: .children)
        case let .button(actionID, label):
            try container.encode(ComponentType.button, forKey: .type)
            try container.encode(actionID, forKey: .actionID)
            try container.encode(label, forKey: .label)
        case let .toggle(actionID, isOn, label):
            try container.encode(ComponentType.toggle, forKey: .type)
            try container.encode(actionID, forKey: .actionID)
            try container.encode(isOn, forKey: .isOn)
            try container.encode(label, forKey: .label)
        }
    }
}

public enum DeclarativeUIValidationError: Error, Equatable, LocalizedError {
    case encodedSizeExceeded(actual: Int, maximum: Int)
    case nodeCountExceeded(actual: Int, maximum: Int)
    case depthExceeded(actual: Int, maximum: Int)
    case emptyNodeID
    case duplicateNodeID(String)
    case emptyValue(nodeID: String)
    case invalidProgress(nodeID: String)
    case invalidImageResourceName(nodeID: String)
    case invalidAccessibility(nodeID: String)
    case missingAccessibilityLabel(nodeID: String)
    case invalidActionID(nodeID: String)

    public var errorDescription: String? {
        switch self {
        case let .encodedSizeExceeded(actual, maximum):
            "Declarative UI is \(actual) bytes; maximum is \(maximum)"
        case let .nodeCountExceeded(actual, maximum):
            "Declarative UI has \(actual) nodes; maximum is \(maximum)"
        case let .depthExceeded(actual, maximum):
            "Declarative UI depth is \(actual); maximum is \(maximum)"
        case .emptyNodeID:
            "Declarative UI node identifiers must not be empty"
        case let .duplicateNodeID(id):
            "Declarative UI node identifier is duplicated: \(id)"
        case let .emptyValue(nodeID):
            "Declarative UI node has an empty required value: \(nodeID)"
        case let .invalidProgress(nodeID):
            "Progress must be between zero and one: \(nodeID)"
        case let .invalidImageResourceName(nodeID):
            "Image resource name must be a normalized relative path: \(nodeID)"
        case let .invalidAccessibility(nodeID):
            "Declarative UI node has invalid accessibility metadata: \(nodeID)"
        case let .missingAccessibilityLabel(nodeID):
            "Declarative UI node requires an accessibility label: \(nodeID)"
        case let .invalidActionID(nodeID):
            "Interactive declarative UI node has an empty action identifier: \(nodeID)"
        }
    }
}

/// Enforces transport and renderer limits before a tree is accepted.
public enum DeclarativeUIValidator {
    public static let maximumEncodedSize = 64 * 1024
    public static let maximumNodeCount = 100
    public static let maximumDepth = 10

    public static func validate(_ tree: DeclarativeUITree) throws {
        let encoded = try JSONEncoder().encode(tree)
        guard encoded.count <= maximumEncodedSize else {
            throw DeclarativeUIValidationError.encodedSizeExceeded(
                actual: encoded.count,
                maximum: maximumEncodedSize
            )
        }

        var ids = Set<String>()
        var nodeCount = 0
        try validate(tree.root, depth: 1, ids: &ids, nodeCount: &nodeCount)
    }

    private static func validate(
        _ node: DeclarativeUINode,
        depth: Int,
        ids: inout Set<String>,
        nodeCount: inout Int
    ) throws {
        guard depth <= maximumDepth else {
            throw DeclarativeUIValidationError.depthExceeded(actual: depth, maximum: maximumDepth)
        }
        nodeCount += 1
        guard nodeCount <= maximumNodeCount else {
            throw DeclarativeUIValidationError.nodeCountExceeded(
                actual: nodeCount,
                maximum: maximumNodeCount
            )
        }
        guard !node.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeclarativeUIValidationError.emptyNodeID
        }
        guard ids.insert(node.id).inserted else {
            throw DeclarativeUIValidationError.duplicateNodeID(node.id)
        }
        try validateAccessibility(node)

        switch node.component {
        case let .text(value):
            try requireValue(value, nodeID: node.id)
        case let .symbol(systemName):
            try requireValue(systemName, nodeID: node.id)
            if node.accessibility?.hidden != true {
                guard hasValue(node.accessibility?.label) else {
                    throw DeclarativeUIValidationError.missingAccessibilityLabel(nodeID: node.id)
                }
            }
        case let .image(resourceName):
            try validateImageResourceName(resourceName, nodeID: node.id)
            if node.accessibility?.hidden != true {
                guard hasValue(node.accessibility?.label) else {
                    throw DeclarativeUIValidationError.missingAccessibilityLabel(nodeID: node.id)
                }
            }
        case let .spacer(minLength):
            if let minLength, !minLength.isFinite || minLength < 0 {
                throw DeclarativeUIValidationError.emptyValue(nodeID: node.id)
            }
        case .divider:
            break
        case let .progress(value):
            if let value, !value.isFinite || !(0...1).contains(value) {
                throw DeclarativeUIValidationError.invalidProgress(nodeID: node.id)
            }
        case let .hStack(spacing, children), let .vStack(spacing, children):
            if let spacing, !spacing.isFinite || spacing < 0 {
                throw DeclarativeUIValidationError.emptyValue(nodeID: node.id)
            }
            for child in children {
                try validate(child, depth: depth + 1, ids: &ids, nodeCount: &nodeCount)
            }
        case let .button(actionID, label):
            try validateInteractive(node, actionID: actionID, label: label)
            try validate(label, depth: depth + 1, ids: &ids, nodeCount: &nodeCount)
        case let .toggle(actionID, _, label):
            try validateInteractive(node, actionID: actionID, label: label)
            try validate(label, depth: depth + 1, ids: &ids, nodeCount: &nodeCount)
        }
    }

    private static func validateAccessibility(_ node: DeclarativeUINode) throws {
        guard let accessibility = node.accessibility else { return }
        let supplied = [accessibility.label, accessibility.hint, accessibility.value].compactMap { $0 }
        guard supplied.allSatisfy({ hasValue($0) }) else {
            throw DeclarativeUIValidationError.invalidAccessibility(nodeID: node.id)
        }
    }

    private static func validateInteractive(
        _ node: DeclarativeUINode,
        actionID: String,
        label: DeclarativeUINode
    ) throws {
        guard hasValue(actionID) else {
            throw DeclarativeUIValidationError.invalidActionID(nodeID: node.id)
        }
        guard node.accessibility?.hidden != true else {
            throw DeclarativeUIValidationError.invalidAccessibility(nodeID: node.id)
        }
        guard hasValue(node.accessibility?.label) || hasAccessibleContent(label) else {
            throw DeclarativeUIValidationError.missingAccessibilityLabel(nodeID: node.id)
        }
    }

    private static func hasAccessibleContent(_ node: DeclarativeUINode) -> Bool {
        if node.accessibility?.hidden == true { return false }
        if hasValue(node.accessibility?.label) { return true }
        switch node.component {
        case let .text(value):
            return hasValue(value)
        case let .hStack(_, children), let .vStack(_, children):
            return children.contains(where: hasAccessibleContent)
        default:
            return false
        }
    }

    private static func requireValue(_ value: String, nodeID: String) throws {
        guard hasValue(value) else {
            throw DeclarativeUIValidationError.emptyValue(nodeID: nodeID)
        }
    }

    private static func validateImageResourceName(_ value: String, nodeID: String) throws {
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        let hasDriveComponent = components.contains { component in
            guard component.count >= 2 else { return false }
            let start = component.startIndex
            let second = component.index(after: start)
            return component[start].isASCII && component[start].isLetter && component[second] == ":"
        }
        guard !value.isEmpty,
              value.utf8.count <= 512,
              !value.hasPrefix("/"),
              !value.contains("\\"),
              !value.contains("\0"),
              !value.contains("~"),
              !hasDriveComponent,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            throw DeclarativeUIValidationError.invalidImageResourceName(nodeID: nodeID)
        }
    }

    private static func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
