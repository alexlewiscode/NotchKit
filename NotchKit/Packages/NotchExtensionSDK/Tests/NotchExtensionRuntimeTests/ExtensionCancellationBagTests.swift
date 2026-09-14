//
//  ExtensionCancellationBagTests.swift
//  NotchExtensionRuntimeTests
//

import XCTest
import NotchExtensionSDK

@MainActor
final class ExtensionCancellationBagTests: XCTestCase {
    func testRunsTeardownsOnceInReverseOrder() {
        let bag = ExtensionCancellationBag()
        var order: [Int] = []
        bag.add { order.append(1) }
        bag.add { order.append(2) }
        bag.cancelAll()
        bag.cancelAll()
        XCTAssertEqual(order, [2, 1])
        XCTAssertTrue(bag.isCancelled)
    }

    func testAddAfterCancelRunsImmediately() {
        let bag = ExtensionCancellationBag()
        bag.cancelAll()
        var ran = false
        bag.add { ran = true }
        XCTAssertTrue(ran)
    }

    func testCancelsRegisteredTask() async {
        let bag = ExtensionCancellationBag()
        let task = Task { _ = try? await Task.sleep(for: .seconds(10)) }
        bag.add(task)
        bag.cancelAll()
        _ = await task.result
        XCTAssertTrue(task.isCancelled)
    }

    func testInvalidatesRegisteredTimer() {
        let bag = ExtensionCancellationBag()
        let timer = Timer(timeInterval: 100, repeats: true) { _ in }
        bag.add(timer)
        bag.cancelAll()
        XCTAssertFalse(timer.isValid)
    }

    func testRemovesNotificationObserver() {
        let bag = ExtensionCancellationBag()
        let center = NotificationCenter()
        let token = center.addObserver(
            forName: Notification.Name("test"), object: nil, queue: nil
        ) { _ in }
        bag.add(observer: token, center: center)
        bag.cancelAll()
        center.post(name: Notification.Name("test"), object: nil)
    }
}
