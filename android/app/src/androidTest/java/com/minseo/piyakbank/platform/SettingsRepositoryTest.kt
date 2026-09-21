package com.minseo.piyakbank.platform

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.minseo.piyakbank.core.DomainEngine
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** Exercises production repository serialization only in the opt-in, separate .uitest package. */
@RunWith(AndroidJUnit4::class)
class SettingsRepositoryTest {
    private lateinit var repository: PiyakRepository

    @Before fun setup() = runBlocking {
        val application = ApplicationProvider.getApplicationContext<PiyakApplication>()
        assumeTrue("Synthetic writes require the separate UI QA package", application.packageName == "com.minseo.piyakbank.uitest")
        repository = application.repository
        repository.refresh()
        resetFixture()
    }

    @After fun cleanup() = runBlocking {
        if (this@SettingsRepositoryTest::repository.isInitialized) resetFixture()
    }

    private suspend fun resetFixture() {
        repository.mutate("합성 설정 검증") { prior, clock ->
            PersistentState(DomainEngine.fresh(clock), UserSettings(onboarded = true), revision = prior.revision)
        }
        assertNull(repository.ui.value.error)
        repository.clearMessage()
    }

    @Test fun parallelFieldUpdatesAllSurviveInActualSqliteSnapshot() = runBlocking {
        coroutineScope {
            launch { repository.updateWage(25_000) }
            launch { repository.updateAnimation(false) }
            launch { repository.updateNotifications(true) }
            launch { repository.updateReminderMinutes(30) }
        }
        assertEquals(UserSettings(25_000, true, true, 30, false), repository.snapshot().settings)
        assertNull(repository.ui.value.error)
    }

    @Test fun wageGuardUsesLatestCommittedWorkStateAndDoesNotCommitRejectedChange() = runBlocking {
        repository.mutate("다른 기기의 근무 시작") { state, clock ->
            state.copy(data = DomainEngine.start(state.data, state.settings.wage, clock, "watch-work"))
        }
        val before = repository.snapshot()
        repository.updateWage(50_000)
        assertNotNull(repository.ui.value.error)
        assertEquals(before, repository.snapshot())
        repository.updateAnimation(false)
        val after = repository.snapshot()
        assertNull(repository.ui.value.error)
        assertEquals(10_000, after.settings.wage)
        assertFalse(after.settings.animationEnabled)
        assertEquals(before.data, after.data)
    }
}
