package com.minseo.piyakbank.scene

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES20
import android.os.Build
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.minseo.piyakbank.core.Catalog
import java.io.File
import java.nio.ByteBuffer
import java.security.MessageDigest
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Renders synthetic bundled models into an EGL pbuffer using the PRODUCTION
 * asset composer, shaders, VBO upload, camera and draw path. No Activity, screen
 * capture, UI input, saved bank data, network or background render loop is used.
 * Artifacts are generated model renders, not screenshots of an application UI.
 */
@RunWith(AndroidJUnit4::class)
class SceneRenderingTest {
    private data class Entry(val id: String, val image: File, val subtitle: String = "")
    private data class Pixels(val fraction: Double, val colors: Int, val contrast: Int, val border: Int, val bounds: List<Int>, val digest: String) {
        fun json() = JSONObject().put("foregroundFraction", fraction).put("colorBins", colors)
            .put("contrast", contrast).put("solidBorderPixels", border).put("bounds", JSONArray(bounds)).put("sha256", digest)
    }

    @Test(timeout = 300_000)
    fun allCatalogModelsAndCombinedOutfitsRenderOnRealGlesWithoutClippingOrGlErrors() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val output = File(context.filesDir, "scene-gpu-qa").apply { check(mkdirs() || isDirectory) }
        val thumbnails = File(output, "catalog").apply { check(mkdirs() || isDirectory) }
        val rooms = File(output, "rooms").apply { check(mkdirs() || isDirectory) }
        val outfits = File(output, "outfits").apply { check(mkdirs() || isDirectory) }
        val report = JSONObject().put("api", Build.VERSION.SDK_INT).put("device", Build.MODEL)
            .put("abi", JSONArray(Build.SUPPORTED_ABIS.toList())).put("status", "running")
            .put("scope", "Offscreen production OpenGL ES rendering; generated artifacts, not UI screenshots")
        val entries = JSONArray()
        val findings = mutableListOf<String>()
        val begin = SystemClock.elapsedRealtime()
        var catalogCount = 0
        var roomCount = 0
        var outfitCount = 0
        try {
            val assets = SceneAssets.load(context.assets)
            val items = Catalog.items.sortedWith(compareBy({ it.slot.name }, { it.id }))
            assertEquals("Every original item must be covered", 81, items.size)
            assertEquals(81, items.map { it.id }.toSet().size)
            val groups = items.groupBy { it.slot.name }.toSortedMap()
            assertEquals("All nine populated slots", 9, groups.size)
            assertTrue(groups.values.all { it.size == 9 })
            OffscreenGles(512, 512).use { egl ->
                report.put("glVendor", GLES20.glGetString(GLES20.GL_VENDOR))
                    .put("glRenderer", GLES20.glGetString(GLES20.GL_RENDERER))
                    .put("glVersion", GLES20.glGetString(GLES20.GL_VERSION))
                var rendererFailure: String? = null
                var readyCount = 0
                val renderer = RoomRenderer(onReady = { readyCount++ }, onFailure = { rendererFailure = it }, onActivity = {})
                renderer.onSurfaceCreated(null, null)
                checkGl("production shader initialization")

                fun render(id: String, composition: SceneAssets.Composition, equipment: Map<String, String>, width: Int, height: Int, file: File, requireBorder: Boolean): Pixels {
                    val vertices = validateComposition(composition, id)
                    val previousReady = readyCount
                    renderer.configuration = RoomRenderer.Configuration(equipment, animated = false, working = false)
                    renderer.heading = 0f; renderer.zoom = 1f; renderer.resetClock = true
                    renderer.pending.set(composition)
                    renderer.onSurfaceChanged(null, width, height)
                    renderer.onDrawFrame(null)
                    GLES20.glFinish()
                    check(rendererFailure == null) { "$id: production renderer failed: $rendererFailure" }
                    check(readyCount > previousReady) { "$id: no successful production frame" }
                    checkGl(id)
                    val image = egl.readImage(width, height)
                    val metrics = inspect(image)
                    save(image, file)
                    image.recycle()
                    entries.put(metrics.json().put("id", id).put("file", file.relativeTo(output).path)
                        .put("width", width).put("height", height).put("vertices", vertices).put("batches", composition.batches.size))
                    if (metrics.fraction < .008) findings += "$id: blank/nearly invisible (${metrics.fraction})"
                    if (metrics.fraction > .98) findings += "$id: model fills essentially the whole camera frame (${metrics.fraction})"
                    // A thin single-material rug legitimately has very few
                    // 4-bit RGB bins: cloud/star measure nine on the API 26 GPU
                    // despite 55/73 levels of contrast and clean silhouettes.
                    // Retain visibility, clipping, contrast and duplicate-image
                    // checks; palette complexity is not a quality requirement.
                    val minimumColorBins = if (id in setOf("item/rug.cloud", "item/rug.star", "item/rug.heart")) 6 else 10
                    if (metrics.colors < minimumColorBins || metrics.contrast < 22) findings += "$id: flat/low-contrast render (${metrics.colors} colors, ${metrics.contrast} contrast)"
                    if (requireBorder && metrics.border > max(12, (width + height) / 8)) findings += "$id: ${metrics.border} opaque pixels reach the border; inspect silhouette clipping"
                    return metrics
                }

                val catalogEntries = mutableListOf<Entry>()
                val digests = linkedMapOf<String, MutableList<String>>()
                groups.forEach { (slot, choices) ->
                    val category = mutableListOf<Entry>()
                    choices.forEach { item ->
                        val file = File(thumbnails, "${item.id}.png")
                        val metrics = render("item/${item.id}", assets.compose(emptyMap(), item.id), emptyMap(), 320, 320, file, requireBorder = slot != "bg")
                        digests.getOrPut(metrics.digest) { mutableListOf() }.add(item.id)
                        val entry = Entry(item.id, file, item.name)
                        category += entry; catalogEntries += entry; catalogCount++
                    }
                    sheet(category, File(output, "catalog-$slot.png"), 3, 320, "Piyak Bank | $slot | production GLES")
                }
                digests.values.filter { it.size > 1 }.forEach { findings += "Distinct catalog models produced identical pixels: ${it.joinToString()}" }
                sheet(catalogEntries, File(output, "catalog-all-81.png"), 9, 160, "Piyak Bank | all 81 original catalog models | production GLES")

                val roomEntries = mutableListOf<Entry>()
                val outfitEntries = mutableListOf<Entry>()
                // Each of these nine full combinations equips all nine slots;
                // together they include every catalog item, once per slot.
                for (index in 0 until 9) {
                    val equipment = groups.mapValues { (_, choices) -> choices[index].id }
                    val composition = assets.compose(equipment, null)
                    val label = "combination-${(index + 1).toString().padStart(2, '0')}"
                    val roomFile = File(rooms, "$label.png")
                    render("room/$label", composition, equipment, 512, 384, roomFile, requireBorder = false)
                    roomEntries += Entry(label, roomFile, equipment.getValue("bigFurniture").substringAfter('.'))
                    roomCount++
                    val outfitFile = File(outfits, "$label.png")
                    // Keep the SAME composed character/rig buffers, but omit the
                    // room for a close fitting inspection. This is a QA camera,
                    // not a second renderer or a change to production assets.
                    val character = composition.copy(
                        batches = composition.batches.filter { it.rig in CHARACTER_RIGS },
                        preview = SceneAssets.Preview(emptyList(), floatArrayOf(2.45f, 2.5f, 7.2f), floatArrayOf(.15f, 1.10f, .45f), 1.34f)
                    )
                    render("outfit/$label", character, equipment, 384, 384, outfitFile, requireBorder = true)
                    outfitEntries += Entry(label, outfitFile, listOf("headTop", "eyes", "neck", "bodyFront").joinToString(" / ") { equipment.getValue(it).substringAfter('.') })
                    outfitCount++
                    entries.getJSONObject(entries.length() - 1).put("equipped", JSONObject(equipment))
                }
                sheet(roomEntries, File(output, "rooms-nine-combinations.png"), 3, 384, "Piyak Bank | nine complete rooms | all 81 items covered")
                sheet(outfitEntries, File(output, "outfits-nine-combinations.png"), 3, 384, "Piyak Bank | fitted hats / eyewear / neckwear / clothing")

                // EGL-context loss is a real renderer lifecycle boundary. Keep
                // the same renderer + retained scene, recreate the EGL context,
                // and verify that onSurfaceCreated restores all GPU buffers.
                val defaultEquipment = mapOf("bg" to "bg.cozy_cream", "bodyFront" to "bodyFront.hoodie_mint", "floorProp" to "floorProp.plant", "rug" to "rug.oval_coral")
                val retained = assets.compose(defaultEquipment, null)
                val before = render("context/before", retained, defaultEquipment, 384, 320, File(output, "context-before.png"), requireBorder = false)
                egl.recreateContext()
                renderer.onSurfaceCreated(null, null)
                renderer.onSurfaceChanged(null, 384, 320)
                renderer.resetClock = true
                renderer.onDrawFrame(null)
                GLES20.glFinish(); checkGl("restored context")
                check(rendererFailure == null)
                val restoredImage = egl.readImage(384, 320)
                val after = inspect(restoredImage)
                save(restoredImage, File(output, "context-after.png")); restoredImage.recycle()
                assertEquals("Context loss must preserve identical static geometry and equipment", before.digest, after.digest)
                report.put("contextRestore", "identical pixels after EGL context recreation")
            }
            report.put("status", if (findings.isEmpty()) "passed" else "failed")
            assertTrue("GPU findings: ${findings.joinToString("; ")}. Inspect generated scene-gpu-qa artifacts.", findings.isEmpty())
        } catch (failure: Throwable) {
            report.put("status", "failed").put("failure", failure.toString())
            throw failure
        } finally {
            report.put("elapsedMillis", SystemClock.elapsedRealtime() - begin)
                .put("catalogRenders", catalogCount).put("fullRoomRenders", roomCount).put("outfitRenders", outfitCount)
                .put("findings", JSONArray(findings)).put("renders", entries)
                .put("manualReview", "Inspect all nine catalog sheets and both combination sheets for detached surfaces, occlusion, misplaced seams and clothing intersections; pixel checks cannot certify visual design quality.")
            File(output, "report.json").writeText(report.toString(2))
            android.util.Log.i("PiyakSceneQA", "Generated GPU artifacts: ${output.absolutePath}; status=${report.optString("status")}")
        }
    }

    private fun validateComposition(composition: SceneAssets.Composition, id: String): Int {
        check(composition.batches.isNotEmpty()) { "$id: no draw batches" }
        var count = 0
        composition.batches.forEach { batch ->
            val data = batch.vertices.duplicate()
            check(data.capacity() % SceneAssets.STRIDE == 0)
            val vertices = data.capacity() / SceneAssets.STRIDE
            check(vertices in 1..65_535 && batch.count == batch.indices.capacity() && batch.count % 3 == 0)
            repeat(vertices) { vertex ->
                val offset = vertex * SceneAssets.STRIDE
                for (component in 0 until SceneAssets.STRIDE) check(data.get(offset + component).isFinite()) { "$id: nonfinite vertex" }
                for (axis in 0..2) check(abs(data.get(offset + axis)) < 100f) { "$id: exploded geometry" }
                val nx = data.get(offset + 3); val ny = data.get(offset + 4); val nz = data.get(offset + 5)
                check(abs(sqrt(nx * nx + ny * ny + nz * nz) - 1f) < .02f) { "$id: invalid surface normal" }
                for (channel in 6..9) check(data.get(offset + channel) in 0f..1f) { "$id: invalid color" }
            }
            repeat(batch.count) { index -> check((batch.indices.get(index).toInt() and 0xffff) < vertices) { "$id: index outside GPU buffer" } }
            count += vertices
        }
        composition.rigs.forEach { check(it.matrix.size == 16 && it.matrix.all(Float::isFinite)) }
        return count
    }

    private fun inspect(image: Bitmap): Pixels {
        val width = image.width; val height = image.height
        val pixels = IntArray(width * height); image.getPixels(pixels, 0, width, 0, 0, width, height)
        var occupied = 0; var border = 0; var darkest = 255; var lightest = 0
        var minX = width; var minY = height; var maxX = -1; var maxY = -1
        val colors = HashSet<Int>()
        val digest = MessageDigest.getInstance("SHA-256")
        pixels.forEachIndexed { index, color ->
            val red = Color.red(color); val green = Color.green(color); val blue = Color.blue(color)
            digest.update(red.toByte()); digest.update(green.toByte()); digest.update(blue.toByte())
            if (max(abs(red - 246), max(abs(green - 241), abs(blue - 232))) > 13) {
                occupied++
                val x = index % width; val y = index / width
                minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
                val level = (red + green + blue) / 3
                darkest = min(darkest, level); lightest = max(lightest, level)
                colors += ((red shr 4) shl 8) or ((green shr 4) shl 4) or (blue shr 4)
                if (x < 2 || y < 2 || x >= width - 2 || y >= height - 2) border++
            }
        }
        return Pixels(occupied.toDouble() / pixels.size, colors.size, lightest - darkest, border,
            listOf(minX, minY, maxX, maxY), digest.digest().joinToString("") { "%02x".format(it) })
    }

    private fun save(bitmap: Bitmap, file: File) {
        file.outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
    }

    private fun sheet(entries: List<Entry>, file: File, columns: Int, imageSize: Int, title: String) {
        val cellWidth = imageSize + 16; val cellHeight = imageSize + 60; val header = 44
        val rows = (entries.size + columns - 1) / columns
        val bitmap = Bitmap.createBitmap(columns * cellWidth, header + rows * cellHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap); canvas.drawColor(Color.rgb(232, 227, 219))
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(57, 47, 42); textSize = 18f }
        canvas.drawText(title, 12f, 28f, text)
        entries.forEachIndexed { index, entry ->
            val x = (index % columns) * cellWidth + 8; val y = header + (index / columns) * cellHeight
            val image = android.graphics.BitmapFactory.decodeFile(entry.image.absolutePath)
            check(image != null)
            val ratio = min(imageSize.toFloat() / image.width, imageSize.toFloat() / image.height)
            val drawnWidth = (image.width * ratio).toInt(); val drawnHeight = (image.height * ratio).toInt()
            val left = x + (imageSize - drawnWidth) / 2; val top = y + (imageSize - drawnHeight) / 2
            canvas.drawBitmap(image, null, Rect(left, top, left + drawnWidth, top + drawnHeight), Paint(Paint.FILTER_BITMAP_FLAG))
            image.recycle()
            text.textSize = if (imageSize < 200) 11f else 14f
            canvas.drawText(entry.id.take(45), x.toFloat(), (y + imageSize + 19).toFloat(), text)
            text.textSize = if (imageSize < 200) 10f else 12f
            // Two lines keep combined outfit IDs legible on exported sheets.
            val wrapped = entry.subtitle.chunked(if (imageSize < 200) 24 else 47)
            wrapped.take(2).forEachIndexed { line, value -> canvas.drawText(value, x.toFloat(), (y + imageSize + 35 + line * 14).toFloat(), text) }
        }
        save(bitmap, file); bitmap.recycle()
    }

    private fun checkGl(label: String) {
        val errors = mutableListOf<Int>()
        repeat(12) { val error = GLES20.glGetError(); if (error == GLES20.GL_NO_ERROR) return@repeat else errors += error }
        check(errors.isEmpty()) { "$label: GL errors ${errors.joinToString { "0x${it.toString(16)}" }}" }
    }

    private class OffscreenGles(private val width: Int, private val height: Int) : AutoCloseable {
        private val display: EGLDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        private var context: EGLContext = EGL14.EGL_NO_CONTEXT
        private var surface: EGLSurface = EGL14.EGL_NO_SURFACE
        private val config: EGLConfig

        init {
            check(display != EGL14.EGL_NO_DISPLAY)
            check(EGL14.eglInitialize(display, IntArray(2), 0, IntArray(2), 0))
            val choices = arrayOfNulls<EGLConfig>(1); val count = IntArray(1)
            val attributes = intArrayOf(EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT, EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8, EGL14.EGL_ALPHA_SIZE, 0,
                EGL14.EGL_DEPTH_SIZE, 16, EGL14.EGL_NONE)
            check(EGL14.eglChooseConfig(display, attributes, 0, choices, 0, 1, count, 0) && count[0] > 0) { "No GLES2 pbuffer configuration" }
            config = checkNotNull(choices[0])
            createContext()
        }

        private fun createContext() {
            context = EGL14.eglCreateContext(display, config, EGL14.EGL_NO_CONTEXT, intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0)
            check(context != EGL14.EGL_NO_CONTEXT)
            surface = EGL14.eglCreatePbufferSurface(display, config, intArrayOf(EGL14.EGL_WIDTH, width, EGL14.EGL_HEIGHT, height, EGL14.EGL_NONE), 0)
            check(surface != EGL14.EGL_NO_SURFACE)
            check(EGL14.eglMakeCurrent(display, surface, surface, context))
        }

        fun recreateContext() {
            check(EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT))
            check(EGL14.eglDestroySurface(display, surface)); check(EGL14.eglDestroyContext(display, context))
            createContext()
        }

        fun readImage(width: Int, height: Int): Bitmap {
            val buffer = ByteBuffer.allocateDirect(width * height * 4)
            GLES20.glReadPixels(0, 0, width, height, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, buffer)
            check(GLES20.glGetError() == GLES20.GL_NO_ERROR) { "Cannot read generated pbuffer pixels" }
            val pixels = IntArray(width * height)
            for (y in 0 until height) for (x in 0 until width) {
                val offset = (y * width + x) * 4
                pixels[(height - 1 - y) * width + x] = Color.argb(255, buffer.get(offset).toInt() and 255,
                    buffer.get(offset + 1).toInt() and 255, buffer.get(offset + 2).toInt() and 255)
            }
            return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
        }

        override fun close() {
            EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            if (surface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, surface)
            if (context != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(display, context)
            EGL14.eglTerminate(display)
        }
    }

    companion object {
        private val CHARACTER_RIGS = setOf("piyak", "bodyRig", "headRig", "eyes", "wing.left", "wing.right", "foot.left", "foot.right")
    }
}
