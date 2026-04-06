//
//  LoadingCoordinatorTests.swift
//  BookPlayerTests
//
//  Created by Gianni Carlo on 30/10/21.
//  Copyright © 2021 BookPlayer LLC. All rights reserved.
//

import Foundation

@testable import BookPlayer
@testable import BookPlayerKit
import XCTest

@MainActor
class LoadingCoordinatorTests: XCTestCase {
  var loadingCoordinator: LoadingCoordinator!
  var presentingController: UINavigationController!

  override func setUp() {
    super.setUp()
    if AppServices.shared.setupCoreServicesTask == nil {
      AppServices.shared.setupCoreServices()
    }
    self.presentingController = MockNavigationController()
    self.loadingCoordinator = LoadingCoordinator(
      flow: .modalFlow(presentingController: self.presentingController)
    )
    self.loadingCoordinator.start()
  }

  @MainActor
  func testFinishedLoadingSequence() async throws {
    try await AppServices.shared.awaitCoreServices()
    XCTAssertNil(
      AppServices.shared.errorCoreServicesSetup,
      "Core Data / services setup failed: \(String(describing: AppServices.shared.errorCoreServicesSetup))"
    )
    self.loadingCoordinator.didFinishLoadingSequence()
    XCTAssertNotNil(
      self.loadingCoordinator.getMainCoordinator(),
      "MainCoordinator was not created; core services may be nil or didFinishLoadingSequence returned early"
    )
  }
}
