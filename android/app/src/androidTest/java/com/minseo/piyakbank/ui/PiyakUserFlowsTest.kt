package com.minseo.piyakbank.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelStore
import androidx.test.core.app.ApplicationProvider
import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.minseo.piyakbank.core.*
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
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId

/**
 * Real Compose screens, ViewModel, domain actions and SQLite commits in a separate installed package.
 *
 * Run: ./gradlew -PpiyakUiTest=true :app:connectedUiTestAndroidTest
 * The ordinary com.minseo.piyakbank install is never reset or used as a fixture. A guard runs before
 * the test activity is launched, and fixture writes repeat that check. The QA package also prevents
 * its synthetic snapshots reaching production widgets or Wear peers with a different package ID.
 * These interaction assertions do not validate GPU appearance or physical Wear communication.
 */
@RunWith(AndroidJUnit4::class)
class PiyakUserFlowsTest {
    private val compose = createAndroidComposeRule<ComponentActivity>()
    private val qaOnly = TestRule { base, _: Description ->
        object : Statement() {
            override fun evaluate() {
                val app = ApplicationProvider.getApplicationContext<PiyakApplication>()
                assumeTrue("UI fixture tests require the opt-in .uitest package; normal app data is untouched", app.packageName == QA_PACKAGE)
                base.evaluate()
            }
        }
    }
    @get:Rule val rules: RuleChain = RuleChain.outerRule(qaOnly).around(compose)
    private lateinit var repository: PiyakRepository
    private lateinit var viewModel: PiyakViewModel
    private val models = ViewModelStore()

    private fun launch(onboarded: Boolean = true, fixture: (ClockSample) -> AppState = DomainEngine::fresh): AppState {
        val app = ApplicationProvider.getApplicationContext<PiyakApplication>()
        check(app.packageName == QA_PACKAGE) { "Refusing to replace a non-QA app database" }
        repository = app.repository
        runBlocking {
            repository.refresh()
            repository.mutate("합성 UI 검증 데이터") { previous, clock ->
                check(app.packageName == QA_PACKAGE)
                val data = fixture(clock)
                DomainEngine.validate(data)
                PersistentState(data = data, settings = UserSettings(onboarded = onboarded, animationEnabled = false), revision = previous.revision)
            }
        }
        assertNull("Fixture must commit before the UI starts", repository.ui.value.error)
        repository.clearMessage()
        val initial = repository.ui.value.data!!
        compose.runOnUiThread {
            viewModel = PiyakViewModel(app)
            models.put("ui-test", viewModel)
        }
        compose.setContent { PiyakApp(viewModel, onExport = {}, onRequestNotifications = {}) }
        compose.waitForIdle()
        return initial
    }

    @After fun releaseViewModel() {
        if (::viewModel.isInitialized) compose.runOnUiThread { models.clear() }
    }

    private fun data(): AppState = repository.ui.value.data!!
    private fun waitForState(condition: (AppState) -> Boolean) {
        try {
            compose.waitUntil(timeoutMillis = 10_000) {
                repository.ui.value.error != null ||
                    (repository.ui.value.data?.let(condition) == true && !repository.ui.value.busy)
            }
        } catch (e: ComposeTimeoutException) {
            val ui = repository.ui.value
            throw AssertionError("UI action did not reach its expected state: busy=${ui.busy}, error=${ui.error}, " +
                "actionRevision=${ui.actionRevision}, active=${ui.data?.active?.id}, " +
                "working=${ui.data?.active?.tracking?.working}, records=${ui.data?.records?.size}", e)
        }
        assertNull("Action must not report an error", repository.ui.value.error)
        compose.waitForIdle()
    }
    /** Real touch delivery matters: semantically enabled buttons can still be covered by a banner. */
    private fun assertFeedbackDoesNotCoverControl(message: String, button: String) {
        val feedback = compose.onAllNodesWithText(message).fetchSemanticsNodes().singleOrNull() ?: return
        val control = compose.onNodeWithText(button).assertIsEnabled().fetchSemanticsNode()
        assertFalse("Transient feedback covers the $button touch target",
            feedback.boundsInRoot.overlaps(control.boundsInRoot))
    }
    private fun dialogButton(label: String) = compose.onNode(hasText(label) and hasClickAction() and hasAnyAncestor(isDialog()))
    private fun snapshot(): PersistentState = runBlocking { repository.snapshot() }
    private fun verticalList() = compose.onNode(
        SemanticsMatcher.keyIsDefined(SemanticsActions.ScrollToIndex) and
            SemanticsMatcher.keyIsDefined(SemanticsProperties.VerticalScrollAxisRange),
    )

    @Test fun onboardingBlocksMissingZeroAndExcessiveWageThenSavesValidValue() {
        launch(onboarded = false)
        val wage = compose.onNode(hasSetTextAction())
        for (invalid in listOf("", "0", "1000001")) {
            wage.performTextReplacement(invalid)
            compose.onNodeWithText("삐약이의 방으로").assertIsNotEnabled()
            assertFalse(repository.ui.value.settings.onboarded)
        }
        wage.performTextReplacement("12500")
        compose.onNodeWithText("삐약이의 방으로").performScrollTo().assertIsEnabled().performClick()
        compose.waitUntil(10_000) { repository.ui.value.settings.onboarded }
        compose.onNodeWithText("삐약이의 하루").assertExists()
        assertEquals(12_500, snapshot().settings.wage)
        assertTrue(snapshot().settings.onboarded)
    }

    @Test fun timerConfirmsStartPausesResumesAndCommitsOneCompletedRecord() {
        launch()
        compose.onNodeWithText("삐약이와 근무 시작").performClick()
        dialogButton("취소").performClick()
        assertNull(snapshot().data.active)

        compose.onNodeWithText("삐약이와 근무 시작").performClick()
        dialogButton("근무 시작").performClick()
        waitForState { it.active?.tracking?.working == true }
        val sessionId = data().active!!.id
        assertFeedbackDoesNotCoverControl("근무를 시작했어요.", "잠깐 쉬기")
        compose.onNodeWithText("잠깐 쉬기").assertIsDisplayed().performClick()
        waitForState { it.active?.tracking?.working == false }
        compose.onNodeWithText("다시 근무").assertIsDisplayed()
        assertEquals(0, snapshot().data.active!!.segments.last().hourlyWage)

        assertFeedbackDoesNotCoverControl("잠시 쉬어요.", "다시 근무")
        compose.onNodeWithText("다시 근무").performClick()
        waitForState { it.active?.tracking?.working == true }
        assertEquals(sessionId, snapshot().data.active!!.id)
        assertFeedbackDoesNotCoverControl("다시 함께 일해요.", "근무 마치기")
        compose.onNodeWithText("근무 마치기").performClick()
        dialogButton("취소").performClick()
        assertNotNull(snapshot().data.active)
        compose.onNodeWithText("근무 마치기").performClick()
        dialogButton("근무 마치기").performClick()
        waitForState { it.active == null && it.records.size == 1 }
        compose.onNodeWithText("삐약이와 근무 시작").assertIsDisplayed()
        val saved = snapshot().data
        assertEquals(sessionId, saved.records.single().id)
        assertEquals(listOf(10_000, 0, 10_000), saved.records.single().segments.map { it.hourlyWage })
        assertTrue(saved.records.single().segments.all { it.endMillis != null })
        assertEquals(1, saved.receipts.size)
        DomainEngine.validate(saved)
    }

    @Test fun existingEditorShowsAllSegmentsRejectsInvalidDraftAndKeepsEarnedPoints() {
        val original = launch(fixture = ::completedThreeSegmentSession)
        assertTrue("Fixture has earned points to protect during edits", DomainEngine.balance(original) > 0)
        val record = original.records.single()
        val originalTotal = EarningsCalculator.total(record.segments, repository.ui.value.now)
        openHistoryOnRecord(record)
        verticalList().performScrollToNode(hasContentDescription("근무 기록 수정 또는 삭제"))
        compose.onNodeWithContentDescription("근무 기록 수정 또는 삭제").performClick()
        compose.onNodeWithText("기록 수정").performClick()
        compose.onNodeWithText("근무 기록 수정").assertExists()
        compose.onNodeWithText("놓친 근무 추가").assertDoesNotExist()
        compose.onAllNodes(hasSetTextAction()).assertCountEquals(3)

        val firstWage = compose.onNode(hasSetTextAction() and hasText("1번째 구간 시급"))
        firstWage.assertTextContains("10000")
        compose.onNode(hasSetTextAction() and hasText("2번째 구간 시급")).assertTextContains("0")
        compose.onNode(hasSetTextAction() and hasText("3번째 구간 시급")).assertTextContains("15000")
        firstWage.performTextReplacement("")
        compose.onNodeWithText("기록 저장").performClick()
        compose.onNodeWithText("근무 기록 수정").assertExists()
        compose.onNodeWithText("시급은 0~1,000,000원으로 입력해 주세요.").assertExists()
        assertEquals(record, snapshot().data.records.single())

        firstWage.performTextReplacement("20000")
        compose.onNodeWithText("기록 저장").performClick()
        dialogButton("저장").performClick()
        waitForState { it.records.singleOrNull()?.revision == record.revision + 1 }
        compose.onNodeWithText("근무 기록 수정").assertDoesNotExist()
        val edited = snapshot().data
        assertEquals(record.id, edited.records.single().id)
        assertEquals(listOf(20_000, 0, 15_000), edited.records.single().segments.map { it.hourlyWage })
        assertTrue(EarningsCalculator.total(edited.records.single().segments, repository.ui.value.now) > originalTotal)
        assertEquals(original.ledger, edited.ledger)
        assertEquals(original.receipts, edited.receipts)
        assertEquals(DomainEngine.balance(original), DomainEngine.balance(edited))
        assertEquals(DomainEngine.level(original), DomainEngine.level(edited))
    }

    @Test fun manualHighWageRecordChangesPayWithoutCreatingPoints() {
        val original = launch(fixture = { clock ->
            val completed = completedThreeSegmentSession(clock)
            DomainEngine.deleteRecord(completed, completed.records.single().id, 0)
        })
        assertTrue("Manual entry must preserve an existing earned balance", DomainEngine.balance(original) > 0)
        compose.onNodeWithText("근무 기록").performClick()
        compose.onNodeWithContentDescription("놓친 근무 추가").performClick()
        compose.onNodeWithText("놓친 근무 추가").assertExists()
        compose.onNode(hasSetTextAction()).performTextReplacement("999999")
        compose.onNodeWithText("기록 저장").performClick()
        dialogButton("저장").performClick()
        waitForState { it.records.size == 1 }
        val saved = snapshot().data
        assertEquals(999_999, saved.records.single().segments.single().hourlyWage)
        assertTrue(EarningsCalculator.total(saved.records.single().segments, repository.ui.value.now) > 0)
        assertEquals(original.ledger, saved.ledger)
        assertEquals(original.receipts, saved.receipts)
        assertEquals(DomainEngine.balance(original), DomainEngine.balance(saved))
        assertEquals(DomainEngine.level(original), DomainEngine.level(saved))
    }

    @Test fun insufficientPointsPreviewCannotBuyAndBackPreservesEquipment() {
        val original = launch()
        val item = Catalog.items.first { !it.defaultOwned }
        compose.onNodeWithText("꾸미기").performClick()
        val itemDescription = hasContentDescription(item.name, substring = true)
        verticalList().performScrollToNode(itemDescription)
        compose.onNode(itemDescription).performClick()
        compose.onNodeWithText("아이템 미리보기").assertExists()
        compose.onNodeWithText("${item.price.toLong().points()} 더 필요해요").assertIsNotEnabled()
        Espresso.pressBack()
        compose.onNodeWithText("아이템 미리보기").assertDoesNotExist()
        val saved = snapshot().data
        assertEquals(original.owned, saved.owned)
        assertEquals(original.ledger, saved.ledger)
        assertEquals(0L, DomainEngine.balance(saved))
        compose.onNodeWithText("꾸미기").assertIsSelected()
    }

    private fun openHistoryOnRecord(record: WorkRecord) {
        compose.onNodeWithText("근무 기록").performClick()
        val zone = ZoneId.systemDefault()
        val lastDay = Instant.ofEpochMilli(record.segments.last().endMillis!! - 1).atZone(zone).toLocalDate()
        val today = Instant.ofEpochMilli(repository.ui.value.now).atZone(zone).toLocalDate()
        if (YearMonth.from(lastDay) != YearMonth.from(today)) compose.onNodeWithContentDescription("이전 달").performClick()
        val prefix = "${lastDay.year}년 ${lastDay.format(KoreanDate)}, 예상 수익"
        verticalList().performScrollToNode(hasContentDescription(prefix, substring = true))
        compose.onNodeWithContentDescription(prefix, substring = true).performClick()
    }

    /** Domain APIs create a valid earned balance; fixture setup never patches money independently. */
    private fun completedThreeSegmentSession(clock: ClockSample): AppState {
        val end = clock.wallMillis - 1_000
        val start = ClockSample(end - 1_800_000, 10_000, "synthetic-ui-fixture")
        fun at(delta: Long) = start.copy(wallMillis = start.wallMillis + delta, elapsedMillis = start.elapsedMillis + delta)
        var state = DomainEngine.start(DomainEngine.fresh(start), 10_000, start, "synthetic-three-segments")
        state = DomainEngine.pause(state, at(600_000))
        state = DomainEngine.resume(state, 15_000, at(1_200_000))
        return DomainEngine.finish(state, at(1_800_000))
    }

    private companion object { const val QA_PACKAGE = "com.minseo.piyakbank.uitest" }
}
