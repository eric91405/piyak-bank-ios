package com.minseo.piyakbank.scene

import org.junit.Assert.*
import org.junit.Test

class RoomChoreographyTest {
    @Test fun crossRoomTravelUsesFrontAisle() {
        val start = RoomChoreography.Point(.83f, .73f)
        val end = RoomChoreography.Point(-1.28f, .16f)
        val route = RoomChoreography.route(start, end)
        assertEquals(listOf(RoomChoreography.Point(.83f, 1.12f), RoomChoreography.Point(-1.28f, 1.12f), end), route)
        assertTrue(RoomChoreography.route(start, start).isEmpty())
    }

    @Test fun equippedFurnitureAndPropDriveBoundedGroundedInteractions() {
        val cases = listOf(
            Triple("bigFurniture.sofa", "floorProp.plant", setOf("rest", "water")),
            Triple("bigFurniture.piano", "floorProp.puppy", setOf("piano", "pet")),
            Triple("bigFurniture.bookshelf", "floorProp.toybox", setOf("read", "play"))
        )
        cases.forEach { (furniture, prop, expected) ->
            val subject = RoomChoreography()
            subject.configure(mapOf("bigFurniture" to furniture, "floorProp" to prop), false)
            val observed = mutableSetOf<String>()
            repeat(3_600) {
                val pose = subject.sample(.05f)
                observed += pose.activity
                assertTrue(pose.point.x in -1.8f..1.0f)
                assertTrue(pose.point.z in -.8f..1.13f)
                assertTrue(pose.height in 0f..0.6f)
                if (pose.activity != "rest") assertEquals(0f, pose.height, 0f)
                assertTrue(pose.angle.isFinite())
            }
            assertTrue("Missing interaction $expected in $observed", observed.containsAll(expected))
        }
    }

    @Test fun hiddenRoomClockAndRapidTapsCannotAdvanceOrQueuePoses() {
        val subject = RoomChoreography()
        subject.configure(mapOf("floorProp" to "floorProp.books"), false)
        repeat(70) { subject.sample(.05f) }
        val before = subject.pose.copy()
        repeat(100) { subject.sample(0f) }
        assertEquals(before, subject.pose)
        assertTrue(subject.react())
        repeat(100) { assertFalse(subject.react()) }
        repeat(80) { subject.sample(.05f) }
        assertTrue(subject.react())
    }

    @Test fun replacingSofaDuringRestResetsToSafeFloorWaypoint() {
        val subject = RoomChoreography()
        subject.configure(mapOf("bigFurniture" to "bigFurniture.sofa"), false)
        var found = false
        repeat(2_000) {
            if (!found && subject.sample(.05f).seated > .8f) found = true
        }
        assertTrue(found)
        subject.configure(mapOf("bigFurniture" to "bigFurniture.desk"), true)
        val pose = subject.sample(0f)
        assertEquals(RoomChoreography.HOME, pose.point)
        assertEquals(0f, pose.height, 0f)
        assertEquals(0f, pose.seated, 0f)
    }
}
