package com.minseo.piyakbank.scene

import kotlin.math.*

/** Scene-clock choreography. No timer, work reward clock or Android lifecycle dependency. */
internal class RoomChoreography {
    data class Point(val x: Float, val z: Float) {
        fun distance(other: Point) = hypot(other.x - x, other.z - z)
    }
    data class Visit(val activity: String, val point: Point, val facing: Point, val duration: Float)
    data class Pose(
        var point: Point = HOME, var height: Float = 0f, var angle: Float = 0.18f,
        var gait: Float = 0f, var activity: String = "greet", var progress: Float = 0f,
        var envelope: Float = 0f, var blink: Float = 1f, var seated: Float = 0f
    )
    private data class Step(val from: Point, val to: Point, val duration: Float, val visit: Visit? = null)
    private var equipment = emptyMap<String, String>()
    private var working = false
    private var steps = emptyList<Step>()
    private var index = 0
    private var elapsed = 0f
    private var clock = 0f
    private var angle = .18f
    private var reacting = false
    private var reactionSequence = 0
    var pose = Pose(); private set

    fun configure(equipped: Map<String, String>, working: Boolean) {
        if (equipment == equipped && this.working == working && steps.isNotEmpty()) return
        equipment = equipped.toMap(); this.working = working
        // A new configuration starts from a safe grounded waypoint; no resumed
        // furniture pose can retain an old item's seat height.
        pose = Pose(); angle = .18f; reacting = false
        rebuild(HOME, itinerary())
    }

    fun react(): Boolean {
        if (reacting || pose.seated > 0.01f) return false
        val point = pose.point
        val choices = listOf(Visit("greet", point, Point(2f, 6f), 2.4f), Visit("celebrate", point, Point(2f, 6f), 2.8f)) + itinerary().filter { it.activity !in listOf("greet", "look", "stretch") }
        val selected = choices[reactionSequence++ % choices.size]
        rebuild(point, listOf(selected)); reacting = true
        return true
    }

    fun sample(delta: Float): Pose {
        val dt = delta.coerceIn(0f, 0.1f)
        clock += dt; elapsed += dt
        if (steps.isEmpty()) rebuild(HOME, itinerary())
        while (elapsed >= steps[index].duration) {
            elapsed -= steps[index].duration
            val endpoint = steps[index].to
            index++
            if (index >= steps.size) { reacting = false; rebuild(endpoint, itinerary()) }
        }
        val step = steps[index]
        val fraction = (elapsed / step.duration).coerceIn(0f, 1f)
        val result = Pose(point = Point(step.from.x + (step.to.x - step.from.x) * fraction, step.from.z + (step.to.z - step.from.z) * fraction))
        val visit = step.visit
        val targetAngle = if (visit == null) heading(step.from, step.to) else heading(visit.point, visit.facing)
        angle += atan2(sin(targetAngle - angle), cos(targetAngle - angle)) * min(1f, dt * 8f)
        result.angle = angle
        result.progress = elapsed
        result.envelope = min(smooth(elapsed / .5f), smooth((step.duration - elapsed) / .5f))
        if (visit == null) {
            result.activity = "walk"
            result.gait = sin(elapsed * PI.toFloat() * 2 / .56f) * min(smooth(elapsed / .18f), smooth((step.duration - elapsed) / .18f))
        } else {
            result.activity = visit.activity
            if (visit.activity == "rest") {
                val seated = min(smooth(elapsed / 1.25f), smooth((step.duration - elapsed) / 1.25f))
                result.seated = seated
                result.point = Point(visit.point.x + (-1.57f - visit.point.x) * seated, visit.point.z + (-.77f - visit.point.z) * seated)
                result.height = .49f * seated + sin(seated * PI.toFloat()) * .1f
                result.angle += atan2(sin(.18f - result.angle), cos(.18f - result.angle)) * seated
            }
        }
        val blinkPhase = (clock + 2.4f) % 4.8f
        result.blink = 1f - .94f * max(0f, 1f - abs(blinkPhase - 2.7f) / .11f)
        if (result.seated > .99f) result.blink = .15f
        pose = result
        return result
    }

    private fun rebuild(start: Point, visits: List<Visit>) {
        val next = mutableListOf<Step>(); var cursor = start
        visits.forEach { visit ->
            route(cursor, visit.point).forEach { point ->
                next += Step(cursor, point, max(.55f, cursor.distance(point) / if (working) .42f else .36f)); cursor = point
            }
            next += Step(cursor, cursor, visit.duration, visit)
        }
        steps = next; index = 0; elapsed = 0f
    }

    private fun itinerary(): List<Visit> = buildList {
        add(Visit("greet", HOME, Point(2f, 6f), 4f))
        val prop = equipment["floorProp"]?.let { id ->
            val activity = when (id) {
                "floorProp.plant", "floorProp.cactus" -> "water"
                "floorProp.books" -> "read"
                "floorProp.puppy" -> "pet"
                "floorProp.balloons", "floorProp.toybox" -> "play"
                "floorProp.coin_pile" -> "tidy"
                else -> "inspect"
            }
            Visit(activity, Point(.83f, .73f), Point(1.65f, .5f), 7f)
        }
        val furniture = equipment["bigFurniture"]?.let { id ->
            val activity = when (id) {
                "bigFurniture.sofa" -> "rest"
                "bigFurniture.piano" -> "piano"
                "bigFurniture.desk" -> if (working) "work" else "read"
                "bigFurniture.bookshelf", "bigFurniture.shelf" -> "read"
                "bigFurniture.tv" -> "watch"
                else -> "tidy"
            }
            Visit(activity, Point(-1.28f, .16f), Point(-1.45f, -.9f), 9f)
        }
        if (working && furniture != null) add(furniture)
        if (prop != null) add(prop)
        add(Visit("look", Point(-.45f, 1.12f), Point(-2f, 2f), 3f))
        if (!working && furniture != null) add(furniture)
        add(Visit("stretch", Point(.05f, .66f), Point(2f, 6f), 5f))
        add(Visit("look", Point(.58f, 1.12f), Point(2f, -1f), 3f))
    }

    companion object {
        val HOME = Point(.15f, .45f)
        fun route(start: Point, end: Point): List<Point> {
            if (start.distance(end) <= .025f) return emptyList()
            if (abs(start.x - end.x) < .025f) return listOf(end)
            var cursor = start
            return listOf(Point(start.x, 1.12f), Point(end.x, 1.12f), end).filter { next ->
                if (cursor.distance(next) > .025f) { cursor = next; true } else false
            }
        }
        private fun heading(from: Point, to: Point) = atan2(to.x - from.x, to.z - from.z)
        fun smooth(value: Float): Float { val v = value.coerceIn(0f, 1f); return v * v * (3 - 2 * v) }
        fun title(activity: String) = when (activity) {
            "walk", "look" -> "우리 방을 산책하는 중"
            "water" -> "초록 친구에게 물 주는 중"
            "read" -> "좋아하는 책을 읽는 중"
            "work" -> "책상에서 꼼지락꼼지락"
            "piano" -> "작은 연주회를 여는 중"
            "rest" -> "소파에서 잠깐 쉬는 중"
            "pet" -> "강아지 친구를 쓰다듬는 중"
            "play" -> "장난감을 가지고 노는 중"
            "tidy" -> "내 물건을 가지런히 정리하는 중"
            "stretch" -> "쭉쭉, 기지개 켜는 중"
            "celebrate" -> "같이 놀아 주니 신나!"
            "watch" -> "재미있는 장면을 구경하는 중"
            "inspect" -> "새로운 소품을 살펴보는 중"
            else -> "반가워! 오늘도 함께해"
        }
    }
}
