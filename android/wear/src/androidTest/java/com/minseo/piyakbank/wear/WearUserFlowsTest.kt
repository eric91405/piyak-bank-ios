package com.minseo.piyakbank.wear

import android.content.pm.PackageManager
import androidx.activity.ComponentActivity
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Fake phone snapshots test the actual watch UI without writing any phone or watch data. */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class WearUserFlowsTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val phone = PhoneState("install-A", 1, 1000, true, "shift-A", true, 10, 20, 1, 10000, "", "stage-A", emptyMap())

    @Test fun disconnectedWatchCannotQueueCommandsAndRefreshRemainsUsable() {
        var refreshes = 0
        compose.setContent { WearHome(WearUiState(), { _, _ -> fail("Offline command") }, { refreshes++ }) }
        compose.onNodeWithText("근무 시작").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("새로고침").performScrollTo().performClick()
        compose.runOnIdle { assertEquals(1, refreshes) }
    }

    @Test fun olderFinishDialogCannotEndNewShiftAfterPhoneUpdate() {
        val ui = mutableStateOf(WearUiState(phone, connected = true))
        val commands = mutableListOf<Pair<String, WearCommandTarget>>()
        compose.setContent { WearHome(ui.value, { action, target -> commands += action to target }, {}) }
        compose.onNodeWithText("근무 마치기").performScrollTo().performClick()
        compose.runOnIdle { ui.value = ui.value.copy(phone = phone.copy(session = "shift-B", stage = "stage-B")) }
        compose.onNodeWithText("마치기").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("취소").performScrollTo().performClick()
        compose.onNodeWithText("근무 마치기").performScrollTo().performClick()
        compose.onNodeWithText("마치기").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals(listOf("finish" to ui.value.phone!!.commandTarget()), commands)
        }
    }

    @Test fun finishTargetSurvivesSavedStateAndRejectsChangedStage() {
        val ui = mutableStateOf(WearUiState(phone, connected = true))
        val restoration = StateRestorationTester(compose)
        restoration.setContent { WearHome(ui.value, { _, _ -> fail("Stale command") }, {}) }
        compose.onNodeWithText("근무 마치기").performScrollTo().performClick()
        restoration.emulateSavedInstanceStateRestore()
        compose.runOnIdle { ui.value = ui.value.copy(phone = phone.copy(stage = "resumed-stage")) }
        compose.onNodeWithText("마치기").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("취소").performScrollTo().assertIsDisplayed()
    }

    @Test fun doubledFontAllowsScrollingToEveryActionAndBusyBlocksDuplicates() {
        val ui = mutableStateOf(WearUiState(phone, connected = true))
        val commands = mutableListOf<String>()
        compose.setContent {
            DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(2f)) {
                WearHome(ui.value, { action, _ -> commands += action }, {})
            }
        }
        compose.onNodeWithText("잠깐 쉬기").performScrollTo().assertIsDisplayed().performClick()
        compose.runOnIdle { ui.value = ui.value.copy(busy = true) }
        compose.onNodeWithText("잠깐 쉬기").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("근무 마치기").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("새로고침").performScrollTo().assertIsDisplayed()
        compose.runOnIdle { assertEquals(listOf("pause"), commands) }
    }
}

@RunWith(AndroidJUnit4::class)
class WearActivityCompatibilityTest {
    @get:Rule val compose = createEmptyComposeRule()
    @Test fun realWatchActivityLaunchesAndRecreatesOnWearSystemImage() {
        val app = ApplicationProvider.getApplicationContext<WearApplication>()
        assertTrue("Run this smoke test on an actual Wear system image", app.packageManager.hasSystemFeature(PackageManager.FEATURE_WATCH))
        ActivityScenario.launch(WearActivity::class.java).use { scenario ->
            compose.onNodeWithText("삐약뱅크").assertIsDisplayed()
            scenario.recreate()
            compose.onNodeWithText("새로고침").performScrollTo().assertIsDisplayed()
        }
    }
}
