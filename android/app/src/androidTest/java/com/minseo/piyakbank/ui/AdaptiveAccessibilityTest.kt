package com.minseo.piyakbank.ui

import android.content.pm.ActivityInfo
import android.content.res.Configuration
import androidx.activity.ComponentActivity
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.junit4.accessibility.enableAccessibilityChecks
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModelStore
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import android.view.accessibility.AccessibilityNodeInfo
import com.minseo.piyakbank.MainActivity
import com.minseo.piyakbank.core.AppState
import com.minseo.piyakbank.core.ClockSample
import com.minseo.piyakbank.core.DomainEngine
import com.minseo.piyakbank.platform.PersistentState
import com.minseo.piyakbank.platform.PiyakApplication
import com.minseo.piyakbank.platform.PiyakRepository
import com.minseo.piyakbank.platform.PiyakViewModel
import com.minseo.piyakbank.platform.UserSettings
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain
import org.junit.rules.TestRule
import org.junit.runner.Description
import org.junit.runner.RunWith
import org.junit.runners.model.Statement

private const val ADAPTIVE_QA_PACKAGE = "com.minseo.piyakbank.uitest"
private const val ROOM_DESCRIPTION = "삐약이와 가구가 있는 3D 방. 아래 버튼으로 놀아 주거나 시점을 바꿀 수 있어요."

private fun adaptiveQaGuard() = TestRule { base, _: Description ->
    object : Statement() {
        override fun evaluate() {
            val app = ApplicationProvider.getApplicationContext<PiyakApplication>()
            assumeTrue("Synthetic adaptive tests require the isolated .uitest install", app.packageName == ADAPTIVE_QA_PACKAGE)
            base.evaluate()
        }
    }
}

private fun prepareAdaptiveFixture(onboarded: Boolean = true, working: Boolean = false): PiyakRepository {
    val app = ApplicationProvider.getApplicationContext<PiyakApplication>()
    check(app.packageName == ADAPTIVE_QA_PACKAGE) { "Never replace production app data" }
    val repository = app.repository
    runBlocking {
        repository.refresh()
        repository.mutate("합성 화면 검증 데이터") { previous, clock: ClockSample ->
            check(app.packageName == ADAPTIVE_QA_PACKAGE)
            val data = DomainEngine.fresh(clock).let { if (working) DomainEngine.start(it, 10_000, clock) else it }
            DomainEngine.validate(data)
            PersistentState(data, UserSettings(onboarded = onboarded, animationEnabled = false), previous.revision)
        }
    }
    assertNull(repository.ui.value.error)
    repository.clearMessage()
    return repository
}

/**
 * Real production Compose + repository under locally overridden viewport/font configuration.
 * ForcedSize verifies layout/interaction without changing the emulator or the user's system settings.
 * These cases do not claim physical tablet, GPU appearance, or TalkBack traversal coverage.
 * See https://developer.android.com/develop/ui/compose/testing/common-patterns
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class AdaptiveAccessibilityTest {
    private val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule val rules: RuleChain = RuleChain.outerRule(adaptiveQaGuard()).around(compose)
    private val models = ViewModelStore()
    private lateinit var repository: PiyakRepository
    private val viewport = mutableStateOf(DpSize(320.dp, 640.dp))
    private val testFontScale = mutableStateOf(1f)
    private var compositionId = ""
    private var disposedCompositions = 0
    private var currentDensity = ""

    private fun launch(size: DpSize = DpSize(320.dp, 640.dp), fontScale: Float = 1f, onboarded: Boolean = true, working: Boolean = false, overrideSize: Boolean = true) {
        repository = prepareAdaptiveFixture(onboarded, working)
        val app = ApplicationProvider.getApplicationContext<PiyakApplication>()
        lateinit var vm: PiyakViewModel
        compose.runOnUiThread { vm = PiyakViewModel(app); models.put("adaptive", vm); viewport.value = size; testFontScale.value = fontScale }
        compose.setContent {
            DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(testFontScale.value)) {
                if (overrideSize) DeviceConfigurationOverride(DeviceConfigurationOverride.ForcedSize(viewport.value)) {
                    val id = remember { java.util.UUID.randomUUID().toString() }
                    val density = LocalDensity.current
                    SideEffect { compositionId = id; currentDensity = density.toString() }
                    DisposableEffect(Unit) { onDispose { disposedCompositions++ } }
                    PiyakApp(vm, onExport = {}, onRequestNotifications = {})
                } else PiyakApp(vm, onExport = {}, onRequestNotifications = {})
            }
        }
        compose.waitForIdle()
    }

    @After fun cleanup() { compose.runOnUiThread { models.clear() } }

    private fun tab(text: String) = compose.onNode(hasText(text) and SemanticsMatcher.keyIsDefined(SemanticsProperties.Selected))
    private fun verticalList() = compose.onNode(SemanticsMatcher.keyIsDefined(SemanticsActions.ScrollToIndex) and SemanticsMatcher.keyIsDefined(SemanticsProperties.VerticalScrollAxisRange))
    private fun waitForData(predicate: (AppState) -> Boolean) {
        compose.waitUntil(10_000) { !repository.ui.value.busy && repository.ui.value.data?.let(predicate) == true }
        assertNull(repository.ui.value.error)
        compose.waitForIdle()
    }
    private fun assertTextFits(text: String) {
        val results = mutableListOf<TextLayoutResult>()
        compose.onNode(hasText(text) and SemanticsMatcher.keyIsDefined(SemanticsActions.GetTextLayoutResult), useUnmergedTree = true)
            .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(results) }
        assertTrue("No text layout returned for $text", results.isNotEmpty())
        val details = results.joinToString("\n") { result ->
            "size=${result.size}, constraints=${result.layoutInput.constraints}, density=${result.layoutInput.density}, " +
                "style=${result.layoutInput.style}, maxLines=${result.layoutInput.maxLines}, " +
                "widthOverflow=${result.didOverflowWidth}, heightOverflow=${result.didOverflowHeight}, " +
                "paragraph=${result.multiParagraph.width}x${result.multiParagraph.height}, lines=${result.lineCount}\n" +
                (0 until result.lineCount).joinToString("\n") { line ->
                    "line$line start=${result.getLineStart(line)} end=${result.getLineEnd(line)} " +
                        "left=${result.getLineLeft(line)} right=${result.getLineRight(line)} " +
                        "top=${result.getLineTop(line)} bottom=${result.getLineBottom(line)} ellipsized=${result.isLineEllipsized(line)}"
                }
        }
        assertTrue("Text is clipped or ellipsized: $text\n$details", results.none { it.hasVisualOverflow })
    }

    @Test fun narrow320DpKeepsEveryTabAndRoomControlsReachable() {
        launch()
        listOf("우리 방", "꾸미기", "근무 기록", "설정").forEach { tab(it).assertIsDisplayed() }
        compose.onNodeWithText("삐약이와 근무 시작").assertIsDisplayed().assertIsEnabled()
        compose.onNodeWithContentDescription("방 시점 조절").performScrollTo().performClick()
        listOf("왼쪽으로 회전", "오른쪽으로 회전", "방 확대", "방 축소", "기본 시점으로").forEach {
            compose.onNodeWithContentDescription(it).performScrollTo().assertIsDisplayed().performClick()
        }
        tab("꾸미기").performClick()
        compose.onNodeWithText("취향이 자라는 방").assertIsDisplayed()
        tab("근무 기록").performClick()
        compose.onNodeWithContentDescription("놓친 근무 추가").assertIsDisplayed()
        tab("설정").performClick()
        compose.onNodeWithText("기본 시급").performScrollTo().assertIsDisplayed()
        tab("우리 방").performClick()
        compose.onNodeWithText("삐약이와 근무 시작").assertIsDisplayed()
    }

    @Test fun shortLandscapeUsesReachableSideNavigationAndTimerControls() {
        launch(DpSize(720.dp, 360.dp), working = true)
        val home = tab("우리 방").fetchSemanticsNode().boundsInRoot
        tab("설정").performScrollTo().assertIsDisplayed().performClick()
        val settings = tab("설정").fetchSemanticsNode().boundsInRoot
        assertEquals("Landscape navigation must be in a side rail", home.center.x, settings.center.x, 2f)
        tab("우리 방").performScrollTo().performClick()
        compose.onNodeWithText("잠깐 쉬기").assertIsDisplayed().performClick()
        waitForData { it.active?.tracking?.working == false }
        compose.onNodeWithText("다시 근무").assertIsDisplayed()
        compose.onNodeWithText("근무 마치기").assertIsDisplayed()
        assertFalse(compose.onNodeWithText("다시 근무").fetchSemanticsNode().boundsInRoot.overlaps(
            compose.onNodeWithText("근무 마치기").fetchSemanticsNode().boundsInRoot))
    }

    @Test fun tabletShowsRoomAndEarningsBesideEachOtherAndRailNavigationWorks() {
        launch(DpSize(1280.dp, 800.dp))
        val room = compose.onNodeWithContentDescription(ROOM_DESCRIPTION).assertIsDisplayed().fetchSemanticsNode().boundsInRoot
        val earnings = compose.onNodeWithText("오늘의 예상 수익").assertIsDisplayed().fetchSemanticsNode().boundsInRoot
        assertTrue("Tablet earnings must occupy the column beside the room", earnings.left > room.right)
        val home = tab("우리 방").fetchSemanticsNode().boundsInRoot
        val settings = tab("설정").fetchSemanticsNode().boundsInRoot
        assertEquals(home.center.x, settings.center.x, 2f)
        assertTrue(settings.center.y > home.center.y)
        tab("꾸미기").performClick()
        compose.onNodeWithText("취향이 자라는 방").assertIsDisplayed()
        tab("근무 기록").performClick()
        compose.onNodeWithContentDescription("놓친 근무 추가").performClick()
        compose.onNodeWithText("기록 저장").assertIsDisplayed()
        compose.onNodeWithContentDescription("편집 취소").performClick()
        tab("설정").performClick()
        compose.onNodeWithText("기본 시급").assertIsDisplayed()
    }

    @Test fun doubledFontOnNarrowPhoneAllowsOnboardingWithoutClippingPrimaryAction() {
        launch(fontScale = 2f, onboarded = false)
        compose.onNode(hasSetTextAction()).performScrollTo().performTextReplacement("0")
        compose.onNodeWithText("삐약이의 방으로").performScrollTo().assertIsNotEnabled()
        compose.onNode(hasSetTextAction()).performScrollTo().performTextReplacement("12500")
        compose.onNodeWithText("삐약이의 방으로").performScrollTo().assertIsDisplayed()
        assertTextFits("삐약이의 방으로")
        compose.onNodeWithText("삐약이의 방으로").performClick()
        compose.waitUntil(10_000) { repository.ui.value.settings.onboarded }
        compose.onNodeWithText("삐약이와 근무 시작").assertIsDisplayed()
        assertTextFits("삐약이와 근무 시작")
    }

    @Test fun doubledFontKeepsWorkingActionsAndCalendarMonthArrowsUsable() {
        launch(fontScale = 2f, working = true)
        compose.onNodeWithText("잠깐 쉬기").assertIsDisplayed()
        compose.onNodeWithText("근무 마치기").assertIsDisplayed()
        assertTextFits("잠깐 쉬기")
        assertTextFits("근무 마치기")
        compose.onNodeWithText("잠깐 쉬기").performClick()
        waitForData { it.active?.tracking?.working == false }
        tab("근무 기록").performClick()
        verticalList().performScrollToNode(hasContentDescription("다음 달"))
        compose.onNodeWithContentDescription("다음 달").assertIsDisplayed().performClick()
        compose.onNodeWithContentDescription("이전 달").assertIsDisplayed().performClick()
        compose.onNodeWithText("오늘로").performScrollTo().assertIsDisplayed().performClick()
    }

    @Test fun doubledFontSettingsWageDialogCanScrollValidateAndSave() {
        launch(fontScale = 2f)
        tab("설정").performClick()
        compose.onNodeWithText("기본 시급").performScrollTo().performClick()
        compose.onNode(hasSetTextAction()).performScrollTo().performTextReplacement("0")
        compose.onNodeWithText("저장").assertIsNotEnabled()
        compose.onNode(hasSetTextAction()).performTextReplacement("18000")
        compose.onNodeWithText("저장").assertIsDisplayed().performClick()
        compose.waitUntil(10_000) { repository.ui.value.settings.wage == 18_000 }
        compose.onNodeWithText("18,000원").assertExists()
    }

    @Test fun changingViewportRetainsSelectedTabAndUnsavedRecordDraft() {
        launch()
        tab("근무 기록").performClick()
        compose.onNodeWithContentDescription("놓친 근무 추가").performClick()
        compose.onNode(hasSetTextAction()).performScrollTo().performTextReplacement("23456")
        val originalComposition = compositionId
        compose.runOnIdle { viewport.value = DpSize(1100.dp, 700.dp) }
        awaitReattachedRecordEditor(originalComposition)
        compose.runOnIdle { viewport.value = DpSize(720.dp, 360.dp) }
        awaitReattachedRecordEditor(originalComposition)
        compose.onNodeWithText("기록 저장").assertIsDisplayed()
        compose.onNodeWithContentDescription("편집 취소").performClick()
        compose.onNodeWithText("계속 편집").performClick()
        compose.onNode(hasSetTextAction()).assertTextContains("23456")
        assertTrue(repository.ui.value.data!!.records.isEmpty())
        compose.onNodeWithContentDescription("편집 취소").performClick()
        compose.onNodeWithText("저장하지 않고 닫기").performClick()
        tab("근무 기록").assertIsSelected()
    }

    private fun awaitReattachedRecordEditor(originalComposition: String) {
        // ForcedSize changes LocalDensity. Compose recreates DialogWrapper for that density,
        // then shows its Android window in LaunchedEffect; API26 can attach after Compose is idle.
        // Wait for attachment only, then assert the original value: no dismissal/reopening fixture.
        val field = hasSetTextAction() and hasText("1번째 구간 시급")
        try {
            compose.waitUntil(5_000) { compose.onAllNodes(field).fetchSemanticsNodes().size == 1 }
        } catch (failure: ComposeTimeoutException) {
            throw AssertionError("Record editor did not survive viewport change: " +
                "originalComposition=$originalComposition, currentComposition=$compositionId, disposed=$disposedCompositions, " +
                "density=$currentDensity, viewport=${viewport.value}, ui=${repository.ui.value}\n" +
                compose.onAllNodes(isRoot(), useUnmergedTree = true).printToString(maxDepth = 20), failure)
        }
        compose.onNode(field).assertTextContains("23456")
        compose.onNodeWithContentDescription("편집 취소").assertExists()
    }

    @Test fun changingDensityAndFontKeepsWageDialogDraftUntilExplicitSave() {
        launch()
        tab("설정").performClick()
        compose.onNodeWithText("기본 시급").performScrollTo().performClick()
        compose.onNode(hasSetTextAction()).performTextReplacement("24680")
        compose.runOnIdle { viewport.value = DpSize(1100.dp, 700.dp) }
        compose.waitUntil(5_000) { compose.onAllNodes(hasSetTextAction()).fetchSemanticsNodes().size == 1 }
        compose.onNode(hasSetTextAction()).assertTextContains("24680")
        compose.runOnIdle { testFontScale.value = 2f }
        compose.waitUntil(5_000) { compose.onAllNodes(hasSetTextAction()).fetchSemanticsNodes().size == 1 }
        compose.onNode(hasSetTextAction()).assertTextContains("24680")
        assertEquals("Resizing must not implicitly save the draft", 10_000, repository.ui.value.settings.wage)
        compose.onNodeWithText("저장").assertIsDisplayed().performClick()
        compose.waitUntil(10_000) { repository.ui.value.settings.wage == 24_680 }
        tab("설정").assertIsSelected()
        compose.onNodeWithText("24,680원").assertExists()
    }

    @Test fun systemAccessibilityTreeExposesRoomDescription() {
        launch(overrideSize = false)
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        fun containsRoom(node: AccessibilityNodeInfo): Boolean {
            if (node.contentDescription?.toString() == ROOM_DESCRIPTION && node.isVisibleToUser) return true
            return (0 until node.childCount).any { index -> node.getChild(index)?.let(::containsRoom) == true }
        }
        // Query the platform tree used by TalkBack, not just Compose's test semantics.
        compose.waitUntil(10_000) { automation.rootInActiveWindow?.let(::containsRoom) == true }
    }

    /** ATF checks actual device bounds: no ForcedSize scaling that could distort touch-size results. */
    @SdkSuppress(minSdkVersion = 34)
    @Test fun accessibilityFrameworkChecksHomeTabsSettingsAndRecordEditor() {
        launch(overrideSize = false)
        compose.enableAccessibilityChecks()
        compose.onRoot().tryPerformAccessibilityChecks()
        tab("꾸미기").performClick()
        compose.onRoot().tryPerformAccessibilityChecks()
        tab("근무 기록").performClick()
        compose.onNodeWithContentDescription("놓친 근무 추가").performClick()
        compose.onNode(hasSetTextAction()).performScrollTo().performTextReplacement("15000")
        compose.onNodeWithText("기록 저장").tryPerformAccessibilityChecks()
        compose.onNodeWithContentDescription("편집 취소").performClick()
        compose.onNodeWithText("저장하지 않고 닫기").performClick()
        tab("설정").performClick()
        compose.onNodeWithContentDescription("삐약이 움직임").performScrollTo().tryPerformAccessibilityChecks()
    }
}

/** Actual Activity recreation/configuration changes; these are not simulated saveable registries. */
@RunWith(AndroidJUnit4::class)
class AdaptiveActivityRecreationTest {
    private val compose = createEmptyComposeRule()
    @get:Rule val rules: RuleChain = RuleChain.outerRule(adaptiveQaGuard()).around(compose)

    private fun rotate(scenario: ActivityScenario<MainActivity>, orientation: Int, expected: Int) {
        scenario.onActivity { it.requestedOrientation = orientation }
        compose.waitUntil(10_000) {
            var actual = Configuration.ORIENTATION_UNDEFINED
            scenario.onActivity { actual = it.resources.configuration.orientation }
            actual == expected
        }
        compose.waitForIdle()
    }

    @Test fun realPortraitLandscapeRecreationPreservesAllUnsavedRecordSegments() {
        val repository = prepareAdaptiveFixture()
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            rotate(scenario, ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, Configuration.ORIENTATION_PORTRAIT)
            compose.onNodeWithText("근무 기록").performClick()
            compose.onNodeWithContentDescription("놓친 근무 추가").performClick()
            compose.onNode(hasSetTextAction()).performScrollTo().performTextReplacement("23456")
            compose.onNodeWithText("근무·휴식 구간 추가").performScrollTo().performClick()
            compose.onAllNodes(hasSetTextAction()).assertCountEquals(2)
            rotate(scenario, ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE, Configuration.ORIENTATION_LANDSCAPE)
            compose.onNode(hasSetTextAction() and hasText("1번째 구간 시급")).assertTextContains("23456")
            compose.onNode(hasSetTextAction() and hasText("2번째 구간 시급")).assertTextContains("0")
            compose.onNodeWithText("기록 저장").assertIsDisplayed()
            scenario.recreate()
            compose.onNode(hasSetTextAction() and hasText("1번째 구간 시급")).assertTextContains("23456")
            rotate(scenario, ActivityInfo.SCREEN_ORIENTATION_PORTRAIT, Configuration.ORIENTATION_PORTRAIT)
            compose.onNode(hasSetTextAction() and hasText("2번째 구간 시급")).assertTextContains("0")
            compose.onNodeWithContentDescription("편집 취소").performClick()
            compose.onNodeWithText("계속 편집").performClick()
            assertTrue(repository.ui.value.data!!.records.isEmpty())
            assertEquals(0L, DomainEngine.balance(repository.ui.value.data!!))
        }
    }

    @Test fun actualActivityRecreationKeepsSettingsTabDialogAndDraftThenSaves() {
        val repository = prepareAdaptiveFixture()
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            compose.onNodeWithText("설정").performClick()
            compose.onNodeWithText("기본 시급").performScrollTo().performClick()
            compose.onNode(hasSetTextAction()).performTextReplacement("17500")
            scenario.recreate()
            compose.onNode(hasSetTextAction()).assertTextContains("17500")
            compose.onNodeWithText("저장").performClick()
            compose.waitUntil(10_000) { repository.ui.value.settings.wage == 17_500 }
            compose.onNodeWithText("설정").assertIsSelected()
            compose.onNodeWithText("17,500원").assertExists()
        }
    }
}
