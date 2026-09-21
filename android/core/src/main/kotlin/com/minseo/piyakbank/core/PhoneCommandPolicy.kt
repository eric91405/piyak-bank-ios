package com.minseo.piyakbank.core

/** Phone buttons retain the stage they displayed; the repository validates against its latest commit. */
object PhoneCommandPolicy {
    fun apply(
        data: AppState,
        instanceId: String,
        onboarded: Boolean,
        wage: Int,
        action: WatchAction,
        expectedSession: String,
        expectedStage: String,
        now: ClockSample,
    ): AppState {
        require(onboarded) { "시작 설정을 먼저 완료해 주세요." }
        WatchCommandPolicy.requireCurrentStage(instanceId, data, expectedSession, expectedStage, action)
        return when (action) {
            WatchAction.START -> DomainEngine.start(data, wage, now)
            WatchAction.PAUSE -> DomainEngine.pause(data, now)
            WatchAction.RESUME -> DomainEngine.resume(data, wage, now)
            WatchAction.FINISH -> DomainEngine.finish(data, now)
        }
    }
}
