package com.minseo.piyakbank.core

import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class WatchCommandPolicyTest {
    private val initial = ClockSample(Instant.parse("2026-09-20T15:00:00Z").toEpochMilli(), 100_000, "boot-1")
    private fun after(millis: Long) = initial.copy(wallMillis = initial.wallMillis + millis, elapsedMillis = initial.elapsedMillis + millis)
    private fun context(data: AppState = DomainEngine.fresh(initial), processed: List<String> = emptyList()) =
        WatchCommandContext("instance-1", true, data, processed)
    private fun command(context: WatchCommandContext, action: WatchAction, id: String = "command-1") =
        WatchCommand(id, context.instanceId, context.data.active?.id ?: "", WatchCommandPolicy.stageToken(context.instanceId, context.data), action, initial.wallMillis)
    private fun rejects(block: () -> Unit) {
        try { block(); fail("Expected invalid/stale command rejection") } catch (_: IllegalArgumentException) { /* expected */ }
    }

    @Test fun freshStartIsAcceptedAndCheckpointDoesNotInvalidatePauseControl() {
        val idle = context()
        assertEquals(CommandDecision.APPLY, WatchCommandPolicy.validate(command(idle, WatchAction.START), idle, initial.wallMillis))
        val working = context(DomainEngine.start(idle.data, 10_000, initial, "work"))
        val pause = command(working, WatchAction.PAUSE)
        val checkpointed = working.copy(data = DomainEngine.checkpoint(working.data, after(15_000)))
        assertEquals(pause.stageToken, WatchCommandPolicy.stageToken(checkpointed.instanceId, checkpointed.data))
        assertEquals(CommandDecision.APPLY, WatchCommandPolicy.validate(pause, checkpointed, after(15_000).wallMillis))
    }

    @Test fun oldPauseCannotExecuteAfterPauseAndResumeInSameSession() {
        val working = context(DomainEngine.start(context().data, 10_000, initial, "work"))
        val old = command(working, WatchAction.PAUSE)
        val resumed = DomainEngine.resume(DomainEngine.pause(working.data, after(1000)), 10_000, after(2000))
        rejects { WatchCommandPolicy.validate(old, context(resumed), after(3000).wallMillis) }
    }

    @Test fun oldIdleStartCannotExecuteAfterInterveningShiftFinishesOrRecordDeleted() {
        val idle = context()
        val old = command(idle, WatchAction.START)
        val completed = DomainEngine.finish(DomainEngine.start(idle.data, 10_000, initial, "work"), after(6000))
        val deleted = DomainEngine.deleteRecord(completed, "work", 0)
        rejects { WatchCommandPolicy.validate(old, context(completed), after(7000).wallMillis) }
        rejects { WatchCommandPolicy.validate(old, context(deleted), after(7000).wallMillis) }
    }

    @Test fun alreadyCommittedCommandIsAcknowledgedWithoutReexecutingEvenAfterStateMoves() {
        val idle = context()
        val start = command(idle, WatchAction.START)
        val running = context(DomainEngine.start(idle.data, 10_000, initial, "work"), listOf(start.id))
        assertEquals(CommandDecision.DUPLICATE, WatchCommandPolicy.validate(start, running, after(600_000).wallMillis))
    }

    @Test fun resetChangesInstanceAndCannotAcceptOldReplayReceipt() {
        val idle = context()
        val old = command(idle, WatchAction.START)
        val reset = context(processed = listOf(old.id)).copy(instanceId = "instance-2")
        rejects { WatchCommandPolicy.validate(old, reset, initial.wallMillis) }
    }

    @Test fun staleFutureAndInvalidCommandTimesAreRejectedWithExactBoundarySupport() {
        val idle = context()
        val command = command(idle, WatchAction.START)
        assertEquals(CommandDecision.APPLY, WatchCommandPolicy.validate(command, idle, initial.wallMillis + 120_000))
        rejects { WatchCommandPolicy.validate(command, idle, initial.wallMillis + 120_001) }
        assertEquals(CommandDecision.APPLY, WatchCommandPolicy.validate(command.copy(createdMillis = initial.wallMillis + 30_000), idle, initial.wallMillis))
        rejects { WatchCommandPolicy.validate(command.copy(createdMillis = initial.wallMillis + 30_001), idle, initial.wallMillis) }
        rejects { WatchCommandPolicy.validate(command.copy(createdMillis = Long.MIN_VALUE), idle, initial.wallMillis) }
    }

    @Test fun wrongSessionAndActionCannotControlCurrentTimer() {
        val idle = context()
        rejects { WatchCommandPolicy.validate(command(idle, WatchAction.FINISH), idle, initial.wallMillis) }
        val running = context(DomainEngine.start(idle.data, 10_000, initial, "work"))
        rejects { WatchCommandPolicy.validate(command(running, WatchAction.RESUME), running, initial.wallMillis) }
        rejects { WatchCommandPolicy.validate(command(running, WatchAction.PAUSE).copy(sessionId = "other"), running, initial.wallMillis) }
    }

    @Test fun commandIdentifiersAndOnboardingMustBeValid() {
        val idle = context()
        val start = command(idle, WatchAction.START)
        for (id in listOf("", " ", "bad\ncommand", "x".repeat(101))) {
            rejects { WatchCommandPolicy.validate(start.copy(id = id), idle, initial.wallMillis) }
        }
        rejects { WatchCommandPolicy.validate(start, idle.copy(onboarded = false), initial.wallMillis) }
    }
}
