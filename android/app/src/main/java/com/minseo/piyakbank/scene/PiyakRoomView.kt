package com.minseo.piyakbank.scene

import android.app.ActivityManager
import android.content.Context
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.database.ContentObserver
import android.graphics.Color
import android.opengl.GLSurfaceView
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Native offline 3D room. Host must forward ON_RESUME/ON_PAUSE and set animated
 * false for reduced motion, power saving, thermal pressure and item previews.
 * All public methods are main-thread APIs; assets are decoded on one shared worker.
 */
class PiyakRoomView(context: Context) : FrameLayout(context) {
    var onInteraction: (() -> Unit)? = null
    var onActivityChanged: ((String) -> Unit)? = null
    var onRenderError: ((String) -> Unit)? = null
    private val main = Handler(Looper.getMainLooper())
    private val generation = AtomicInteger()
    private val fallback = TextView(context).apply {
        text = "삐약이의 방을 준비하고 있어요"
        setTextColor(Color.rgb(87, 73, 63)); textSize = 16f
        gravity = android.view.Gravity.CENTER
        setPadding(32, 24, 32, 24)
        setBackgroundColor(Color.rgb(246, 241, 232))
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private var gl: GLSurfaceView? = null
    private val renderer = RoomRenderer(
        onReady = { main.post { if (!renderFailed) fallback.visibility = GONE } },
        onFailure = { message -> main.post { showFailure(message) } },
        onActivity = { title -> main.post { if (isAttachedToWindow) onActivityChanged?.invoke(title) } }
    )
    private var resumed = false
    private var surfaceResumed = false
    private var renderFailed = false
    private var animated = false
    private var requestedAnimation = false
    private var working = false
    private var registered = false
    private val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private val powerReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { updateMotionPreference() }
    }
    private val animatorObserver = object : ContentObserver(main) {
        override fun onChange(selfChange: Boolean) { updateMotionPreference() }
    }
    private val thermalListener = if (Build.VERSION.SDK_INT >= 29) PowerManager.OnThermalStatusChangedListener { main.post { updateMotionPreference() } } else null
    private var equipment: Map<String, String>? = null
    private var preview: String? = null
    private var frameQueued = false
    private var tapRecognized = false
    private var multiTouchGesture = false
    private val frame = object : Runnable {
        override fun run() {
            frameQueued = false
            if (canRender() && animated) {
                gl?.requestRender()
                frameQueued = true; main.postDelayed(this, FRAME_DELAY_MS)
            }
        }
    }
    private val gestures = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
        override fun onDown(event: MotionEvent) = true
        override fun onSingleTapUp(event: MotionEvent): Boolean { tapRecognized = true; return true }
        override fun onScroll(first: MotionEvent?, second: MotionEvent, distanceX: Float, distanceY: Float): Boolean {
            if (!scale.isInProgress) rotateBy(-distanceX * .18f)
            return true
        }
        override fun onDoubleTap(event: MotionEvent): Boolean { resetCamera(); return true }
    })
    private val scale = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(detector: ScaleGestureDetector): Boolean { zoomBy(detector.scaleFactor); return true }
    })

    init {
        clipChildren = true
        isClickable = true; isFocusable = true
        contentDescription = "삐약이의 3D 방. 두 번 눌러 함께 놀 수 있어요"
        val version = (context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager)?.deviceConfigurationInfo?.reqGlEsVersion ?: 0
        if (version >= 0x20000) {
            try {
                gl = GLSurfaceView(context).also { surface ->
                    surface.setEGLContextClientVersion(2)
                    // No MSAA requirement: devices without a multisampled EGL
                    // configuration still render the full original geometry.
                    surface.setEGLConfigChooser(8, 8, 8, 0, 16, 0)
                    surface.preserveEGLContextOnPause = true
                    surface.setRenderer(renderer)
                    surface.renderMode = GLSurfaceView.RENDERMODE_WHEN_DIRTY
                    surface.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
                    addView(surface, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
                    // GLSurfaceView starts active; immediately park until host resumes.
                    surface.onPause()
                }
            } catch (_: RuntimeException) { renderFailed = true }
        } else renderFailed = true
        addView(fallback, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        if (renderFailed) fallback.text = "이 기기는 3D 방을 지원하지 않아요. 근무 기록과 꾸미기는 계속 사용할 수 있어요."
    }

    fun configure(equipped: Map<String, String>, animated: Boolean, working: Boolean, previewItemId: String? = null) {
        requestedAnimation = animated && previewItemId == null
        this.working = working
        if (equipment != equipped || preview != previewItemId) {
            equipment = equipped.toMap(); preview = previewItemId
            val token = generation.incrementAndGet()
            val selected = equipped.toMap()
            if (!renderFailed) loader.execute {
                try {
                    if (token != generation.get()) return@execute
                    val assets = SceneAssets.load(context.applicationContext.assets)
                    if (token != generation.get()) return@execute
                    val composition = assets.compose(selected, previewItemId)
                    main.post {
                        if (token == generation.get() && !renderFailed) {
                            renderer.pending.set(composition)
                            renderer.resetClock = true
                            requestFrame()
                        }
                    }
                } catch (_: Exception) { main.post { if (token == generation.get()) showFailure("방의 모델을 불러오지 못했어요. 근무 기록과 꾸미기는 계속 사용할 수 있어요.") } }
            }
        }
        updateMotionPreference()
        refreshRendering(); requestFrame()
    }

    fun playInteraction() {
        if (!canRender() || preview != null) return
        if (animated) { renderer.interactionRequested = true; requestFrame() }
        onInteraction?.invoke()
    }

    fun rotateBy(degrees: Float) {
        if (!degrees.isFinite()) return
        renderer.heading = (renderer.heading + degrees).coerceIn(-65f, 65f); requestFrame()
    }

    fun zoomBy(factor: Float) {
        if (!factor.isFinite() || factor <= 0) return
        renderer.zoom = (renderer.zoom * factor).coerceIn(.72f, 1.6f); requestFrame()
    }

    fun resetCamera() { renderer.heading = 0f; renderer.zoom = 1f; requestFrame() }
    fun onHostResume() { resumed = true; refreshRendering() }
    fun onHostPause() { resumed = false; refreshRendering() }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (!registered) {
            if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(powerReceiver, IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED), Context.RECEIVER_NOT_EXPORTED)
            else context.registerReceiver(powerReceiver, IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED))
            context.contentResolver.registerContentObserver(Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE), false, animatorObserver)
            if (Build.VERSION.SDK_INT >= 29 && thermalListener != null) power.addThermalStatusListener(context.mainExecutor, thermalListener)
            registered = true
        }
        updateMotionPreference(); refreshRendering()
    }
    override fun onDetachedFromWindow() {
        removeFrames()
        if (surfaceResumed) { gl?.onPause(); surfaceResumed = false }
        if (registered) {
            context.unregisterReceiver(powerReceiver)
            context.contentResolver.unregisterContentObserver(animatorObserver)
            if (Build.VERSION.SDK_INT >= 29 && thermalListener != null) power.removeThermalStatusListener(thermalListener)
            registered = false
        }
        renderer.resetClock = true
        super.onDetachedFromWindow()
    }

    override fun onWindowVisibilityChanged(visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        // View's superclass may invoke this before field initialization.
        if (gl != null) refreshRendering()
    }

    override fun onVisibilityAggregated(isVisible: Boolean) { super.onVisibilityAggregated(isVisible); if (gl != null) refreshRendering() }
    override fun performClick(): Boolean { super.performClick(); playInteraction(); return true }
    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!isEnabled) return false
        if (event.actionMasked == MotionEvent.ACTION_DOWN) multiTouchGesture = false
        if (event.pointerCount > 1) multiTouchGesture = true
        tapRecognized = false
        scale.onTouchEvent(event)
        // Both detectors need the complete pointer stream: skipping events
        // during a pinch can make the final UP look like a one-finger tap.
        gestures.onTouchEvent(event)
        if (event.actionMasked == MotionEvent.ACTION_UP && tapRecognized && !multiTouchGesture) {
            // Touch, TalkBack ACTION_CLICK and keyboard activation all use the
            // same callback and accessibility event supplied by performClick.
            performClick()
        }
        if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL) multiTouchGesture = false
        return true
    }

    private fun canRender() = !renderFailed && resumed && isAttachedToWindow && isShown && windowVisibility == VISIBLE
    private fun updateMotionPreference() {
        val animatorEnabled = Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) > 0f
        val warm = Build.VERSION.SDK_INT >= 29 && power.currentThermalStatus >= PowerManager.THERMAL_STATUS_MODERATE
        animated = requestedAnimation && animatorEnabled && !power.isPowerSaveMode && !warm
        renderer.configuration = RoomRenderer.Configuration(equipment.orEmpty(), animated, working)
        renderer.resetClock = true
        refreshRendering()
    }
    private fun refreshRendering() {
        val active = canRender()
        if (active != surfaceResumed) {
            if (active) gl?.onResume() else gl?.onPause()
            surfaceResumed = active; renderer.resetClock = true
        }
        if (!active || !animated) removeFrames()
        else if (!frameQueued) { frameQueued = true; main.post(frame) }
        if (active) requestFrame()
    }
    private fun removeFrames() { main.removeCallbacks(frame); frameQueued = false }
    private fun requestFrame() { if (canRender()) gl?.requestRender() }
    private fun showFailure(message: String) {
        renderFailed = true; fallback.text = message; fallback.visibility = VISIBLE
        refreshRendering(); onRenderError?.invoke(message)
    }

    companion object {
        // 42 ms = at most 23.81 requested frames/s. Dirty-mode never renders a
        // hidden continuous loop. This worker performs no Android/GPU rendering.
        private const val FRAME_DELAY_MS = 42L
        private val loader = Executors.newSingleThreadExecutor { task -> Thread(task, "Piyak-scene-assets").apply { isDaemon = true; priority = Thread.MIN_PRIORITY } }
    }
}
