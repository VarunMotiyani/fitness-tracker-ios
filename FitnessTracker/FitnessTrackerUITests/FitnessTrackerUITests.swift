//
//  FitnessTrackerUITests.swift
//  FitnessTrackerUITests
//
//  Created by Motiyani, Varun on 28/08/26.
//

import XCTest

final class FitnessTrackerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppFlowAndCaptureScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        // 1. Home screen verification
        let pulseTitle = app.staticTexts["PulseAI"]
        XCTAssertTrue(pulseTitle.waitForExistence(timeout: 5.0))
        saveScreenshot(app: app, name: "audit_ui_home")

        // 2. Open Settings
        let gearButton = app.buttons["settings_gear_button"]
        if gearButton.waitForExistence(timeout: 3.0) {
            gearButton.tap()
            sleep(1)
            saveScreenshot(app: app, name: "audit_ui_settings_top")

            // Scroll down
            app.swipeUp()
            sleep(1)
            saveScreenshot(app: app, name: "audit_ui_settings_middle")

            app.swipeUp()
            sleep(1)
            saveScreenshot(app: app, name: "audit_ui_settings_bottom")

            app.swipeUp()
            sleep(1)
            saveScreenshot(app: app, name: "audit_ui_settings_data")

            // Check if Equipment Profile exists
            let equipmentRow = app.staticTexts["Equipment Profile"]
            if equipmentRow.waitForExistence(timeout: 2.0) {
                equipmentRow.tap()
                sleep(1)
                saveScreenshot(app: app, name: "audit_ui_equipment_profiles")
                let doneBtn = app.buttons["Done"]
                if doneBtn.exists { doneBtn.tap() }
                sleep(1)
            }

            // Check Hevy API sync sheet
            let hevyRow = app.staticTexts["Import from Hevy (API Key)"]
            if hevyRow.waitForExistence(timeout: 2.0) {
                hevyRow.tap()
                sleep(1)
                saveScreenshot(app: app, name: "audit_ui_hevy_sync_sheet")
                let cancelBtn = app.buttons["Cancel"]
                if cancelBtn.exists { cancelBtn.tap() }
                sleep(1)
            }

            let settingsDone = app.buttons["Done"]
            if settingsDone.exists {
                settingsDone.tap()
                sleep(1)
            }
        }
    }

    @MainActor
    private func saveScreenshot(app: XCUIApplication, name: String) {
        let screenshot = app.screenshot()
        let tmpPath = "/tmp/\(name).png"
        let tmpUrl = URL(fileURLWithPath: tmpPath)
        try? screenshot.pngRepresentation.write(to: tmpUrl)
        
        let brainPath = "/Users/vmotiyani/.gemini/antigravity/brain/dbf13674-330a-445a-a665-5736a817fde4/\(name).png"
        let brainUrl = URL(fileURLWithPath: brainPath)
        try? screenshot.pngRepresentation.write(to: brainUrl)
    }
}
