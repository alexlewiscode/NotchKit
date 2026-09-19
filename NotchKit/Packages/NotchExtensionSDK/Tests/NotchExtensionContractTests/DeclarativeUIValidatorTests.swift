import Foundation
import NotchExtensionSDK
import XCTest

final class DeclarativeUIValidatorTests: XCTestCase {
    func testValidTreeRoundTripsAndValidates() throws {
        let tree = makeValidTree()
        try DeclarativeUIValidator.validate(tree)
        let data = try JSONEncoder().encode(tree)
        XCTAssertEqual(try JSONDecoder().decode(DeclarativeUITree.self, from: data), tree)
    }

    func testEveryComponentRoundTrips() throws {
        let components: [DeclarativeUIComponent] = [
            .text("Text"),
            .symbol(systemName: "star"),
            .image(resourceName: "hero"),
            .spacer(minLength: 8),
            .divider,
            .progress(value: 0.5),
            .hStack(spacing: 4, children: []),
            .vStack(spacing: nil, children: []),
            .button(actionID: "tap", label: .init(id: "button-label", component: .text("Tap"))),
            .toggle(actionID: "toggle", isOn: true, label: .init(id: "toggle-label", component: .text("On")))
        ]
        for (index, component) in components.enumerated() {
            let node = DeclarativeUINode(
                id: "node-\(index)",
                component: component,
                accessibility: needsAccessibility(index) ? .init(label: "Image") : nil
            )
            let data = try JSONEncoder().encode(node)
            XCTAssertEqual(try JSONDecoder().decode(DeclarativeUINode.self, from: data), node)
        }
    }

    func testRejectsDuplicateStableIDs() {
        let tree = DeclarativeUITree(root: .init(
            id: "root",
            component: .vStack(spacing: nil, children: [
                .init(id: "same", component: .text("One")),
                .init(id: "same", component: .text("Two"))
            ])
        ))
        assertValidationError(tree, equals: .duplicateNodeID("same"))
    }

    func testRejectsEmptyStableID() {
        assertValidationError(
            DeclarativeUITree(root: .init(id: "  ", component: .text("Text"))),
            equals: .emptyNodeID
        )
    }

    func testAllowsExactlyOneHundredNodes() throws {
        let children = (1..<100).map { DeclarativeUINode(id: "n\($0)", component: .text("x")) }
        try DeclarativeUIValidator.validate(DeclarativeUITree(
            root: .init(id: "root", component: .vStack(spacing: nil, children: children))
        ))
    }

    func testRejectsMoreThanOneHundredNodes() {
        let children = (1...100).map { DeclarativeUINode(id: "n\($0)", component: .text("x")) }
        assertValidationError(
            DeclarativeUITree(root: .init(id: "root", component: .vStack(spacing: nil, children: children))),
            equals: .nodeCountExceeded(actual: 101, maximum: 100)
        )
    }

    func testAllowsDepthTen() throws {
        try DeclarativeUIValidator.validate(DeclarativeUITree(root: nestedNode(depth: 10)))
    }

    func testRejectsDepthEleven() {
        assertValidationError(
            DeclarativeUITree(root: nestedNode(depth: 11)),
            equals: .depthExceeded(actual: 11, maximum: 10)
        )
    }

    func testRejectsDocumentLargerThan64KiB() {
        let tree = DeclarativeUITree(root: .init(
            id: "large",
            component: .text(String(repeating: "x", count: 66_000))
        ))
        XCTAssertThrowsError(try DeclarativeUIValidator.validate(tree)) { error in
            guard case let DeclarativeUIValidationError.encodedSizeExceeded(actual, maximum) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertGreaterThan(actual, 64 * 1024)
            XCTAssertEqual(maximum, 64 * 1024)
        }
    }

    func testRequiresLabelsForVisibleSymbolsAndImages() {
        let symbol = DeclarativeUITree(root: .init(id: "symbol", component: .symbol(systemName: "star")))
        assertValidationError(symbol, equals: .missingAccessibilityLabel(nodeID: "symbol"))

        let hiddenImage = DeclarativeUITree(root: .init(
            id: "image",
            component: .image(resourceName: "decoration"),
            accessibility: .init(hidden: true)
        ))
        XCTAssertNoThrow(try DeclarativeUIValidator.validate(hiddenImage))
    }

    func testAcceptsNormalizedRelativeImageResourcePaths() throws {
        let tree = DeclarativeUITree(root: .init(
            id: "image",
            component: .image(resourceName: "images/status/icon.png"),
            accessibility: .init(label: "Status")
        ))
        try DeclarativeUIValidator.validate(tree)

        let maximumLength = DeclarativeUITree(root: .init(
            id: "maximum",
            component: .image(resourceName: String(repeating: "a", count: 512)),
            accessibility: .init(label: "Maximum")
        ))
        try DeclarativeUIValidator.validate(maximumLength)
    }

    func testRejectsUnsafeImageResourcePaths() {
        let paths = [
            "",
            "/images/icon.png",
            "images\\icon.png",
            "images//icon.png",
            "./icon.png",
            "images/./icon.png",
            "../icon.png",
            "images/../icon.png",
            "images/icon.png\0ignored",
            "~/images/icon.png",
            "images/~private/icon.png",
            "C:/images/icon.png",
            "images/D:/icon.png",
            String(repeating: "a", count: 513)
        ]

        for path in paths {
            let tree = DeclarativeUITree(root: .init(
                id: "image",
                component: .image(resourceName: path),
                accessibility: .init(label: "Image")
            ))
            assertValidationError(
                tree,
                equals: .invalidImageResourceName(nodeID: "image")
            )
        }
    }

    func testInteractiveControlUsesVisibleTextLabel() throws {
        let tree = DeclarativeUITree(root: .init(
            id: "button",
            component: .button(
                actionID: "save",
                label: .init(id: "label", component: .text("Save"))
            )
        ))
        try DeclarativeUIValidator.validate(tree)
    }

    func testRejectsUnlabelledOrHiddenInteractiveControl() {
        let unlabelled = DeclarativeUITree(root: .init(
            id: "button",
            component: .button(actionID: "go", label: .init(id: "space", component: .spacer(minLength: nil)))
        ))
        assertValidationError(unlabelled, equals: .missingAccessibilityLabel(nodeID: "button"))

        let hidden = DeclarativeUITree(root: .init(
            id: "toggle",
            component: .toggle(
                actionID: "change",
                isOn: false,
                label: .init(id: "label", component: .text("Change"))
            ),
            accessibility: .init(hidden: true)
        ))
        assertValidationError(hidden, equals: .invalidAccessibility(nodeID: "toggle"))
    }

    func testRejectsEmptyActionAndAccessibilityValues() {
        let action = DeclarativeUITree(root: .init(
            id: "button",
            component: .button(actionID: " ", label: .init(id: "label", component: .text("Tap")))
        ))
        assertValidationError(action, equals: .invalidActionID(nodeID: "button"))

        let accessibility = DeclarativeUITree(root: .init(
            id: "text",
            component: .text("Text"),
            accessibility: .init(hint: " ")
        ))
        assertValidationError(accessibility, equals: .invalidAccessibility(nodeID: "text"))
    }

    func testRejectsOutOfRangeProgress() {
        let tree = DeclarativeUITree(root: .init(id: "progress", component: .progress(value: 1.1)))
        assertValidationError(tree, equals: .invalidProgress(nodeID: "progress"))
    }

    private func makeValidTree() -> DeclarativeUITree {
        DeclarativeUITree(root: .init(
            id: "root",
            component: .vStack(spacing: 8, children: [
                .init(id: "title", component: .text("Timer")),
                .init(
                    id: "status",
                    component: .symbol(systemName: "timer"),
                    accessibility: .init(label: "Timer running")
                ),
                .init(id: "progress", component: .progress(value: 0.25)),
                .init(
                    id: "pause",
                    component: .button(
                        actionID: "pause",
                        label: .init(id: "pause-label", component: .text("Pause"))
                    )
                )
            ])
        ))
    }

    private func nestedNode(depth: Int) -> DeclarativeUINode {
        guard depth > 1 else { return .init(id: "depth-1", component: .text("Leaf")) }
        return .init(
            id: "depth-\(depth)",
            component: .vStack(spacing: nil, children: [nestedNode(depth: depth - 1)])
        )
    }

    private func needsAccessibility(_ index: Int) -> Bool {
        index == 1 || index == 2
    }

    private func assertValidationError(
        _ tree: DeclarativeUITree,
        equals expected: DeclarativeUIValidationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try DeclarativeUIValidator.validate(tree), file: file, line: line) { error in
            XCTAssertEqual(error as? DeclarativeUIValidationError, expected, file: file, line: line)
        }
    }
}
