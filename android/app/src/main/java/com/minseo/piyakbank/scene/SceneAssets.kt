package com.minseo.piyakbank.scene

import android.content.res.AssetManager
import android.opengl.Matrix
import org.json.JSONArray
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.ShortBuffer

/** Exact, bundled geometry exported from the project's original SceneKit source. */
internal class SceneAssets private constructor(
    val rigs: List<Rig>,
    private val base: List<Instance>,
    private val rooms: Map<String, List<Instance>>,
    private val items: Map<String, Delta>,
    private val previews: Map<String, Preview>,
    private val effects: Map<String, List<Instance>>,
    private val meshes: List<Mesh>
) {
    data class Rig(val name: String, val parent: String, val matrix: FloatArray)
    data class Instance(val key: String, val mesh: Int, val rig: String, val matrix: FloatArray, val color: FloatArray, val label: String)
    data class Delta(val add: List<Instance>, val remove: Set<String>)
    data class Preview(val instances: List<Instance>, val camera: FloatArray, val target: FloatArray, val scale: Float)
    data class Mesh(val vertices: FloatArray, val indices: ShortArray)
    data class Batch(val rig: String, val vertices: FloatBuffer, val indices: ShortBuffer, val count: Int, val center: FloatArray)
    data class Composition(val batches: List<Batch>, val rigs: List<Rig>, val preview: Preview?)

    fun compose(equipped: Map<String, String>, previewId: String?): Composition {
        val preview = previewId?.let(previews::get)
        val selected = if (preview != null) preview.instances else {
            val deltas = equipped.filter { (slot, id) -> id.substringBefore('.') == slot }.values.mapNotNull(items::get)
            val removed = deltas.flatMap { it.remove }.toSet()
            (rooms[equipped["bg"]] ?: rooms.getValue("bg.cozy_cream")) + base.filterNot { it.key in removed } + deltas.flatMap { it.add }
        }
        val groups = linkedMapOf<String, MutableList<Instance>>()
        selected.forEach { instance ->
            val moving = instance.label.takeIf { label -> listOf("plant.leaf.", "puppy.tail", "piano.key.", "balloon.").any(label::startsWith) }
            val key = if (preview == null && moving != null) "prop:$moving" else instance.rig
            groups.getOrPut(key) { mutableListOf() }.add(instance)
        }
        if (preview == null) effects.forEach { (name, instances) -> groups["effect:$name"] = instances.toMutableList() }
        val batches = groups.flatMap { (rig, instances) -> bake(rig, instances) } + if (preview == null) listOf(shadow()) else emptyList()
        return Composition(batches, rigs, preview)
    }

    private fun shadow(): Batch {
        val segments = 40
        val vertices = ByteBuffer.allocateDirect((segments + 2) * STRIDE * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        vertices.put(floatArrayOf(0f, -.019f, 0f, 0f, 1f, 0f, .30f, .24f, .25f, .18f))
        for (i in 0..segments) {
            val angle = i * kotlin.math.PI * 2 / segments
            vertices.put(floatArrayOf(kotlin.math.cos(angle).toFloat() * .53f, -.019f, kotlin.math.sin(angle).toFloat() * .38f, 0f, 1f, 0f, .30f, .24f, .25f, 0f))
        }
        val indices = ByteBuffer.allocateDirect(segments * 3 * 2).order(ByteOrder.nativeOrder()).asShortBuffer()
        for (i in 0 until segments) { indices.put(0); indices.put((i + 1).toShort()); indices.put((i + 2).toShort()) }
        vertices.position(0); indices.position(0)
        return Batch("shadow", vertices, indices, segments * 3, floatArrayOf(0f, 0f, 0f))
    }

    /** Bake static transforms once, retain only eight live character rig transforms per frame. */
    private fun bake(rig: String, instances: List<Instance>): List<Batch> {
        val result = mutableListOf<Batch>()
        val vertices = ArrayList<Float>()
        val indices = ArrayList<Short>()
        var low = floatArrayOf(Float.MAX_VALUE, Float.MAX_VALUE, Float.MAX_VALUE)
        var high = floatArrayOf(-Float.MAX_VALUE, -Float.MAX_VALUE, -Float.MAX_VALUE)
        fun flush() {
            if (indices.isEmpty()) return
            val v = ByteBuffer.allocateDirect(vertices.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
            vertices.forEach(v::put); v.position(0)
            val i = ByteBuffer.allocateDirect(indices.size * 2).order(ByteOrder.nativeOrder()).asShortBuffer()
            indices.forEach(i::put); i.position(0)
            result += Batch(rig, v, i, indices.size, FloatArray(3) { (low[it] + high[it]) / 2f })
            vertices.clear(); indices.clear()
            low = floatArrayOf(Float.MAX_VALUE, Float.MAX_VALUE, Float.MAX_VALUE)
            high = floatArrayOf(-Float.MAX_VALUE, -Float.MAX_VALUE, -Float.MAX_VALUE)
        }
        val inverse = FloatArray(16)
        instances.forEach { instance ->
            val mesh = meshes[instance.mesh]
            val count = mesh.vertices.size / 6
            if (vertices.size / STRIDE + count > 65_535) flush()
            val offset = vertices.size / STRIDE
            check(Matrix.invertM(inverse, 0, instance.matrix, 0)) { "Singular model transform" }
            val m = instance.matrix
            for (i in 0 until count) {
                val source = i * 6
                val x = mesh.vertices[source]; val y = mesh.vertices[source + 1]; val z = mesh.vertices[source + 2]
                val p = floatArrayOf(m[0]*x + m[4]*y + m[8]*z + m[12], m[1]*x + m[5]*y + m[9]*z + m[13], m[2]*x + m[6]*y + m[10]*z + m[14])
                for (axis in 0..2) { vertices += p[axis]; low[axis] = minOf(low[axis], p[axis]); high[axis] = maxOf(high[axis], p[axis]) }
                val nx = mesh.vertices[source + 3]; val ny = mesh.vertices[source + 4]; val nz = mesh.vertices[source + 5]
                val normal = floatArrayOf(inverse[0]*nx + inverse[1]*ny + inverse[2]*nz, inverse[4]*nx + inverse[5]*ny + inverse[6]*nz, inverse[8]*nx + inverse[9]*ny + inverse[10]*nz)
                val length = kotlin.math.sqrt(normal.sumOf { (it * it).toDouble() }).toFloat().coerceAtLeast(0.00001f)
                normal.forEach { vertices += it / length }
                instance.color.forEach { vertices += it }
            }
            mesh.indices.forEach { indices += ((it.toInt() and 0xffff) + offset).toShort() }
        }
        flush()
        return result
    }

    companion object {
        const val STRIDE = 10
        @Volatile private var cached: SceneAssets? = null
        @Synchronized fun load(assets: AssetManager): SceneAssets {
            cached?.let { return it }
            val json = assets.open("scene/scene.json").bufferedReader().use { JSONObject(it.readText()) }
            check(json.getInt("version") == 1)
            val meshCount = json.getInt("meshCount").also { check(it in 1..10_000) }
            val raw = assets.open("scene/meshes.bin").use { it.readBytes() }
            check(raw.size <= 96 * 1024 * 1024) { "Scene exceeds memory budget" }
            val buffer = ByteBuffer.wrap(raw).order(ByteOrder.LITTLE_ENDIAN)
            val meshes = List(meshCount) {
                val vertexCount = buffer.int.also { check(it in 1..65_535) }
                val indexCount = buffer.int.also { check(it in 3..3_000_000 && it % 3 == 0) }
                check(buffer.remaining() >= vertexCount * 24 + indexCount * 2)
                val vertices = FloatArray(vertexCount * 6) { buffer.float.also { value -> check(value.isFinite()) } }
                val indices = ShortArray(indexCount) { buffer.short.also { value -> check((value.toInt() and 0xffff) < vertexCount) } }
                Mesh(vertices, indices)
            }
            check(!buffer.hasRemaining())
            fun instances(array: JSONArray): List<Instance> = List(array.length()) { index ->
                val item = array.getJSONObject(index)
                Instance(item.getString("key"), item.getInt("mesh").also { check(it in meshes.indices) }, item.getString("rig"), item.getJSONArray("matrix").floats(16), item.getJSONArray("color").floats(4), item.optString("label"))
            }
            val rigs = json.getJSONArray("rigs").let { array -> List(array.length()) { i -> array.getJSONObject(i).let { Rig(it.getString("name"), it.getString("parent"), it.getJSONArray("matrix").floats(16)) } } }
            val rooms = json.getJSONObject("rooms").mapObjects { _, value -> instances(value as JSONArray) }
            val items = json.getJSONObject("items").mapObjects { _, value ->
                val item = value as JSONObject
                val removed = item.getJSONArray("remove")
                Delta(instances(item.getJSONArray("add")), (0 until removed.length()).map { removed.getString(it) }.toSet())
            }
            check(items.size == 81 && rooms.size == 9)
            val previews = json.getJSONObject("previews").mapObjects { _, value ->
                val item = value as JSONObject
                Preview(instances(item.getJSONArray("instances")), item.getJSONArray("camera").floats(3), item.getJSONArray("target").floats(3), item.getDouble("scale").toFloat().also { check(it.isFinite() && it > 0) })
            }
            val effects = json.getJSONObject("effects").mapObjects { _, value -> instances(value as JSONArray) }
            return SceneAssets(rigs, instances(json.getJSONArray("base")), rooms, items, previews, effects, meshes).also { cached = it }
        }
        private fun JSONArray.floats(count: Int): FloatArray {
            check(length() == count)
            return FloatArray(count) { getDouble(it).toFloat().also { value -> check(value.isFinite()) } }
        }
        private fun <T> JSONObject.mapObjects(transform: (String, Any) -> T): Map<String, T> = keys().asSequence().associateWith { transform(it, get(it)) }
    }
}
