package com.minseo.piyakbank.platform

/** Apply a single user's intent to the latest committed settings, never a stale UI copy. */
object SettingsPolicy {
    fun wage(state: PersistentState, value: Int): PersistentState {
        require(state.data.active == null) { "진행 중인 근무는 시급을 바꿀 수 없어요. 근무를 마친 뒤 다시 시도해 주세요." }
        return replace(state, state.settings.copy(wage = value))
    }
    fun notifications(state: PersistentState, enabled: Boolean) = replace(state, state.settings.copy(notificationsEnabled = enabled))
    fun animation(state: PersistentState, enabled: Boolean) = replace(state, state.settings.copy(animationEnabled = enabled))
    fun reminderMinutes(state: PersistentState, value: Int) = replace(state, state.settings.copy(reminderMinutes = value))

    private fun replace(state: PersistentState, settings: UserSettings): PersistentState {
        settings.validate()
        return state.copy(settings = settings)
    }
}
