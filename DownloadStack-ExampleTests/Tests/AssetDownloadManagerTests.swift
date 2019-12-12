//
//  AssetDownloadManagerTests.swift
//  DownloadStack-ExampleTests
//
//  Created by William Boles on 28/01/2018.
//  Copyright © 2018 William Boles. All rights reserved.
//

import XCTest

@testable import DownloadStack_Example

class AssetDownloadManagerTests: XCTestCase {
    
    class NotificationCenterSpy: NotificationCenter {
        
        var addObserverWasCalled = false
        var forNamePassedIn: NSNotification.Name?
        var closurePassedIn: ((Notification) -> Void)?
        
        override func addObserver(forName name: NSNotification.Name?, object obj: Any?, queue: OperationQueue?, using block: @escaping (Notification) -> Void) -> NSObjectProtocol {
            addObserverWasCalled = true
            forNamePassedIn = name
            closurePassedIn = block
            
            return NSObject()
        }
    }
    
    class AssetDownloadItemSpy: AssetDownloadItem {
        
        var hardCancelWasCalled = false
        var resumeWasCalled = false
        
        init() {
            super.init(task: URLSessionDownloadTask())
        }
        
        override func hardCancel() {
            hardCancelWasCalled = true
        }
        
        override func resume() {
            resumeWasCalled = true
        }
    }
    
    class AssetDownloadManagerMock: AssetDownloadManager {
        
        var urlSessionToBeRetuned: URLSessionMock!
        
        override lazy var urlSession: URLSession = {
            return urlSessionToBeRetuned
        }()
    }
    
    class URLSessionMock: URLSession {
        
        var downloadTaskToBeReturned: URLSessionDownloadTaskSpy!
    
        override func downloadTask(with url: URL) -> URLSessionDownloadTask {
            return downloadTaskToBeReturned
        }
    }
    
    // MARK: - Properties

    var urlSessionDownloadTaskSpy: URLSessionDownloadTaskSpy!
    var urlSessionMock: URLSessionMock!
    var assetDownloadManagerMock: AssetDownloadManagerMock!

    // MARK: - Helpers
    
    func assetDownloadItem(forURL url: URL) -> AssetDownloadItem {
        let urlRequest = URLRequest(url: url)
        let urlSessionDownloadTask = URLSessionDownloadTaskSpy()
        urlSessionDownloadTask.currentRequestToBeReturned = urlRequest
        
        return AssetDownloadItem(task: urlSessionDownloadTask)
    }
    
    // MARK: - Lifecycle
    
    override func setUp() {
        super.setUp()
        urlSessionDownloadTaskSpy = URLSessionDownloadTaskSpy()
        urlSessionMock = URLSessionMock()
        urlSessionMock.downloadTaskToBeReturned = urlSessionDownloadTaskSpy
        assetDownloadManagerMock = AssetDownloadManagerMock()
        assetDownloadManagerMock.urlSessionToBeRetuned = urlSessionMock
    }
    
    override func tearDown() {
        AssetDownloadManager.maximumConcurrentDownloadsResetValue = Int.max
        super.tearDown()
    }
    
    // MARK: - Tests
    
    // MARK: Notification
    
    func test_init_notificationRegistration() {
        let notificationCenterSpy = NotificationCenterSpy()
        _ = AssetDownloadManager(notificationCenter: notificationCenterSpy)
        
        XCTAssertTrue(notificationCenterSpy.addObserverWasCalled)
        XCTAssertEqual(notificationCenterSpy.forNamePassedIn, UIApplication.didReceiveMemoryWarningNotification)
        XCTAssertNotNil(notificationCenterSpy.closurePassedIn)
    }
    
    func test_init_notificationTriggeredClearsCanceledItems() {
        let manager = AssetDownloadManager()
        
        let itemA = AssetDownloadItemSpy()
        manager.suspended.append(itemA)
        
        let itemB = AssetDownloadItemSpy()
        manager.suspended.append(itemB)
        
        let itemC = AssetDownloadItemSpy()
        manager.suspended.append(itemC)
        
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        
        XCTAssertTrue(manager.suspended.count == 0)
        XCTAssertTrue(itemA.hardCancelWasCalled)
        XCTAssertTrue(itemB.hardCancelWasCalled)
        XCTAssertTrue(itemC.hardCancelWasCalled)
    }
    
    // MARK: ScheduleDownload
    
    func test_scheduleDownload_schedules() {
        let manager = AssetDownloadManager()
        
        let url = URL(string: "http://test.com")!
        manager.scheduleDownload(url: url, forceDownload: false) { _ in }
        
        XCTAssertTrue(manager.downloading.count == 1)
        XCTAssertTrue(manager.waiting.count == 0)
        XCTAssertTrue(manager.suspended.count == 0)
    }
    
    func test_scheduleDownload_multipleConncurrentDownloads() {
        let manager = AssetDownloadManager()
        
        let urlA = URL(string: "http://testA.com")!
        manager.scheduleDownload(url: urlA, forceDownload: false) { _ in }
        
        let urlB = URL(string: "http://testB.com")!
        manager.scheduleDownload(url: urlB, forceDownload: false) { _ in }
        
        XCTAssertTrue(manager.downloading.count == 2)
        XCTAssertTrue(manager.waiting.count == 0)
        XCTAssertTrue(manager.suspended.count == 0)
    }
    
    func test_scheduleDownload_queuingDownloadsWhenLimitIsMeet() {
        let manager = AssetDownloadManager()
        manager.maximumConcurrentDownloads = 1
        AssetDownloadManager.maximumConcurrentDownloadsResetValue = 1
        
        let urlA = URL(string: "http://testA.com")!
        manager.scheduleDownload(url: urlA, forceDownload: false) { _ in }
        
        let urlB = URL(string: "http://testB.com")!
        manager.scheduleDownload(url: urlB, forceDownload: false) { _ in }
        
        XCTAssertTrue(manager.downloading.count == 1)
        XCTAssertTrue(manager.waiting.count == 1)
        XCTAssertTrue(manager.suspended.count == 0)
    }
    
    func test_scheduleDownload_forceDownload() {
        let manager = AssetDownloadManager()
        let urlA = URL(string: "http://testA.com")!
        manager.scheduleDownload(url: urlA, forceDownload: false) { _ in }
        
        let urlB = URL(string: "http://testB.com")!
        manager.scheduleDownload(url: urlB, forceDownload: false) { _ in }
        
        let urlC = URL(string: "http://testC.com")!
        manager.scheduleDownload(url: urlC, forceDownload: true) { _ in }
        
        XCTAssertTrue(manager.downloading.count == 1)
        XCTAssertTrue(manager.waiting.count == 2)
        XCTAssertTrue(manager.suspended.count == 0)
        
        let item = manager.downloading.last!
        XCTAssertEqual(item.url, urlC)
        XCTAssertTrue(item.forceDownload)
    }
    
    func test_scheduleDownload_coalesceCurrentlyDownloading() {
        let manager = AssetDownloadManager()
        
        let url = URL(string: "http://testA.com")!
        manager.scheduleDownload(url: url, forceDownload: false) { _ in }
        manager.scheduleDownload(url: url, forceDownload: false) { _ in }
        
        XCTAssertTrue(manager.downloading.count == 1)
        XCTAssertTrue(manager.waiting.count == 0)
        XCTAssertTrue(manager.suspended.count == 0)
    }
    
    func test_scheduleDownload_coalesceCurrentlyDownloadingAndForceDownload() {
        let manager = AssetDownloadManager()
        
        let urlA = URL(string: "http://testA.com")!
        manager.scheduleDownload(url: urlA, forceDownload: false) { _ in }
        
        let urlB = URL(string: "http://testB.com")!
        manager.scheduleDownload(url: urlB, forceDownload: false) { _ in }
        manager.scheduleDownload(url: urlB, forceDownload: true) { _ in }
        
        XCTAssertTrue(manager.downloading.count == 1)
        XCTAssertTrue(manager.waiting.count == 1)
        XCTAssertTrue(manager.suspended.count == 0)
        
        let item = manager.downloading.last!
        XCTAssertEqual(item.url, urlB)
        XCTAssertTrue(item.forceDownload)
    }
    
    func test_scheduleDownload_coalesceWaitingDownloading() {
        let manager = AssetDownloadManager()
        
        manager.maximumConcurrentDownloads = 1
        AssetDownloadManager.maximumConcurrentDownloadsResetValue = 1
        
        let urlA = URL(string: "http://testA.com")!
        manager.scheduleDownload(url: urlA, forceDownload: false) { _ in }
        
        let urlB = URL(string: "http://testB.com")!
        manager.scheduleDownload(url: urlB, forceDownload: false) { _ in }
        manager.scheduleDownload(url: urlB, forceDownload: false) { _ in }
        
        XCTAssertTrue(manager.downloading.count == 1)
        XCTAssertTrue(manager.waiting.count == 1)
        XCTAssertTrue(manager.suspended.count == 0)
    }
    
    func test_scheduleDownload_coalesceWaitingDownloadingAndMoveToFront() {
        let manager = AssetDownloadManager()
        
        manager.maximumConcurrentDownloads = 1
        AssetDownloadManager.maximumConcurrentDownloadsResetValue = 1
        
        let urlA = URL(string: "http://testA.com")!
        manager.scheduleDownload(url: urlA, forceDownload: false) { _ in }
        
        let urlB = URL(string: "http://testB.com")!
        manager.scheduleDownload(url: urlB, forceDownload: false) { _ in }
        
        let urlC = URL(string: "http://testC.com")!
        manager.scheduleDownload(url: urlC, forceDownload: false) { _ in }
        
        manager.scheduleDownload(url: urlB, forceDownload: false) { _ in }
        
        XCTAssertTrue(manager.downloading.count == 1)
        XCTAssertTrue(manager.waiting.count == 2)
        XCTAssertTrue(manager.suspended.count == 0)
        
        let item = manager.waiting.last
        XCTAssertEqual(item?.url, urlB)
    }
    
    func test_scheduleDownload_coalesceCurrentlyWaitingAndForceDownload() {
        let manager = AssetDownloadManager()
        
        manager.maximumConcurrentDownloads = 1
        AssetDownloadManager.maximumConcurrentDownloadsResetValue = 1
        
        let itemA = assetDownloadItem(forURL: URL(string: "http://testA.com")!)
        manager.downloading.append(itemA)
        
        let urlB = URL(string: "http://testB.com")!
        let itemB = assetDownloadItem(forURL: urlB)
        manager.waiting.append(itemB)
        
        manager.scheduleDownload(url: urlB, forceDownload: true) { _ in }
        
        XCTAssertTrue(manager.downloading.count == 1)
        XCTAssertTrue(manager.waiting.count == 1)
        XCTAssertTrue(manager.suspended.count == 0)
        
        let item = manager.downloading.last!
        XCTAssertEqual(item.url, urlB)
        XCTAssertTrue(item.forceDownload)
    }
    
    func test_scheduleDownload_resurrectCanceledDownload() {
        let manager = AssetDownloadManager()
        
        let url = URL(string: "http://testA.com")!

        let urlRequest = URLRequest(url: url)
        urlSessionDownloadTaskSpy.currentRequestToBeReturned = urlRequest
        let item = AssetDownloadItem(task: urlSessionDownloadTaskSpy)
        manager.suspended.append(item)
        
        manager.scheduleDownload(url: url, forceDownload: false) { _ in }
        
        XCTAssertTrue(manager.downloading.count == 1)
        XCTAssertTrue(manager.waiting.count == 0)
        XCTAssertTrue(manager.suspended.count == 0)
    }
    
    func test_scheduleDownload_resurrectCanceledDownloadAndForceDownload() {
        let manager = AssetDownloadManager()
        manager.maximumConcurrentDownloads = 1
        AssetDownloadManager.maximumConcurrentDownloadsResetValue = 1
        
        let urlA = URL(string: "http://testA.com")!
        manager.scheduleDownload(url: urlA, forceDownload: false) { _ in }
        
        manager.cancelDownload(url: urlA)
        
        let urlB = URL(string: "http://testB.com")!
        manager.scheduleDownload(url: urlB, forceDownload: false) { _ in }
        
        manager.scheduleDownload(url: urlA, forceDownload: true) { _ in }
        
        XCTAssertTrue(manager.downloading.count == 1)
        XCTAssertTrue(manager.waiting.count == 1)
        XCTAssertTrue(manager.suspended.count == 0)
        
        let item = manager.downloading.last!
        XCTAssertEqual(item.url, urlA)
        XCTAssertTrue(item.forceDownload)
    }
    
    // MARK: Cancel
    
    func test_cancelDownload_cancelDownloadingItem() {
        let manager = AssetDownloadManager()
        
        let urlA = URL(string: "http://testA.com")!
        manager.scheduleDownload(url: urlA, forceDownload: true) { _ in }
        
        manager.cancelDownload(url: urlA)
        
        XCTAssertTrue(manager.downloading.count == 0)
        XCTAssertTrue(manager.waiting.count == 0)
        XCTAssertTrue(manager.suspended.count == 1)
    }
    
    func test_cancelDownload_cancelDownloadingItemResumeWaiting() {
        let manager = AssetDownloadManager()
        manager.maximumConcurrentDownloads = 1
        AssetDownloadManager.maximumConcurrentDownloadsResetValue = 1
        
        let urlA = URL(string: "http://testA.com")!
        manager.scheduleDownload(url: urlA, forceDownload: true) { _ in }
        
        let urlB = URL(string: "http://testB.com")!
        manager.scheduleDownload(url: urlB, forceDownload: true) { _ in }
        
        manager.cancelDownload(url: urlA)
        
        XCTAssertTrue(manager.downloading.count == 1)
        XCTAssertTrue(manager.waiting.count == 0)
        XCTAssertTrue(manager.suspended.count == 1)
    }
    
    func test_cancelDownload_cancelWaitingItem() {
        let manager = AssetDownloadManager()
        manager.maximumConcurrentDownloads = 1
        AssetDownloadManager.maximumConcurrentDownloadsResetValue = 1
        
        let urlA = URL(string: "http://testA.com")!
        manager.scheduleDownload(url: urlA, forceDownload: true) { _ in }
        
        let urlB = URL(string: "http://testB.com")!
        manager.scheduleDownload(url: urlB, forceDownload: true) { _ in }
        
        XCTAssertTrue(manager.waiting.count == 1)
        
        manager.cancelDownload(url: urlB)
        
        XCTAssertTrue(manager.downloading.count == 1)
        XCTAssertTrue(manager.waiting.count == 0)
        XCTAssertTrue(manager.suspended.count == 1)
    }
    
}
