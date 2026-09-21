package com.minseo.piyakbank.scene

import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import android.os.SystemClock
import java.util.concurrent.atomic.AtomicReference
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.*

internal class RoomRenderer(
    private val onReady: () -> Unit,
    private val onFailure: (String) -> Unit,
    private val onActivity: (String) -> Unit
) : GLSurfaceView.Renderer {
    data class Configuration(val equipped: Map<String, String>, val animated: Boolean, val working: Boolean)
    private data class GPU(val batch: SceneAssets.Batch, val vertex: Int, val index: Int)
    val pending = AtomicReference<SceneAssets.Composition?>(null)
    @Volatile var configuration = Configuration(emptyMap(), false, false)
    @Volatile var heading = 0f
    @Volatile var zoom = 1f
    @Volatile var interactionRequested = false
    @Volatile var resetClock = true
    private var scene: SceneAssets.Composition? = null
    private var gpu = emptyList<GPU>()
    private var program = 0
    private var positionLocation = -1
    private var normalLocation = -1
    private var colorLocation = -1
    private var matrixLocation = -1
    private var normalMatrixLocation = -1
    private var viewProjectionLocation = -1
    private var alphaLocation = -1
    private var width = 1
    private var height = 1
    private var clock = 0L
    private var failed = false
    private var ready = false
    private var activity = ""
    private val choreography = RoomChoreography()
    private val view = FloatArray(16)
    private val projection = FloatArray(16)
    private val viewProjection = FloatArray(16)
    private val model = FloatArray(16)
    private val inverse = FloatArray(16)
    private val normalMatrix = FloatArray(9)
    private val rigMatrices = linkedMapOf<String, FloatArray>()

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        try {
            failed = false; ready = false; resetClock = true
            // The EGL context may have been evicted in the background. Old VBO
            // names are invalid; re-upload the retained composition exactly once.
            gpu = emptyList()
            program = createProgram()
            positionLocation = GLES20.glGetAttribLocation(program, "aPosition")
            normalLocation = GLES20.glGetAttribLocation(program, "aNormal")
            colorLocation = GLES20.glGetAttribLocation(program, "aColor")
            matrixLocation = GLES20.glGetUniformLocation(program, "uModel")
            normalMatrixLocation = GLES20.glGetUniformLocation(program, "uNormal")
            viewProjectionLocation = GLES20.glGetUniformLocation(program, "uViewProjection")
            alphaLocation = GLES20.glGetUniformLocation(program, "uAlpha")
            GLES20.glEnable(GLES20.GL_DEPTH_TEST)
            GLES20.glDepthFunc(GLES20.GL_LEQUAL)
            GLES20.glEnable(GLES20.GL_BLEND)
            GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
            GLES20.glDisable(GLES20.GL_CULL_FACE)
            GLES20.glClearColor(.965f, .945f, .91f, 1f)
            scene?.let(::upload)
        } catch (error: Exception) { fail(error) }
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        this.width = width.coerceAtLeast(1); this.height = height.coerceAtLeast(1)
        GLES20.glViewport(0, 0, this.width, this.height)
    }

    override fun onDrawFrame(gl: GL10?) {
        if (failed) return
        try {
            pending.getAndSet(null)?.let { composition -> scene = composition; upload(composition) }
            GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
            val current = scene ?: return
            val settings = configuration
            choreography.configure(settings.equipped, settings.working)
            val now = SystemClock.uptimeMillis()
            val elapsed = if (resetClock || clock == 0L || !settings.animated) 0f else ((now - clock) / 1000f).coerceAtMost(.1f)
            clock = now; resetClock = false
            if (interactionRequested) { interactionRequested = false; if (settings.animated) choreography.react() }
            val pose = choreography.sample(elapsed)
            val label = if (settings.animated) RoomChoreography.title(pose.activity) else "삐약이가 잠시 쉬고 있어요"
            if (current.preview == null && label != activity) { activity = label; onActivity(label) }
            buildCamera(current.preview)
            buildRigMatrices(current.rigs, pose)
            GLES20.glUseProgram(program)
            GLES20.glUniformMatrix4fv(viewProjectionLocation, 1, false, viewProjection, 0)
            GLES20.glEnableVertexAttribArray(positionLocation)
            GLES20.glEnableVertexAttribArray(normalLocation)
            GLES20.glEnableVertexAttribArray(colorLocation)
            gpu.forEach { item ->
                val opacity = modelFor(item.batch, pose)
                if (opacity <= 0f) return@forEach
                GLES20.glUniformMatrix4fv(matrixLocation, 1, false, model, 0)
                Matrix.invertM(inverse, 0, model, 0)
                // inverse transpose, packed column-major for the normal transform
                for (column in 0..2) for (row in 0..2) normalMatrix[column * 3 + row] = inverse[row * 4 + column]
                GLES20.glUniformMatrix3fv(normalMatrixLocation, 1, false, normalMatrix, 0)
                GLES20.glUniform1f(alphaLocation, opacity)
                GLES20.glBindBuffer(GLES20.GL_ARRAY_BUFFER, item.vertex)
                val stride = SceneAssets.STRIDE * 4
                GLES20.glVertexAttribPointer(positionLocation, 3, GLES20.GL_FLOAT, false, stride, 0)
                GLES20.glVertexAttribPointer(normalLocation, 3, GLES20.GL_FLOAT, false, stride, 12)
                GLES20.glVertexAttribPointer(colorLocation, 4, GLES20.GL_FLOAT, false, stride, 24)
                GLES20.glBindBuffer(GLES20.GL_ELEMENT_ARRAY_BUFFER, item.index)
                GLES20.glDrawElements(GLES20.GL_TRIANGLES, item.batch.count, GLES20.GL_UNSIGNED_SHORT, 0)
            }
            GLES20.glBindBuffer(GLES20.GL_ARRAY_BUFFER, 0)
            GLES20.glBindBuffer(GLES20.GL_ELEMENT_ARRAY_BUFFER, 0)
            if (!ready) { check(GLES20.glGetError() == GLES20.GL_NO_ERROR) { "GL initialization failed" }; ready = true; onReady() }
        } catch (error: Exception) { fail(error) }
    }

    private fun upload(composition: SceneAssets.Composition) {
        gpu.forEach { GLES20.glDeleteBuffers(2, intArrayOf(it.vertex, it.index), 0) }
        gpu = composition.batches.map { batch ->
            val ids = IntArray(2); GLES20.glGenBuffers(2, ids, 0)
            batch.vertices.position(0); batch.indices.position(0)
            GLES20.glBindBuffer(GLES20.GL_ARRAY_BUFFER, ids[0])
            GLES20.glBufferData(GLES20.GL_ARRAY_BUFFER, batch.vertices.capacity() * 4, batch.vertices, GLES20.GL_STATIC_DRAW)
            GLES20.glBindBuffer(GLES20.GL_ELEMENT_ARRAY_BUFFER, ids[1])
            GLES20.glBufferData(GLES20.GL_ELEMENT_ARRAY_BUFFER, batch.indices.capacity() * 2, batch.indices, GLES20.GL_STATIC_DRAW)
            GPU(batch, ids[0], ids[1])
        }
        rigMatrices.clear(); composition.rigs.forEach { rigMatrices[it.name] = FloatArray(16) }
        ready = false
    }

    private fun buildCamera(preview: SceneAssets.Preview?) {
        val degrees = heading.coerceIn(-65f, 65f)
        val radians = degrees * PI.toFloat() / 180f
        val target = preview?.target ?: floatArrayOf(0f, 1.05f, 0f)
        val camera = preview?.camera ?: floatArrayOf(4.4f, 4.1f, 7.5f)
        val dx = camera[0] - target[0]; val dz = camera[2] - target[2]
        val x = target[0] + dx * cos(radians) + dz * sin(radians)
        val z = target[2] - dx * sin(radians) + dz * cos(radians)
        Matrix.setLookAtM(view, 0, x, camera[1], z, target[0], target[1], target[2], 0f, 1f, 0f)
        val aspect = width.toFloat() / height
        val extent = (preview?.scale ?: 3.1f) / zoom.coerceIn(.72f, 1.6f)
        // Match SceneKit's square framing and fit the whole room on narrow panels.
        val vertical = extent / min(1f, aspect)
        Matrix.orthoM(projection, 0, -vertical * aspect, vertical * aspect, -vertical, vertical, .1f, 100f)
        Matrix.multiplyMM(viewProjection, 0, projection, 0, view, 0)
    }

    private fun buildRigMatrices(rigs: List<SceneAssets.Rig>, pose: RoomChoreography.Pose) {
        rigs.forEach { rig ->
            val local = rig.matrix.copyOf()
            val t = pose.progress; val e = pose.envelope; val gait = pose.gait
            when (rig.name) {
                "piyak" -> {
                    Matrix.setIdentityM(local, 0)
                    Matrix.translateM(local, 0, pose.point.x, pose.height, pose.point.z)
                    Matrix.rotateM(local, 0, pose.angle.degrees(), 0f, 1f, 0f)
                    Matrix.scaleM(local, 0, .72f, .72f, .72f)
                }
                "eyes" -> Matrix.scaleM(local, 0, 1f, pose.blink, 1f)
                "foot.left", "foot.right" -> {
                    val lift = max(0f, gait * if (rig.name.endsWith("left")) 1 else -1)
                    Matrix.translateM(local, 0, 0f, lift * .12f, pose.seated * .14f)
                    Matrix.rotateM(local, 0, (lift * .25f - pose.seated * .7f).degrees(), 1f, 0f, 0f)
                }
                "bodyRig" -> {
                    Matrix.translateM(local, 0, 0f, -.06f * pose.seated, 0f)
                    Matrix.rotateM(local, 0, (gait * .065f).degrees(), 0f, 0f, 1f)
                    Matrix.scaleM(local, 0, 1f, 1f - .15f * pose.seated + if (pose.activity == "stretch") .025f * e else 0f, 1f)
                }
                "headRig" -> {
                    Matrix.translateM(local, 0, 0f, -.15f * pose.seated, 0f)
                    val nod = when (pose.activity) { "read", "water", "pet", "tidy", "work", "piano" -> .15f * e; "stretch" -> -.14f * e; else -> 0f }
                    Matrix.rotateM(local, 0, nod.degrees(), 1f, 0f, 0f)
                    Matrix.rotateM(local, 0, ((if (pose.activity == "look") sin(t * 1.35f) * .32f else 0f) * e).degrees(), 0f, 1f, 0f)
                    val tilt = if (pose.activity == "greet" || pose.activity == "celebrate") sin(t * 5f) * .13f * e else if (pose.activity == "inspect" || pose.activity == "rest") sin(t) * .08f * e else -gait * .035f
                    Matrix.rotateM(local, 0, tilt.degrees(), 0f, 0f, 1f)
                }
                "wing.left", "wing.right" -> {
                    val side = if (rig.name.endsWith("left")) -1f else 1f
                    val front = when (pose.activity) {
                        "read" -> -1.1f * e
                        "piano", "work" -> (-1.2f + sin(t * 7f + side) * .17f) * e
                        "tidy" -> (-.9f + sin(t * 3.5f) * side * .16f) * e
                        "water" -> if (side > 0) -1.2f * e else 0f
                        "pet", "play" -> if (side > 0) (-.85f + sin(t * 4f) * .14f) * e else 0f
                        else -> -side * gait * .32f
                    }
                    val wave = when (pose.activity) {
                        "greet", "celebrate" -> if (side < 0) -(1.4f + sin(t * 9f) * .22f) * e else .5f * e
                        "stretch" -> side * 1.9f * e
                        "water" -> if (side > 0) -.4f * e else 0f
                        else -> 0f
                    }
                    Matrix.rotateM(local, 0, front.degrees(), 1f, 0f, 0f)
                    Matrix.rotateM(local, 0, wave.degrees(), 0f, 0f, 1f)
                }
            }
            val destination = rigMatrices.getValue(rig.name)
            val parent = rigMatrices[rig.parent]
            if (parent != null) Matrix.multiplyMM(destination, 0, parent, 0, local, 0) else local.copyInto(destination)
        }
    }

    private fun modelFor(batch: SceneAssets.Batch, pose: RoomChoreography.Pose): Float {
        val rig = batch.rig
        val base = if (rig.startsWith("effect:")) rigMatrices["piyak"] else rigMatrices[rig]
        if (base != null) base.copyInto(model) else Matrix.setIdentityM(model, 0)
        if (rig == "shadow") {
            Matrix.translateM(model, 0, pose.point.x, 0f, pose.point.z)
            return 1f - pose.seated * .6f
        }
        if (rig.startsWith("effect:")) {
            val effect = rig.substringAfter(':')
            when {
                effect == "book" -> { if (pose.activity != "read") return 0f }
                effect == "wateringCan" -> { if (pose.activity != "water") return 0f }
                effect.startsWith("drop.") -> {
                    if (pose.activity != "water" || pose.envelope < .5f) return 0f
                    val phase = (pose.progress * 1.5f + effect.substringAfter('.').toInt() / 6f) % 1f
                    Matrix.translateM(model, 0, .3f, .92f - phase * .48f, 1.04f + phase * .07f)
                    return (1 - phase) * .85f
                }
            }
            return pose.envelope
        }
        if (rig.startsWith("prop:")) {
            val name = rig.substringAfter(':')
            var rotation = 0f
            when {
                name.startsWith("plant.leaf") && pose.activity == "water" -> rotation = sin(pose.progress * 2) * .06f
                name.startsWith("puppy.tail") && pose.activity == "pet" -> rotation = sin(pose.progress * 10) * .5f * pose.envelope
                name.startsWith("balloon.") && pose.activity == "play" -> rotation = sin(pose.progress * 2) * .08f * pose.envelope
                name.startsWith("piano.key") && pose.activity == "piano" -> Matrix.translateM(model, 0, 0f, -max(0f, sin(pose.progress * 7 + name.substringAfterLast('.').toFloat())) * .018f * pose.envelope, 0f)
            }
            if (rotation != 0f) {
                val c = batch.center
                Matrix.translateM(model, 0, c[0], c[1], c[2]); Matrix.rotateM(model, 0, rotation.degrees(), 0f, 0f, 1f); Matrix.translateM(model, 0, -c[0], -c[1], -c[2])
            }
        }
        return 1f
    }

    private fun fail(error: Exception) {
        failed = true
        onFailure("이 기기에서 3D 방을 표시하지 못했어요. 근무 기록과 꾸미기는 계속 사용할 수 있어요.")
        android.util.Log.e("PiyakRoom", "Bundled room renderer failed", error)
    }

    private fun createProgram(): Int {
        fun shader(type: Int, source: String): Int {
            val id = GLES20.glCreateShader(type)
            GLES20.glShaderSource(id, source); GLES20.glCompileShader(id)
            val result = IntArray(1); GLES20.glGetShaderiv(id, GLES20.GL_COMPILE_STATUS, result, 0)
            check(result[0] != 0) { GLES20.glGetShaderInfoLog(id) }
            return id
        }
        val vertex = shader(GLES20.GL_VERTEX_SHADER, """
            uniform mat4 uModel;
            uniform mat4 uViewProjection;
            uniform mat3 uNormal;
            attribute vec3 aPosition;
            attribute vec3 aNormal;
            attribute vec4 aColor;
            varying vec3 vNormal;
            varying vec4 vColor;
            void main() {
                gl_Position = uViewProjection * uModel * vec4(aPosition, 1.0);
                vNormal = normalize(uNormal * aNormal);
                vColor = aColor;
            }
        """.trimIndent())
        val fragment = shader(GLES20.GL_FRAGMENT_SHADER, """
            precision mediump float;
            varying vec3 vNormal;
            varying vec4 vColor;
            uniform float uAlpha;
            void main() {
                vec3 normal = normalize(vNormal);
                if (!gl_FrontFacing) normal = -normal;
                float key = max(dot(normal, normalize(vec3(-0.55, 0.85, 0.8))), 0.0);
                float fill = max(dot(normal, normalize(vec3(0.9, 0.5, 0.3))), 0.0);
                float hemisphere = 0.06 * (normal.y * 0.5 + 0.5);
                vec3 light = vec3(0.54, 0.52, 0.50) + key * vec3(0.34, 0.34, 0.35) + fill * 0.12 + hemisphere;
                gl_FragColor = vec4(vColor.rgb * light, vColor.a * uAlpha);
            }
        """.trimIndent())
        val id = GLES20.glCreateProgram()
        GLES20.glAttachShader(id, vertex); GLES20.glAttachShader(id, fragment); GLES20.glLinkProgram(id)
        GLES20.glDeleteShader(vertex); GLES20.glDeleteShader(fragment)
        val linked = IntArray(1); GLES20.glGetProgramiv(id, GLES20.GL_LINK_STATUS, linked, 0)
        check(linked[0] != 0) { GLES20.glGetProgramInfoLog(id) }
        return id
    }

    private fun Float.degrees() = this * 180f / PI.toFloat()
}
