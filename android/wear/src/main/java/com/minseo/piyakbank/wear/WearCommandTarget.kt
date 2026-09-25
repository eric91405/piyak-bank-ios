package com.minseo.piyakbank.wear

/** The state the user actually saw, rather than whichever shift is current at send time. */
data class WearCommandTarget(val instance: String, val session: String, val stage: String, val working: Boolean) {
    fun matches(phone: PhoneState): Boolean = this == phone.commandTarget()
}

fun PhoneState.commandTarget() = WearCommandTarget(instance, session, stage, working)
