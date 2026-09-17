package vip.qinghan.withu

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.text.TextPaint
import android.text.TextUtils
import android.util.Log
import android.util.TypedValue
import androidx.core.content.ContextCompat
import org.json.JSONObject
import java.util.Calendar
import kotlin.math.ceil

class LiveUpdateService : Service() {
    companion object {
        private const val TAG = "LiveUpdateService"
        private const val CHANNEL_ID = "live_update_channel"
        private const val NOTIFICATION_ID = 2001
        private const val EXTRA_REQUEST_PROMOTED_ONGOING = "android.requestPromotedOngoing"

        /** Flutter 下发的常驻开关 extra（设置 → 实时活动 → 常驻通知）。 */
        private const val EXTRA_PERMANENT_NOTIFICATION = "permanentNotification"

        /** 流体云文案：临近下课窗口（大课最后 5 分钟显示「即将下课」）。 */
        private const val ABOUT_TO_END_WINDOW_MILLIS = 5 * 60_000L

        /** ticker 在 reschedule 出口处续排的重试间隔；见 scheduleTickerRetry。 */
        private const val TICKER_RETRY_DELAY_MILLIS = 5_000L

        private const val PREFS_NAME = "native_runtime_prefs"
        private const val KEY_HIDE_FROM_RECENTS = "hide_from_recents"

        /**
         * 常驻开关落盘键。
         *
         * 开关本身由 Flutter 通过 intent extra 下发，但服务被 START_STICKY 用 null
         * intent 拉起时读不到 extra，那时必须能拿回用户的设置，否则关掉开关的用户
         * 会在进程被杀后又看到一条常驻通知。
         */
        private const val KEY_PERMANENT_NOTIFICATION = "live_permanent_notification"

        /**
         * 常驻空闲形态单次最长睡眠。
         *
         * 空闲时只在「下一次边界」醒来（见 computeIdleTickDelayMillis），跨天前可能
         * 十几小时没有边界。闹钟与 WorkManager 才是主要唤醒源，这个上限纯属兜底：
         * 手动改时钟、换时区、或闹钟被 ROM 吞掉时，最长 6 小时也会自纠一次。
         */
        private const val MAX_IDLE_TICK_DELAY_MILLIS = 6 * 60 * 60_000L

        /** 一天秒数：空闲档位算不到边界时，直接睡到跨天。 */
        private const val SECONDS_PER_DAY = 24 * 3600
        private const val ACTION_ENABLE_SILENT_MODE =
            "vip.qinghan.withu.action.ENABLE_SILENT_MODE"
        private const val ACTION_ENABLE_DO_NOT_DISTURB =
            "vip.qinghan.withu.action.ENABLE_DO_NOT_DISTURB"
        private const val ACTION_CANCEL_SILENT_MODE =
            "vip.qinghan.withu.action.CANCEL_SILENT_MODE"
        private const val ACTION_CANCEL_DO_NOT_DISTURB =
            "vip.qinghan.withu.action.CANCEL_DO_NOT_DISTURB"
        private const val ACTION_DISMISS_STATUS_BAR_STAGE =
            "vip.qinghan.withu.action.DISMISS_STATUS_BAR_STAGE"
        private const val POST_PROMOTED_NOTIFICATIONS_PERMISSION =
            "android.permission.POST_PROMOTED_NOTIFICATIONS"

        @Volatile
        private var isServiceRunning = false

        @Volatile
        private var lastDebugSnapshot: Map<String, Any?> = emptyMap()

        @Volatile
        private var lastDebugUpdatedAtMillis = 0L

        @Volatile
        private var lastStopReason: String? = null

        fun buildDebugStatus(context: Context): Map<String, Any?> {
            val snapshot = lastDebugSnapshot
            val summary = copyStringKeyMap(snapshot["summary"]).apply {
                this["serviceRunning"] = isServiceRunning
                this["statusText"] = when {
                    isServiceRunning -> this["statusText"] ?: context.getString(R.string.debug_status_running)
                    else -> context.getString(R.string.debug_status_not_running)
                }
                this["isExpectedToShowIsland"] =
                    (this["isExpectedToShowIsland"] as? Boolean == true) && isServiceRunning
                this["isActuallyPromotable"] =
                    (this["isActuallyPromotable"] as? Boolean == true) && isServiceRunning
                this["notIslandReason"] =
                    if (isServiceRunning) {
                        this["notIslandReason"] ?: ""
                    } else {
                        lastStopReason ?: context.getString(R.string.debug_service_not_running)
                    }
            }

            val service = copyStringKeyMap(snapshot["service"]).apply {
                this["serviceRunning"] = isServiceRunning
                this["lastDebugUpdatedAtMillis"] = lastDebugUpdatedAtMillis
                this["lastStopReason"] = lastStopReason
            }
            val recentDiagnostics = linkedMapOf<String, Any?>(
                "enabled" to UmengDiagnosticReporter.isLiveDiagnosticsEnabled(context),
                "tail" to UmengDiagnosticReporter.readLiveDiagnosticsTail(context),
            )

            return linkedMapOf(
                "generatedAtMillis" to System.currentTimeMillis(),
                "summary" to summary,
                "environment" to buildEnvironmentSnapshot(context),
                "service" to service,
                "course" to copyStringKeyMap(snapshot["course"]),
                "timing" to copyStringKeyMap(snapshot["timing"]),
                "switches" to copyStringKeyMap(snapshot["switches"]),
                "display" to copyStringKeyMap(snapshot["display"]),
                "notification" to copyStringKeyMap(snapshot["notification"]),
                "recentDiagnostics" to recentDiagnostics,
            )
        }

        private fun copyStringKeyMap(value: Any?): LinkedHashMap<String, Any?> {
            val source = value as? Map<*, *> ?: return linkedMapOf()
            val result = linkedMapOf<String, Any?>()
            source.forEach { (key, item) ->
                if (key is String) {
                    result[key] = item
                }
            }
            return result
        }

        private fun buildEnvironmentSnapshot(context: Context): Map<String, Any?> {
            return linkedMapOf(
                "androidVersion" to Build.VERSION.SDK_INT,
                "brand" to Build.BRAND,
                "manufacturer" to Build.MANUFACTURER,
                "device" to Build.DEVICE,
                "model" to Build.MODEL,
                "isXiaomiFamilyDevice" to isXiaomiFamilyDeviceCompat(),
                "hasNotificationPermission" to hasNotificationPermissionCompat(context),
                "hasPromotedPermissionDeclared" to isPromotedPermissionDeclaredCompat(context),
                "canPostPromotedNotifications" to canPostPromotedNotificationsCompat(context),
                "ignoringBatteryOptimizations" to isIgnoringBatteryOptimizationsCompat(context),
                "hideFromRecentsEnabled" to context
                    .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .getBoolean(KEY_HIDE_FROM_RECENTS, false),
            )
        }

        private fun updateDebugSnapshot(snapshot: Map<String, Any?>) {
            lastDebugSnapshot = snapshot
            lastDebugUpdatedAtMillis = System.currentTimeMillis()
            lastStopReason = null
        }

        private fun markServiceRunning() {
            isServiceRunning = true
            lastStopReason = null
            lastDebugUpdatedAtMillis = System.currentTimeMillis()
        }

        private fun markServiceStopped(reason: String) {
            isServiceRunning = false
            lastStopReason = reason
            lastDebugUpdatedAtMillis = System.currentTimeMillis()
        }

        /**
         * 常驻开关是否打开。
         *
         * 开关由 Flutter 通过 intent extra 下发并落盘（见 onStartCommand），但调度器、
         * 开机接收器与 15 分钟兜底 Worker 也要据此决定「能不能收掉通知」——否则那些
         * 路径会在无课时把常驻通知摘掉。所以统一从这里读，prefs 细节不外泄。
         */
        fun isPermanentNotificationEnabled(context: Context): Boolean =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_PERMANENT_NOTIFICATION, true)

        fun setPermanentNotificationEnabled(context: Context, enabled: Boolean) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_PERMANENT_NOTIFICATION, enabled)
                .apply()
        }

        /**
         * 本进程内服务是否在运行。
         *
         * 开机/启动路径用它避免用「无课程负载」的 intent 打断一个正跑着的课程会话：
         * onStartCommand 收到空负载会切到常驻空闲形态。
         */
        fun isRunning(): Boolean = isServiceRunning

        private fun hasNotificationPermissionCompat(context: Context): Boolean {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.POST_NOTIFICATIONS
                ) == PackageManager.PERMISSION_GRANTED
            } else {
                true
            }
        }

        // 应用级通知总开关：Android 13+ 与运行时通知权限联动，13 以下反映系统设置里的
        // 「显示通知」开关。两种状态为关时 notify() 都会被系统静默丢弃。
        private fun areNotificationsEnabledCompat(context: Context): Boolean {
            return context.getSystemService(NotificationManager::class.java)
                ?.areNotificationsEnabled() == true
        }

        // 渠道级开关：live_update_channel 被单独关闭（importance = NONE）时同样无法出通知。
        // 渠道尚未创建时视为开启，由 ensureNotificationChannel 在服务启动阶段兜底创建。
        private fun isLiveUpdateChannelEnabledCompat(context: Context): Boolean {
            val channel = context.getSystemService(NotificationManager::class.java)
                ?.getNotificationChannel(CHANNEL_ID) ?: return true
            return channel.importance != NotificationManager.IMPORTANCE_NONE
        }

        private fun isPromotedPermissionDeclaredCompat(context: Context): Boolean {
            return try {
                val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    context.packageManager.getPackageInfo(
                        context.packageName,
                        PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong())
                    )
                } else {
                    @Suppress("DEPRECATION")
                    context.packageManager.getPackageInfo(
                        context.packageName,
                        PackageManager.GET_PERMISSIONS
                    )
                }
                packageInfo.requestedPermissions
                    ?.contains(POST_PROMOTED_NOTIFICATIONS_PERMISSION) == true
            } catch (e: Exception) {
                Log.w(TAG, DiagnosticLogMessages.LOG_INSPECT_PROMOTED_PERMISSION_FAILED, e)
                false
            }
        }

        private fun canPostPromotedNotificationsCompat(context: Context): Boolean {
            return Build.VERSION.SDK_INT >= 36 &&
                context.getSystemService(NotificationManager::class.java)
                    ?.canPostPromotedNotifications() == true
        }

        private fun isIgnoringBatteryOptimizationsCompat(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                return true
            }
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            return powerManager?.isIgnoringBatteryOptimizations(context.packageName) == true
        }

        private fun isXiaomiFamilyDeviceCompat(): Boolean =
            liveSurfaceBrand(Build.MANUFACTURER, Build.BRAND) == LiveSurfaceBrand.XIAOMI
    }

    private val handler = Handler(Looper.getMainLooper())
    private var ticker: Runnable? = null
    private var courseName = ""
    private var shortCourseNameRaw = ""
    private var location = ""
    private var teacher = ""
    private var note = ""
    private var startTimeText = ""
    private var endTimeText = ""
    private var nextName = ""
    private var autoDismissAfterStartMinutes = 0
    private var activityStage = ""
    private var showCountdown = true
    private var countdownTextStyle = "smart"
    private var showStageText = true
    private var showCourseNameInIsland = true
    private var showLocationInIsland = true
    private var useShortNameInIsland = false
    private var hidePrefixText = false
    private var duringClassTimeDisplayMode = "nearest"
    private var enableMiuiIslandLabelImage = false
    private var miuiIslandLabelStyle = "text_only"
    private var miuiIslandLabelContent = "course_name"
    private var miuiIslandLabelFontColor = "#FFFFFF"
    private var miuiIslandLabelFontWeight = "bold"
    private var miuiIslandLabelRenderQuality = "standard"
    private var miuiIslandLabelFontSize = 14f
    private var miuiIslandLabelOffsetX = 0f
    private var miuiIslandLabelOffsetY = 0f
    private var miuiIslandLabelLogoPath: String? = null
    private var miuiIslandLabelLogoCornerRadius = 8f
    private var miuiIslandExpandedIconMode = "app_icon"
    private var miuiIslandExpandedIconPath: String? = null
    private var startAtMillis = 0L
    private var endAtMillis = 0L
    private var beforeClassLeadMillis = 0L
    private var liveClassReminderStartMinutes = 0
    private var enableBeforeClass = true
    private var enableDuringClass = true
    private var promoteDuringClass = true
    private var showNotificationDuringClass = true
    private var beforeClassQuickAction = "none"
    private var quickActionAutoLeadMillis = 0L
    private var lastQuickActionState = ""
    private var progressBreakOffsetsMillis = longArrayOf()
    private var progressMilestoneLabels = emptyList<String>()
    private var progressMilestoneTimeTexts = emptyList<String>()
    private var lastRemainingText = "-1"
    private var lastProgressUnits = -1
    private var lastCriticalTimeText = ""
    private var cachedIslandBitmapKey: String? = null
    private var cachedIslandBitmap: Bitmap? = null
    private var hasStartedForeground = false
    private var lastTickerStage: String? = null
    private var validateAgainstSchedule = true
    /**
     * 常驻开关（设置 → 实时活动 → 常驻通知）。
     *
     * 打开时服务在「没有课程会话」时不摘通知、也不退出，改为展示情侣卡片形态；
     * 关闭时完全保持原有的「随课程起停」行为。
     */
    private var permanentNotification = true
    /** 当前是否处于常驻空闲形态（用于让第一帧必定重绘、并让自检页能区分档位）。 */
    private var idleMode = false
    /** 常驻空闲形态的上一帧签名，避免无变化时重复 notify。 */
    private var lastIdleSignature = ""

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return try {
            val quickActionResult = when (intent?.action) {
                ACTION_ENABLE_SILENT_MODE -> {
                    readQuickActionTimingExtra(intent)
                    handleBeforeClassQuickAction(BeforeClassQuickActionRestore.ACTION_SILENT)
                    START_NOT_STICKY
                }
                ACTION_ENABLE_DO_NOT_DISTURB -> {
                    readQuickActionTimingExtra(intent)
                    handleBeforeClassQuickAction(
                        BeforeClassQuickActionRestore.ACTION_DO_NOT_DISTURB
                    )
                    START_NOT_STICKY
                }
                ACTION_CANCEL_SILENT_MODE -> {
                    handleCancelQuickAction(BeforeClassQuickActionRestore.ACTION_SILENT)
                    START_NOT_STICKY
                }
                ACTION_CANCEL_DO_NOT_DISTURB -> {
                    handleCancelQuickAction(BeforeClassQuickActionRestore.ACTION_DO_NOT_DISTURB)
                    START_NOT_STICKY
                }
                ACTION_DISMISS_STATUS_BAR_STAGE -> {
                    dismissStatusBarStage()
                    START_NOT_STICKY
                }
                else -> null
            }
            if (quickActionResult != null) {
                return quickActionResult
            }

            startForegroundSafely(intent)

            // 常驻开关必须**先于负载校验**读取：开机/常驻拉起时 intent 里没有课程
            // 负载，但仍要据此决定是留在前台还是把通知摘掉。读到 extra 就落盘，
            // 这样 START_STICKY 用 null intent 重启时也能拿回用户的真实设置。
            if (intent != null && intent.hasExtra(EXTRA_PERMANENT_NOTIFICATION)) {
                permanentNotification = intent.getBooleanExtra(EXTRA_PERMANENT_NOTIFICATION, true)
                setPermanentNotificationEnabled(applicationContext, permanentNotification)
            } else {
                permanentNotification = isPermanentNotificationEnabled(applicationContext)
            }

            if (!hasCompleteLivePayload(intent)) {
                // 已经在跑一个课程会话时，空负载的 intent（开机 / App 启动拉起常驻
                // 通知）不能把会话打断：此刻阶段仍有效就原样保留，什么都不做。
                // startForegroundSafely 在已前台时直接返回，不会覆盖现有通知。
                val now = System.currentTimeMillis()
                if (hasStartedForeground && resolveStage(now) != null) {
                    return START_STICKY
                }
                UmengDiagnosticReporter.record(
                    context = applicationContext,
                    category = "live_update_service_missing_payload",
                    message = DiagnosticLogMessages.LIVE_UPDATE_SERVICE_MISSING_PAYLOAD,
                    extras = mapOf(
                        "intentIsNull" to (intent == null),
                        "permanentNotification" to permanentNotification,
                        "hasCourseName" to (!intent?.getStringExtra("courseName").isNullOrBlank()),
                        "hasStage" to (!intent?.getStringExtra("stage").isNullOrBlank()),
                        "hasStartAtMillis" to ((intent?.getLongExtra("startAtMillis", 0L) ?: 0L) > 0L),
                        "hasEndAtMillis" to ((intent?.getLongExtra("endAtMillis", 0L) ?: 0L) > 0L),
                    )
                )
                val resumed = LiveUpdateScheduler.reschedule(
                    applicationContext,
                    allowImmediateStart = true,
                    // 常驻模式不能让这次重排把刚起来的前台服务收掉。
                    stopStaleSessions = !permanentNotification,
                )
                if (!resumed && permanentNotification) {
                    // 常驻：此刻没有课程会话也要把通知留在状态栏，切到情侣卡片形态。
                    enterIdleMode()
                    updateForegroundNotification(
                        buildIdleNotification(liveIdleContent(System.currentTimeMillis()))
                    )
                    startTicker()
                    return START_STICKY
                }
                if (!resumed) {
                    stopAndRemoveNotification()
                    return START_NOT_STICKY
                }
                return START_STICKY
            }

            courseName = sanitizeTextExtra(intent?.getStringExtra("courseName"))
            shortCourseNameRaw = sanitizeTextExtra(intent?.getStringExtra("shortName"))
            location = sanitizeTextExtra(intent?.getStringExtra("location"))
            teacher = sanitizeTextExtra(intent?.getStringExtra("teacher"))
            note = sanitizeTextExtra(intent?.getStringExtra("note"))
            startTimeText = sanitizeTextExtra(intent?.getStringExtra("startTime"))
            endTimeText = sanitizeTextExtra(intent?.getStringExtra("endTime"))
            nextName = sanitizeTextExtra(intent?.getStringExtra("nextName"))
            autoDismissAfterStartMinutes = intent?.getIntExtra("autoDismissAfterStartMinutes", 0) ?: 0
            activityStage = intent?.getStringExtra("stage").orEmpty()
            showCountdown = intent?.getBooleanExtra("showCountdown", true) ?: true
            countdownTextStyle = intent?.getStringExtra("countdownTextStyle") ?: "smart"
            showStageText = intent?.getBooleanExtra("showStageText", true) ?: true
            showCourseNameInIsland = intent?.getBooleanExtra("showCourseNameInIsland", true) ?: true
            showLocationInIsland = intent?.getBooleanExtra("showLocationInIsland", true) ?: true
            useShortNameInIsland = intent?.getBooleanExtra("useShortNameInIsland", false) ?: false
            hidePrefixText = intent?.getBooleanExtra("hidePrefixText", false) ?: false
            duringClassTimeDisplayMode =
                intent?.getStringExtra("duringClassTimeDisplayMode") ?: "nearest"
            enableMiuiIslandLabelImage =
                intent?.getBooleanExtra("enableMiuiIslandLabelImage", false) ?: false
            miuiIslandLabelStyle = intent?.getStringExtra("miuiIslandLabelStyle") ?: "text_only"
            miuiIslandLabelContent =
                intent?.getStringExtra("miuiIslandLabelContent") ?: "course_name"
            miuiIslandLabelFontColor =
                intent?.getStringExtra("miuiIslandLabelFontColor") ?: "#FFFFFF"
            miuiIslandLabelFontWeight =
                intent?.getStringExtra("miuiIslandLabelFontWeight") ?: "bold"
            miuiIslandLabelRenderQuality =
                intent?.getStringExtra("miuiIslandLabelRenderQuality") ?: "standard"
            miuiIslandLabelFontSize =
                intent?.getFloatExtra("miuiIslandLabelFontSize", 14f) ?: 14f
            miuiIslandLabelOffsetX =
                intent?.getFloatExtra("miuiIslandLabelOffsetX", 0f) ?: 0f
            miuiIslandLabelOffsetY =
                intent?.getFloatExtra("miuiIslandLabelOffsetY", 0f) ?: 0f
            miuiIslandLabelLogoPath =
                intent?.getStringExtra("miuiIslandLabelLogoPath")?.takeIf { it.isNotBlank() }
            miuiIslandLabelLogoCornerRadius =
                intent?.getFloatExtra("miuiIslandLabelLogoCornerRadius", 8f) ?: 8f
            miuiIslandExpandedIconMode =
                intent?.getStringExtra("miuiIslandExpandedIconMode") ?: "app_icon"
            miuiIslandExpandedIconPath =
                intent?.getStringExtra("miuiIslandExpandedIconPath")?.takeIf { it.isNotBlank() }
            beforeClassLeadMillis =
                intent?.getLongExtra("beforeClassLeadMillis", 0L)
                    ?.coerceAtLeast(0L)
                    ?: 0L
            liveClassReminderStartMinutes =
                intent?.getIntExtra("liveClassReminderStartMinutes", 0)?.coerceAtLeast(0) ?: 0
            enableBeforeClass = intent?.getBooleanExtra("enableBeforeClass", true) ?: true
            enableDuringClass = intent?.getBooleanExtra("enableDuringClass", true) ?: true
            promoteDuringClass = intent?.getBooleanExtra("promoteDuringClass", true) ?: true
            showNotificationDuringClass =
                intent?.getBooleanExtra("showNotificationDuringClass", true) ?: true
            beforeClassQuickAction =
                intent?.getStringExtra("beforeClassQuickAction") ?: "none"
            quickActionAutoLeadMillis =
                intent?.getLongExtra("quickActionAutoLeadMillis", 0L) ?: 0L
            validateAgainstSchedule =
                intent?.getBooleanExtra("validateAgainstSchedule", true) ?: true
            progressBreakOffsetsMillis =
                intent?.getLongArrayExtra("progressBreakOffsetsMillis") ?: longArrayOf()
            progressMilestoneLabels =
                intent?.getStringArrayListExtra("progressMilestoneLabels") ?: emptyList()
            progressMilestoneTimeTexts =
                intent?.getStringArrayListExtra("progressMilestoneTimeTexts") ?: emptyList()
            startAtMillis =
                intent?.getLongExtra("startAtMillis", 0L)?.takeIf { it > 0L }
                    ?: buildCourseTimeMillis(startTimeText)
                    ?: System.currentTimeMillis()
            endAtMillis =
                intent?.getLongExtra("endAtMillis", 0L)?.takeIf { it > 0L }
                    ?: buildCourseTimeMillis(endTimeText)
                    ?: startAtMillis

            lastRemainingText = "-1"
            lastProgressUnits = -1
            lastCriticalTimeText = ""
            markServiceRunning()

            UmengDiagnosticReporter.record(
                context = applicationContext,
                category = "live_update_service_started",
                message = DiagnosticLogMessages.LIVE_UPDATE_SERVICE_STARTED,
                extras = mapOf(
                    "courseName" to courseName,
                    "stage" to activityStage,
                    "startAtMillis" to startAtMillis,
                    "endAtMillis" to endAtMillis,
                    "enableBeforeClass" to enableBeforeClass,
                    "enableDuringClass" to enableDuringClass,
                    "promoteDuringClass" to promoteDuringClass,
                    "showNotificationDuringClass" to showNotificationDuringClass,
                    "showCourseNameInIsland" to showCourseNameInIsland,
                    "showLocationInIsland" to showLocationInIsland,
                    "enableMiuiIslandLabelImage" to enableMiuiIslandLabelImage,
                    "miuiIslandLabelFontSize" to miuiIslandLabelFontSize,
                    "miuiIslandLabelOffsetX" to miuiIslandLabelOffsetX,
                    "miuiIslandLabelOffsetY" to miuiIslandLabelOffsetY,
                    "hasMiuiIslandLabelLogoPath" to (!miuiIslandLabelLogoPath.isNullOrBlank()),
                    "miuiIslandLabelLogoCornerRadius" to miuiIslandLabelLogoCornerRadius,
                    "miuiIslandExpandedIconMode" to miuiIslandExpandedIconMode,
                )
            )

            val initialText = computeRemainingText(System.currentTimeMillis())
            lastRemainingText = initialText
            updateForegroundNotification(buildNotification(initialText))
            startTicker()
            START_STICKY
        } catch (e: Exception) {
            markServiceStopped(getString(R.string.stop_service_start_failed))
            UmengDiagnosticReporter.report(
                context = applicationContext,
                category = "live_update_service_start_failed",
                message = DiagnosticLogMessages.LIVE_UPDATE_SERVICE_START_FAILED,
                throwable = e,
                dedupeKey = "live_update_service_start_failed",
                extras = mapOf(
                    "courseName" to courseName,
                    "stage" to activityStage,
                )
            )
            if (hasStartedForeground) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                hasStartedForeground = false
            }
            stopSelf()
            START_NOT_STICKY
        }
    }

    override fun onDestroy() {
        stopTicker()
        if (isServiceRunning) {
            markServiceStopped(getString(R.string.stop_service_destroyed))
        }
        if (hasStartedForeground) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            hasStartedForeground = false
        }
        if (validateAgainstSchedule) {
            LiveUpdateScheduler.onLiveUpdateStopped(applicationContext)
        }
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val keepAliveExperimentEnabled = isTaskRemovalKeepAliveEnabled()
        getSharedPreferences("native_runtime_prefs", Context.MODE_PRIVATE)
            .edit()
            .putLong("last_task_removed_at", System.currentTimeMillis())
            .apply()
        UmengDiagnosticReporter.record(
            context = applicationContext,
            category = "live_update_task_removed",
            message = DiagnosticLogMessages.LIVE_UPDATE_TASK_REMOVED,
            extras = mapOf(
                "courseName" to courseName,
                "stage" to activityStage,
                "keepAliveExperimentEnabled" to keepAliveExperimentEnabled,
                "hideFromRecentsEnabled" to isHideFromRecentsEnabled(),
            )
        )
        val resumed = LiveUpdateScheduler.reschedule(
            applicationContext,
            allowImmediateStart = true,
            stopStaleSessions = false,
        )
        if (resumed) {
            // 有活跃课程会话被重新拉起来了：保留当前那一帧，什么也不切换。
            UmengDiagnosticReporter.record(
                context = applicationContext,
                category = "live_update_task_removed_resumed",
                message = DiagnosticLogMessages.LIVE_UPDATE_TASK_REMOVED_RESUMED,
                extras = mapOf(
                    "courseName" to courseName,
                    "stage" to activityStage,
                    "keepAliveExperimentEnabled" to keepAliveExperimentEnabled,
                )
            )
        } else if (permanentNotification) {
            // 常驻：用户清后台时哪怕没有课程会话也不能摘通知，切到情侣卡片形态继续
            // 留在状态栏。服务本身跑不住时由闹钟与 15 分钟兜底 Worker 拉回来。
            enterIdleMode()
            refreshIdleNotification(System.currentTimeMillis())
        } else {
            stopAndRemoveNotification()
        }
        super.onTaskRemoved(rootIntent)
    }

    private fun isTaskRemovalKeepAliveEnabled(): Boolean {
        return isHideFromRecentsEnabled()
    }

    private fun startForegroundSafely(intent: Intent?) {
        ensureNotificationChannel()
        if (hasStartedForeground) {
            return
        }

        val bootstrapTitle = intent?.getStringExtra("courseName")
            ?.takeIf { it.isNotBlank() }
            ?.let { getString(R.string.notification_course_reminder_title, it) }
            ?: getString(R.string.app_display_name)
        val notification = buildBootstrapNotification(bootstrapTitle)
        // FOREGROUND_SERVICE_TYPE_SPECIAL_USE is API 34+.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        hasStartedForeground = true
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.notification_channel_live_update_name),
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = getString(R.string.notification_channel_live_update_desc)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildBootstrapNotification(title: String): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }

        return builder
            .setContentTitle(title)
            .setContentText(getString(R.string.notification_preparing_reminder))
            .setSmallIcon(R.drawable.ic_course)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    private fun updateForegroundNotification(notification: Notification) {
        if (!hasStartedForeground) {
            startForeground(NOTIFICATION_ID, notification)
            hasStartedForeground = true
            return
        }

        getSystemService(NotificationManager::class.java)
            ?.notify(NOTIFICATION_ID, notification)
            ?: startForeground(NOTIFICATION_ID, notification)
    }

    // --- 常驻形态（无课程会话时的情侣卡片档） --------------------------------
    //
    // 常驻开关打开时，服务在「没有课程会话」的时间段里不摘通知也不退出，改为展示
    // 情侣卡片那套文案（只取我这一列）。四档形态与胶囊的分工：
    //
    // * 空闲（本段）—— 情侣卡片：课名/时间/地点，或 🍵 今天没有课程 / 🌙 今日课程已结束
    //   / 明日共 N 节 / 未开情侣模式；不上胶囊，也不请求提升。
    // * 课前窗口     —— 课名 + 地点 + 倒计时；ColorOS 上带胶囊（只显示倒计时）。
    // * 课中         —— 课名 + 分段进度条；不上胶囊。
    // * 非常驻模式的旧行为完全保留（会话结束就摘通知并自停）。

    /**
     * 切进常驻空闲形态。只在**从课程会话过来**的那一次重置签名，让第一帧必定重绘，
     * 覆盖掉上一帧残留的课程内容；重复进入不动签名，避免无意义的重复 notify。
     */
    private fun enterIdleMode() {
        if (idleMode) {
            return
        }
        idleMode = true
        lastIdleSignature = ""
    }

    /**
     * 重绘常驻空闲通知，返回本帧签名。
     *
     * 内容无变化时跳过 notify —— 空闲档位的唤醒点可能只差一次时间格式化（例如同一
     * 分钟内连醒两次），没必要让系统重画。
     */
    private fun refreshIdleNotification(now: Long): String {
        val content = liveIdleContent(now)
        val signature = content.signature()
        if (signature == lastIdleSignature) {
            return signature
        }
        lastIdleSignature = signature
        updateForegroundNotification(buildIdleNotification(content))
        updateIdleDebugSnapshot(content)
        return signature
    }

    /**
     * 常驻空闲形态的内容：情侣卡片「我这一列」的实际渲染结果。
     *
     * 卡片不可用（从没同步过 / 未登录 / 未开情侣模式）时照搬卡片的不可用文案，不做
     * 降级 —— 通知说的就是卡片上那句话。
     */
    private fun liveIdleContent(now: Long): LiveIdleContent {
        val snapshot = CoupleTimetableStore.readSnapshot(applicationContext)
            ?: return LiveIdleContent(title = getString(R.string.widget_couple_mode_off))
        val display = CoupleTimetableDisplayBuilder.build(
            context = applicationContext,
            courses = snapshot.mine,
            nowMillis = now,
            status = snapshot.status,
        )
        return buildLiveIdleContent(display)
    }

    /** 常驻空闲形态的通知本体。 */
    private fun buildIdleNotification(content: LiveIdleContent): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        val expandedText = buildString {
            append(content.title)
            content.bodyLines.forEach { append("\n").append(it) }
            if (content.footer.isNotBlank()) {
                append("\n").append(content.footer)
            }
        }

        builder.apply {
            setContentTitle(content.title)
            setContentText(content.bodyLines.firstOrNull() ?: content.footer)
            setSmallIcon(R.drawable.ic_course)
            applyExpandedLargeIcon(this)
            setContentIntent(buildAppLaunchPendingIntent())
            setOngoing(true)
            setAutoCancel(false)
            setOnlyAlertOnce(true)
            setCategory(Notification.CATEGORY_STATUS)
            // 空闲形态不是实时活动，必须让出提升资格：置 true 会让 ColorOS 把这张
            // 卡片也提升成流体云，和「胶囊只显示上课前」的约定冲突。
            setColorized(false)
            setShowWhen(false)
            setWhen(System.currentTimeMillis())
            setUsesChronometer(false)
            setProgress(0, 0, false)
            if (Build.VERSION.SDK_INT >= 36) {
                // 清掉上一次会话可能留下的胶囊文案；提升请求也一并撤掉。
                setShortCriticalText("")
                setExtras(Bundle().apply { putOplusIslandIcon(this@LiveUpdateService, R.drawable.ic_course) })
            }
        }
        builder.setStyle(
            Notification.BigTextStyle()
                .setBigContentTitle(content.title)
                .bigText(expandedText)
                .setSummaryText(content.footer)
        )
        return builder.build()
    }

    /**
     * 常驻空闲形态的唤醒点：只在下一次边界醒来，不再每 60 秒空转。
     *
     * 边界取自 [liveNextBoundaryMinutes]（进入候课窗口、上课、下课），今天再无边界
     * 就睡到跨天。上限 [MAX_IDLE_TICK_DELAY_MILLIS] 兜底，防止改时钟/换时区后
     * 一直不刷新。
     */
    private fun scheduleIdleTick(now: Long) {
        val runnable = ticker ?: return
        handler.postDelayed(runnable, computeIdleTickDelayMillis(now))
    }

    private fun computeIdleTickDelayMillis(now: Long): Long {
        val calendar = Calendar.getInstance().apply { timeInMillis = now }
        val secondsIntoDay = calendar.get(Calendar.HOUR_OF_DAY) * 3600 +
            calendar.get(Calendar.MINUTE) * 60 +
            calendar.get(Calendar.SECOND)
        val nowMinutes = secondsIntoDay / 60
        val boundaryMinutes = liveNextBoundaryMinutes(
            nowMinutes = nowMinutes,
            coursesToday = myTodayCourses(),
            leadMinutes = (beforeClassLeadMillis / 60_000L).toInt(),
        )
        val targetSeconds = boundaryMinutes?.times(60) ?: SECONDS_PER_DAY
        val delaySeconds = (targetSeconds - secondsIntoDay).coerceAtLeast(1)
        return (delaySeconds * 1000L).coerceIn(1_000L, MAX_IDLE_TICK_DELAY_MILLIS)
    }

    /** 情侣快照里我这一侧今天的课（常驻空闲档位判边界用）。 */
    private fun myTodayCourses(): List<CoupleWidgetCourse> {
        return CoupleTimetableStore.readSnapshot(applicationContext)?.mine?.today.orEmpty()
    }

    /**
     * 空闲档位的自检快照。
     *
     * 自检页读的是 buildNotification 里写的 lastDebugSnapshot，而空闲档位根本不走
     * 那条路径；不补这一份，自检页会一直显示上一节课的残留数据。
     */
    private fun updateIdleDebugSnapshot(content: LiveIdleContent) {
        updateDebugSnapshot(
            linkedMapOf(
                "summary" to linkedMapOf(
                    "serviceRunning" to true,
                    "currentStage" to "idle",
                    "resolvedStage" to "idle",
                    "isExpectedToShowIsland" to false,
                    "isActuallyPromotable" to false,
                    "statusText" to getString(R.string.debug_status_running),
                    "notIslandReason" to getString(R.string.debug_promote_not_requested),
                ),
                "service" to linkedMapOf(
                    "serviceRunning" to true,
                    "hasStartedForeground" to hasStartedForeground,
                    "activityStage" to "idle",
                    "resolvedStage" to "idle",
                    "lastRemainingText" to "",
                    "lastProgressUnits" to -1,
                    "lastCriticalTimeText" to "",
                ),
                "switches" to linkedMapOf(
                    "permanentNotification" to permanentNotification,
                ),
                "notification" to linkedMapOf(
                    "permanent" to true,
                    "shouldPromote" to false,
                    "showStandardNotification" to true,
                    "notificationTitle" to content.title,
                    "notificationContentText" to (content.bodyLines.firstOrNull() ?: content.footer),
                    "notificationExpandedText" to content.bodyLines.joinToString("\n"),
                ),
            )
        )
    }

    /**
     * ticker 的统一出口：课程会话结束（或本来就没有会话）时该做什么。
     *
     * 常驻模式下**不摘通知** —— 切到情侣卡片形态，睡到下一个边界继续常驻。这里刻意
     * 用 `stopStaleSessions = false`：调度器不该因为「此刻没有活跃课程」收掉我们，
     * 进程真被系统杀掉后，闹钟是带着新课表负载把服务重新拉起来的唯一通路。
     *
     * 非常驻模式保持原有行为：重排调度，重排不起来就摘通知并自停。
     */
    private fun endSessionOrGoIdle(now: Long) {
        // 已经在空闲档位时不再请求立即启动，否则「调度器认为有课、但按本机设置这节课
        // 不该显示」的组合（例如课前提醒被关掉）会让服务被反复重启、每次又立刻回到
        // 空闲。那种组合交给闹钟在下一个触发点处理即可。
        val resumed = LiveUpdateScheduler.reschedule(
            applicationContext,
            allowImmediateStart = !idleMode,
            stopStaleSessions = false,
        )
        if (resumed) {
            // 调度器已带着新的课表负载把服务重新拉起来了，交给新的 onStartCommand；
            // 这里补一次重试 tick，兜住「重启了但没走到 startTicker」的冻结。
            scheduleTickerRetry()
            return
        }
        if (permanentNotification) {
            enterIdleMode()
            refreshIdleNotification(now)
            scheduleIdleTick(now)
            return
        }
        stopAndRemoveNotification()
    }

    private fun buildAppLaunchPendingIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun buildBeforeClassQuickActions(): List<Notification.Action> {
        val buttons = currentQuickActionButtons()
        val actions = mutableListOf<Notification.Action>()
        if (buttons.silentEnable) {
            actions += buildQuickActionNotificationAction(
                ACTION_ENABLE_SILENT_MODE,
                getString(R.string.action_enable_silent),
            )
        }
        if (buttons.silentCancel) {
            actions += buildQuickActionNotificationAction(
                ACTION_CANCEL_SILENT_MODE,
                getString(R.string.action_cancel_silent),
            )
        }
        if (buttons.dndEnable) {
            actions += buildQuickActionNotificationAction(
                ACTION_ENABLE_DO_NOT_DISTURB,
                getString(R.string.action_enable_dnd),
            )
        }
        if (buttons.dndCancel) {
            actions += buildQuickActionNotificationAction(
                ACTION_CANCEL_DO_NOT_DISTURB,
                getString(R.string.action_cancel_dnd),
            )
        }
        return actions
    }

    private fun buildQuickActionNotificationAction(
        intentAction: String,
        label: String,
    ): Notification.Action {
        val pendingIntent = PendingIntent.getService(
            this,
            intentAction.hashCode(),
            Intent(this, LiveUpdateService::class.java).apply {
                this.action = intentAction
                putExtra("endAtMillis", endAtMillis)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Action.Builder(
            Icon.createWithResource(this, R.drawable.ic_notification),
            label,
            pendingIntent,
        ).build()
    }

    private fun currentQuickActionButtons(): BeforeClassQuickActionButtons {
        if (beforeClassQuickAction == BeforeClassQuickActionRestore.ACTION_NONE) {
            return BeforeClassQuickActionButtons()
        }
        return beforeClassQuickActionButtons(
            action = beforeClassQuickAction,
            silentCurrentlyActive =
                BeforeClassQuickActionRestore.isSilentModeActive(applicationContext),
            dndCurrentlyActive =
                BeforeClassQuickActionRestore.isDoNotDisturbModeActive(applicationContext),
        )
    }

    private fun handleCancelQuickAction(quickAction: String) {
        val applied = if (quickAction == BeforeClassQuickActionRestore.ACTION_SILENT) {
            BeforeClassQuickActionRestore.cancelSilentMode(applicationContext)
        } else {
            BeforeClassQuickActionRestore.cancelDoNotDisturbMode(applicationContext)
        }
        if (!applied) {
            if (quickAction == BeforeClassQuickActionRestore.ACTION_DO_NOT_DISTURB) {
                openNotificationPolicyAccessSettings()
            } else {
                openSoundSettings()
            }
        }
        // 与手动打开一致：一次手动取消即代表本节课不再自动执行
        BeforeClassQuickActionRestore.markTriggerHandled(applicationContext, startAtMillis)
        UmengDiagnosticReporter.record(
            context = applicationContext,
            category = "live_update_before_class_quick_action",
            message = DiagnosticLogMessages.LIVE_UPDATE_BEFORE_CLASS_QUICK_ACTION,
            extras = mapOf(
                "action" to "cancel_$quickAction",
                "applied" to applied,
                "courseName" to courseName,
                "stage" to activityStage,
            )
        )
        refreshQuickActionNotification()
    }

    /** 通知按钮跟随真实铃声/勿扰状态；状态翻转后立即重建通知并更新缓存签名。 */
    private fun refreshQuickActionNotification() {
        if (hasStartedForeground) {
            updateForegroundNotification(
                buildNotification(computeRemainingText(System.currentTimeMillis()))
            )
        }
        lastQuickActionState = currentQuickActionButtons().toString()
    }

    private fun buildDismissStatusBarAction(): Notification.Action {
        val pendingIntent = PendingIntent.getService(
            this,
            ACTION_DISMISS_STATUS_BAR_STAGE.hashCode(),
            Intent(this, LiveUpdateService::class.java).apply {
                action = ACTION_DISMISS_STATUS_BAR_STAGE
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Action.Builder(
            Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel),
            getString(R.string.action_close),
            pendingIntent,
        ).build()
    }

    private fun handleBeforeClassQuickAction(action: String) {
        val restoreAtMillis = endAtMillis.takeIf { it > 0L }
            ?: (System.currentTimeMillis() + 2 * 60 * 60_000L)
        val applied = when (action) {
            BeforeClassQuickActionRestore.ACTION_SILENT ->
                applyQuickActionMode(enableDoNotDisturb = false, restoreAtMillis)
            BeforeClassQuickActionRestore.ACTION_DO_NOT_DISTURB ->
                applyQuickActionMode(enableDoNotDisturb = true, restoreAtMillis)
            BeforeClassQuickActionRestore.ACTION_BOTH -> {
                val silentApplied =
                    applyQuickActionMode(enableDoNotDisturb = false, restoreAtMillis)
                val dndApplied =
                    applyQuickActionMode(enableDoNotDisturb = true, restoreAtMillis)
                silentApplied || dndApplied
            }
            else -> false
        }
        // A manual tap settles the whole quick action for this course session,
        // so the scheduled auto run must not re-apply it mid-session.
        BeforeClassQuickActionRestore.markTriggerHandled(
            applicationContext,
            startAtMillis,
        )
        UmengDiagnosticReporter.record(
            context = applicationContext,
            category = "live_update_before_class_quick_action",
            message = DiagnosticLogMessages.LIVE_UPDATE_BEFORE_CLASS_QUICK_ACTION,
            extras = mapOf(
                "action" to action,
                "applied" to applied,
                "courseName" to courseName,
                "stage" to activityStage,
            )
        )
        refreshQuickActionNotification()
    }

    private fun applyQuickActionMode(
        enableDoNotDisturb: Boolean,
        restoreAtMillis: Long,
    ): Boolean {
        return if (enableDoNotDisturb) {
            val enabled = BeforeClassQuickActionRestore.enableDoNotDisturbMode(
                this,
                restoreAtMillis,
            )
            if (!enabled) {
                openNotificationPolicyAccessSettings()
            }
            enabled
        } else {
            val enabled = BeforeClassQuickActionRestore.enableSilentMode(
                this,
                restoreAtMillis,
            )
            if (!enabled) {
                openSoundSettings()
            }
            enabled
        }
    }

    private fun maybeApplyAutoQuickAction(nowMillis: Long) {
        if (quickActionAutoLeadMillis <= 0L ||
            beforeClassQuickAction == BeforeClassQuickActionRestore.ACTION_NONE
        ) {
            return
        }
        val dueAtMillis = startAtMillis - quickActionAutoLeadMillis
        if (nowMillis < dueAtMillis) {
            return
        }
        BeforeClassQuickActionRestore.applyAutoQuickAction(
            context = applicationContext,
            action = beforeClassQuickAction,
            triggerKeyMillis = startAtMillis,
            restoreAtMillis = endAtMillis,
        )
    }

    private fun dismissStatusBarStage() {
        markServiceStopped(getString(R.string.stop_status_bar_dismissed))
        UmengDiagnosticReporter.record(
            context = applicationContext,
            category = "live_update_status_bar_dismissed",
            message = DiagnosticLogMessages.LIVE_UPDATE_STATUS_BAR_DISMISSED,
            extras = mapOf(
                "courseName" to courseName,
                "stage" to activityStage,
            )
        )
        stopTicker()
        if (hasStartedForeground) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            hasStartedForeground = false
        }
        stopSelf()
    }

    private fun readQuickActionTimingExtra(intent: Intent?) {
        val restoreAtMillis = intent?.getLongExtra("endAtMillis", 0L) ?: 0L
        if (restoreAtMillis > 0L) {
            endAtMillis = restoreAtMillis
        }
    }

    private fun restoreBeforeClassQuickActionIfClassEnded() {
        BeforeClassQuickActionRestore.restoreIfClassEnded(applicationContext)
    }

    private fun openNotificationPolicyAccessSettings() {
        openSettingsIntent(
            Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
        )
    }

    private fun openSoundSettings() {
        openSettingsIntent(Intent(Settings.ACTION_SOUND_SETTINGS))
    }

    private fun openSettingsIntent(intent: Intent) {
        try {
            startActivity(intent.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) })
        } catch (e: Exception) {
            Log.w(TAG, DiagnosticLogMessages.LOG_OPEN_SETTINGS_INTENT_FAILED, e)
            try {
                startActivity(
                    Intent(Settings.ACTION_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                )
            } catch (fallbackError: Exception) {
                Log.w(TAG, DiagnosticLogMessages.LOG_OPEN_FALLBACK_SETTINGS_FAILED, fallbackError)
            }
        }
    }

    private fun isHideFromRecentsEnabled(): Boolean {
        return getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_HIDE_FROM_RECENTS, false)
    }

    private fun hasCompleteLivePayload(intent: Intent?): Boolean {
        if (intent == null) {
            return false
        }
        val courseName = intent.getStringExtra("courseName")
        val stage = intent.getStringExtra("stage")
        val startAtMillis = intent.getLongExtra("startAtMillis", 0L)
        val endAtMillis = intent.getLongExtra("endAtMillis", 0L)
        return !courseName.isNullOrBlank() &&
            !stage.isNullOrBlank() &&
            startAtMillis > 0L &&
            endAtMillis > 0L &&
            endAtMillis >= startAtMillis
    }

    private fun startTicker() {
        stopTicker()
        ticker = object : Runnable {
            override fun run() {
                val now = System.currentTimeMillis()
                BeforeClassQuickActionRestore.restoreIfClassEnded(applicationContext, now)
                maybeApplyAutoQuickAction(now)
                if (validateAgainstSchedule &&
                    !LiveUpdateScheduler.hasActiveLiveSelection(applicationContext, now)
                ) {
                    endSessionOrGoIdle(now)
                    return
                }
                val stage = resolveStage(now)
                if (autoDismissAfterStartMinutes > 0 &&
                    now >= startAtMillis + autoDismissAfterStartMinutes * 60_000L
                ) {
                    endSessionOrGoIdle(now)
                    return
                }

                if (stage == null) {
                    endSessionOrGoIdle(now)
                    return
                }
                // 走到这里说明这一轮确实是课程会话（课前或课中）：作废空闲形态的签名，
                // 会话结束后重新进空闲时会重绘第一帧。
                idleMode = false

                // When stage transitions, reschedule so onStartCommand re-reads
                // the correct displaySettings for the new stage.
                if (lastTickerStage != null && stage != lastTickerStage) {
                    lastTickerStage = stage
                    endSessionOrGoIdle(now)
                    return
                }
                lastTickerStage = stage

                if (now >= endAtMillis + 30_000L) { // Auto-remove 30s after class end, especially for tests.
                    endSessionOrGoIdle(now)
                    return
                }

                val currentText = computeRemainingText(now)
                val currentDuringClassProgress = if (stage == "duringClass") {
                    buildDuringClassProgress(now)
                } else {
                    null
                }
                val currentCriticalTimeText = currentDuringClassProgress?.criticalTimeText ?: currentText
                val shouldRefreshProgressThisTick =
                    currentDuringClassProgress?.updatesEverySecond == true
                val currentProgress =
                    if (shouldRefreshProgressThisTick) {
                        currentDuringClassProgress.progressUnits
                    } else {
                        -1
                    }
                val currentQuickActionState = currentQuickActionButtons().toString()
                if (currentText != lastRemainingText ||
                    currentProgress != lastProgressUnits ||
                    currentCriticalTimeText != lastCriticalTimeText ||
                    currentQuickActionState != lastQuickActionState
                ) {
                    lastRemainingText = currentText
                    lastProgressUnits = currentProgress
                    lastCriticalTimeText = currentCriticalTimeText
                    lastQuickActionState = currentQuickActionState
                    getSystemService(NotificationManager::class.java)
                        ?.notify(NOTIFICATION_ID, buildNotification(currentText))
                }

                handler.postDelayed(this, computeNextTickDelayMillis(now, stage, currentDuringClassProgress))
            }
        }
        handler.post(ticker!!)
    }

    private fun stopTicker() {
        ticker?.let { runnable ->
            handler.removeCallbacks(runnable)
        }
        ticker = null
    }

    /**
     * 续排一次重试 tick（ticker 已停则什么都不做）。
     *
     * ticker 里那几处 `LiveUpdateScheduler.reschedule(...)` 出口都是「调用完就 return，
     * 指望 reschedule 把服务重新拉起来接着跑」。但 reschedule 返回 true 只代表
     * `startForegroundService` 调用成功，**并不保证 onStartCommand 一定会走到
     * startTicker()**：后台 FGS 启动可能被拦、测试会话可能挂起调度、或该次启动因
     * payload 不完整走早退分支。一旦没走到，ticker 就永久停摆，通知冻结在最后一帧
     * —— 实机（OPPO PLA110 / ColorOS 16）出现过「创建后 4 秒再没更新、连
     * endAtMillis+30s 的自动移除都没发生」的冻结。
     *
     * 补这一次重试就能兜住：服务真被重启时 onStartCommand → startTicker() 会先
     * removeCallbacks 清掉它（单线程主 looper，不存在两个 ticker 并存）；只有没重启时
     * 它才生效，下一拍重新走一遍判定。通知已被移除时 ticker 为 null，自然不再续排。
     */
    private fun scheduleTickerRetry() {
        val runnable = ticker ?: return
        handler.postDelayed(runnable, TICKER_RETRY_DELAY_MILLIS)
    }

    private fun computeRemainingText(now: Long): String {
        val stage = resolveStage(now)
        val prefixTextStart = if (hidePrefixText) "" else getString(R.string.prefix_until_class_start)

        return if (!showCountdown) {
            ""
        } else {
            when (stage) {
                "beforeClass" -> {
                    if (liveShouldShowClassStartingPrompt(stage, now, startAtMillis)) {
                        // 上课信号顶掉倒计时，也不要「距上课」前缀。
                        getString(R.string.island_class_starting)
                    } else {
                        val timeUntilStart = (startAtMillis - now).coerceAtLeast(0L)
                        "${prefixTextStart}${formatCountdownDuration(
                            durationMillis = timeUntilStart,
                            secondsThresholdMillis = 60_000L,
                        )}"
                    }
                }
                "duringClass",
                "duringClassStatusBar" -> getString(R.string.stage_in_class)
                else -> ""
            }
        }
    }

    private fun resolveStage(now: Long): String? {
        if (now >= endAtMillis) {
            return null
        }
        // Do not show the before-class stage earlier than its window start.
        // (leadMillis == 0 means the caller did not supply a window; keep the
        // legacy behavior of trusting the start intent in that case.)
        if (beforeClassLeadMillis > 0L && now < startAtMillis - beforeClassLeadMillis) {
            return null
        }

        val reminderStart = if (liveClassReminderStartMinutes == 0) {
            startAtMillis
        } else {
            maxOf(startAtMillis, endAtMillis - liveClassReminderStartMinutes * 60_000L)
        }
        // 「下课提醒」（beforeEnd）阶段已移除：过了重点提醒起点后一律课中，
        // 直到 endAtMillis 结束。
        return when {
            now < startAtMillis -> if (enableBeforeClass) "beforeClass" else null
            liveClassReminderStartMinutes > 0 && now < reminderStart ->
                if (enableDuringClass && showNotificationDuringClass) {
                    "duringClassStatusBar"
                } else {
                    null
                }
            now < reminderStart -> null
            canDisplayDuringStage() -> "duringClass"
            else -> null
        }
    }

    private fun canDisplayDuringStage(): Boolean {
        return enableDuringClass && (promoteDuringClass || showNotificationDuringClass)
    }

    /**
     * ColorOS 流体云胶囊的右侧文案。**只有 ColorOS 走这条规则**，其它品牌维持
     * 各自原有行为（见 `buildNotification` 里 `islandCriticalText` 的分支）。
     *
     * 胶囊在这一侧只呈现「上课前」这一件事：到上课的分钟数，最后 5 秒换成
     * 「开始上课」。课名、地点、教师、时间区间一概不进胶囊，只进下拉通知 ——
     * 胶囊和下拉是两个互不干扰的面，改下拉的展示不会改变胶囊这一行。
     *
     * 为什么只给短文案：左侧小图标槽实测是约 50px 的圆形位、放不下文字，右侧
     * 可用宽度只有 6–7 个字，秒级倒计时还会让胶囊随数字位数不断变宽变窄（用户
     * 可见的「长度一直在跳」），所以一律分钟粒度。
     *
     * 课中那几档目前不可达：提升已限定为仅课前（见 [liveShouldPromoteStage]），
     * 本函数的输出只在 `setShortCriticalText` 那里随提升一起下发。保留分支是为了
     * 课中若重新上岛时不必重写文案规则。
     *
     * 「大课下课后下一次上课的倒计时」不在这里处理：下一节课进入自己的课前
     * 提醒窗口时会由 beforeClass 分支自然接管；间隔过大（11:40 下课、14:00 再
     * 上课）时不会进入该窗口，于是自然不显示。
     */
    private fun buildColorosIslandText(stage: String?, now: Long): String = when (stage) {
        "beforeClass" -> if (liveShouldShowClassStartingPrompt(stage, now, startAtMillis)) {
            getString(R.string.island_class_starting)
        } else {
            colorosMinutesText(startAtMillis - now)
        }
        "duringClass", "duringClassStatusBar" -> buildColorosDuringClassText(now)
        else -> ""
    }

    private fun buildColorosDuringClassText(now: Long): String {
        if (endAtMillis - now <= ABOUT_TO_END_WINDOW_MILLIS) {
            return getString(R.string.island_about_to_end)
        }
        // 大课内部课间：milestone 偏移按「最近下课 / 下节上课」交替排列，
        // 当前落在偶数下标之后（下课之后、下节上课之前）即为课间。
        val elapsed = now - startAtMillis
        val lastIndex = progressBreakOffsetsMillis.indexOfLast { it <= elapsed }
        if (lastIndex >= 0 && lastIndex % 2 == 0) {
            val nextSectionStart = progressBreakOffsetsMillis.getOrNull(lastIndex + 1)
            if (nextSectionStart != null && nextSectionStart > elapsed) {
                return colorosMinutesText(nextSectionStart - elapsed)
            }
        }
        return getString(R.string.stage_in_class)
    }

    private fun colorosMinutesText(remainingMillis: Long): String {
        val minutes = (remainingMillis.coerceAtLeast(0L) / 60_000L).coerceAtLeast(1L)
        return getString(R.string.island_minutes_remaining, minutes.toInt())
    }

    private fun isXiaomiFamilyDevice(): Boolean =
        liveSurfaceBrand(Build.MANUFACTURER, Build.BRAND) == LiveSurfaceBrand.XIAOMI

    private fun dp(value: Float): Float =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value, resources.displayMetrics)

    private fun sp(value: Float): Float =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, value, resources.displayMetrics)

    private fun resolveIslandLabelBitmap(text: String): Bitmap? {
        if (!enableMiuiIslandLabelImage || !isXiaomiFamilyDevice() || text.isBlank()) {
            return null
        }

        val cacheKey = listOf(
            text,
            miuiIslandLabelStyle,
            miuiIslandLabelFontColor,
            miuiIslandLabelFontWeight,
            miuiIslandLabelRenderQuality,
            miuiIslandLabelFontSize.toString(),
            miuiIslandLabelOffsetX.toString(),
            miuiIslandLabelOffsetY.toString(),
            miuiIslandLabelLogoPath.orEmpty(),
            miuiIslandLabelLogoCornerRadius.toString(),
        ).joinToString("|")
        if (cacheKey == cachedIslandBitmapKey && cachedIslandBitmap != null) {
            return cachedIslandBitmap
        }

        val bitmap = buildIslandLabelBitmap(
            text = text,
            includeAppIcon = miuiIslandLabelStyle == "icon_and_text",
            customIconPath = miuiIslandLabelLogoPath,
            customIconCornerRadiusDp = miuiIslandLabelLogoCornerRadius,
            fontColorHex = miuiIslandLabelFontColor,
            fontWeight = miuiIslandLabelFontWeight,
            renderQuality = miuiIslandLabelRenderQuality,
            fontSizeSp = miuiIslandLabelFontSize,
            offsetXDp = miuiIslandLabelOffsetX,
            offsetYDp = miuiIslandLabelOffsetY,
        )
        cachedIslandBitmapKey = cacheKey
        cachedIslandBitmap = bitmap
        return bitmap
    }

    private fun buildIslandLabelBitmap(
        text: String,
        includeAppIcon: Boolean,
        customIconPath: String?,
        customIconCornerRadiusDp: Float,
        fontColorHex: String,
        fontWeight: String,
        renderQuality: String,
        fontSizeSp: Float,
        offsetXDp: Float,
        offsetYDp: Float,
    ): Bitmap? {
        val resolvedFontSizeSp = fontSizeSp.coerceIn(1f, 32f)
        val renderScale = when (renderQuality) {
            "high" -> 3f
            "ultra" -> 4f
            else -> 2f
        }
        val textColor = parseColorHexOrDefault(fontColorHex, 0xFFFFFFFF.toInt())
        val typeface = resolveIslandLabelTypeface(fontWeight)
        val baseTextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = textColor
            textSize = sp(resolvedFontSizeSp)
            this.typeface = typeface
            // 粗细档位说明：真实 Typeface 的 BOLD 样式对拉丁字形有效，
            // 但中文字形走系统回退字体（MiSans 等），样式请求常不生效，
            // 可见的加粗主要依赖 isFakeBoldText 描边实现，故 bold 档必须保留。
            isFakeBoldText = fontWeight == "bold"
            isSubpixelText = true
            isLinearText = true
        }
        val iconSizeDp = if (includeAppIcon) 24f else 0f
        val iconGapDp = if (includeAppIcon) 3f else 0f
        val horizontalPaddingDp = if (includeAppIcon) 3f else 0.75f
        val verticalPaddingDp = 0.5f
        val maxWidthDp = if (includeAppIcon) 132f else 112f
        val maxTextWidthPx = dp(
            maxWidthDp - horizontalPaddingDp * 2f - iconSizeDp - iconGapDp
        ).coerceAtLeast(dp(28f))

        var fittedSizeSp = resolvedFontSizeSp
        while (fittedSizeSp > 1f) {
            baseTextPaint.textSize = sp(fittedSizeSp)
            if (baseTextPaint.measureText(text) <= maxTextWidthPx) {
                break
            }
            fittedSizeSp -= 1f
        }

        // 清晰度修正（在保留字重档位可见性的前提下）：
        // 1) bold 档保留 isFakeBoldText——中文字形走系统回退字体，
        //    真实 Bold 样式请求常不生效，假粗体是“粗”的唯一可靠来源；
        // 2) 去掉 setShadowLayer 文字投影——半透明阴影经系统缩小后
        //    晕成灰色光晕包住笔画，是小字观感“完全模糊”的主要来源；
        // 3) 字号取整到整数物理像素，避免轮廓被分数像素缩放软化。
        val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = textColor
            textSize = Math.round(sp(fittedSizeSp) * renderScale).toFloat()
            this.typeface = typeface
            isFakeBoldText = fontWeight == "bold"
            isSubpixelText = true
            isLinearText = true
        }

        val displayText = if (baseTextPaint.measureText(text) <= maxTextWidthPx) {
            text
        } else {
            TextUtils.ellipsize(
                text,
                baseTextPaint,
                maxTextWidthPx,
                TextUtils.TruncateAt.END
            ).toString()
        }

        val glyphBounds = Rect()
        textPaint.getTextBounds(displayText, 0, displayText.length, glyphBounds)
        val textWidthPx = textPaint.measureText(displayText)
        val textHeightPx = glyphBounds.height().toFloat().coerceAtLeast(sp(1f) * renderScale)
        val iconSizePx = (dp(iconSizeDp) * renderScale).toInt()
        val iconGapPx = dp(iconGapDp) * renderScale
        val horizontalPaddingPx = dp(horizontalPaddingDp) * renderScale
        val verticalPaddingPx = dp(verticalPaddingDp) * renderScale
        val textOnlyMinHeightPx = dp(18f) * renderScale
        val clampedOffsetXDp = offsetXDp.coerceIn(-2f, 2f)
        val clampedOffsetYDp = offsetYDp.coerceIn(-2f, 2f)
        val horizontalOffsetPx = dp(clampedOffsetXDp) * renderScale
        val verticalOffsetPx = dp(clampedOffsetYDp) * renderScale

        val contentWidth = (
            horizontalPaddingPx * 2f +
                textWidthPx +
                if (includeAppIcon) iconSizePx + iconGapPx else 0f
            )
        val width = maxOf(
            ceil(contentWidth).toInt(),
            if (includeAppIcon) (dp(20f) * renderScale).toInt() else 1
        )
        val contentHeight = (
            verticalPaddingPx * 2f + maxOf(textHeightPx, iconSizePx.toFloat())
            )
        val height = maxOf(
            contentHeight,
            if (includeAppIcon) sp(1f) * renderScale else textOnlyMinHeightPx
        ).toInt()
        if (width <= 0 || height <= 0) {
            return null
        }

        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        var textStartX = horizontalPaddingPx
        val centerY = height / 2f

        if (includeAppIcon) {
            val iconTop = ((height - iconSizePx) / 2f).toInt()
            val customBitmap = customIconPath?.let {
                decodeSquareBitmap(it, iconSizePx.coerceAtLeast(1))
            }
            if (customBitmap != null) {
                drawRoundedBitmap(
                    canvas = canvas,
                    bitmap = customBitmap,
                    left = horizontalPaddingPx,
                    top = iconTop.toFloat(),
                    sizePx = iconSizePx.toFloat(),
                    cornerRadiusPx = (dp(customIconCornerRadiusDp.coerceIn(0f, 12f)) * renderScale)
                        .coerceAtMost(iconSizePx / 2f),
                )
            } else {
                val appIcon = packageManager.getApplicationIcon(packageName)
                appIcon.setBounds(
                    horizontalPaddingPx.toInt(),
                    iconTop,
                    horizontalPaddingPx.toInt() + iconSizePx,
                    iconTop + iconSizePx
                )
                appIcon.draw(canvas)
            }
            textStartX += iconSizePx + iconGapPx
        } else {
            textStartX = (
                (width - textWidthPx) / 2f + horizontalOffsetPx
            ).coerceIn(horizontalPaddingPx, width - horizontalPaddingPx - textWidthPx)
        }
        if (includeAppIcon) {
            textStartX = (
                textStartX + horizontalOffsetPx
            ).coerceIn(horizontalPaddingPx, width - horizontalPaddingPx - textWidthPx)
        }
        val baseline = centerY - (glyphBounds.top + glyphBounds.bottom) / 2f + verticalOffsetPx
        // 绘制坐标取整到整数物理像素，消除子像素抗锯齿造成的整体发蒙。
        canvas.drawText(
            displayText,
            Math.round(textStartX).toFloat(),
            Math.round(baseline).toFloat(),
            textPaint,
        )
        return bitmap
    }

    private fun drawRoundedBitmap(
        canvas: Canvas,
        bitmap: Bitmap,
        left: Float,
        top: Float,
        sizePx: Float,
        cornerRadiusPx: Float,
    ) {
        if (cornerRadiusPx <= 0f) {
            canvas.drawBitmap(bitmap, left, top, null)
            return
        }
        val rect = RectF(left, top, left + sizePx, top + sizePx)
        val shader = BitmapShader(bitmap, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.shader = shader
            isFilterBitmap = true
        }
        canvas.drawRoundRect(rect, cornerRadiusPx, cornerRadiusPx, paint)
    }

    private fun parseColorHexOrDefault(colorHex: String?, fallback: Int): Int {
        val normalized = colorHex?.trim()?.removePrefix("#")?.takeIf { it.isNotBlank() } ?: return fallback
        return try {
            when (normalized.length) {
                6 -> (0xFF000000 or normalized.toLong(16)).toInt()
                8 -> normalized.toLong(16).toInt()
                else -> fallback
            }
        } catch (_: Exception) {
            fallback
        }
    }

    private fun resolveIslandLabelTypeface(fontWeight: String): Typeface {
        return when (fontWeight) {
            "regular" -> Typeface.create(Typeface.SANS_SERIF, Typeface.NORMAL)
            "medium" -> Typeface.create("sans-serif-medium", Typeface.NORMAL)
            else -> Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        }
    }

    private fun buildMiuiFocusParam(
        title: String,
        remainingText: String,
        timeRangeText: String,
        bodyContent: String,
        visibleLocation: String,
        stage: String?,
        classProgress: DuringClassProgress?,
        startAtMillis: Long,
        endAtMillis: Long,
        islandName: String,
        progressBreakOffsetsMillis: LongArray,
        progressMilestoneLabels: List<String>,
        progressMilestoneTimeTexts: List<String>,
    ): String? {
        if (!isXiaomiFamilyDevice()) {
            return null
        }

        return try {
            val extraInfo = JSONObject().apply {
                if (visibleLocation.isNotBlank()) put("location", visibleLocation)
                if (teacher.isNotBlank()) put("teacher", teacher)
                if (timeRangeText.isNotBlank()) put("time", timeRangeText)
                if (nextName.isNotBlank()) put("nextCourse", nextName)
            }

            // 摘要态：岛内容
            val paramIsland = buildIslandSummary(
                stage = stage,
                classProgress = classProgress,
                islandName = islandName,
                visibleLocation = visibleLocation,
                startAtMillis = startAtMillis,
                endAtMillis = endAtMillis,
                progressBreakOffsetsMillis = progressBreakOffsetsMillis,
                progressMilestoneLabels = progressMilestoneLabels,
                progressMilestoneTimeTexts = progressMilestoneTimeTexts,
            )

            val paramV2 = JSONObject().apply {
                put("protocol", 1)
                put("business", "class_schedule")
                put("updatable", true)
                put("enableFloat", true)
                put("ticker", title)
                // 展开态：焦点通知卡片
                put(
                    "baseInfo",
                    JSONObject().apply {
                        put("title", title)
                        put("content", bodyContent.ifBlank { remainingText })
                        put("type", 2)
                    }
                )
                if (remainingText.isNotBlank()) {
                    put(
                        "hintInfo",
                        JSONObject().apply {
                            put("type", 1)
                            put("title", remainingText)
                        }
                    )
                }
                if (extraInfo.length() > 0) {
                    put("extraInfo", extraInfo)
                }
                put("param_island", paramIsland)
            }

            JSONObject().apply {
                put("param_v2", paramV2)
            }.toString()
        } catch (e: Exception) {
            Log.w(TAG, DiagnosticLogMessages.LOG_BUILD_MIUI_FOCUS_PARAM_FAILED, e)
            null
        }
    }

    private fun buildIslandSummary(
        stage: String?,
        classProgress: DuringClassProgress?,
        islandName: String,
        visibleLocation: String,
        startAtMillis: Long,
        endAtMillis: Long,
        progressBreakOffsetsMillis: LongArray,
        progressMilestoneLabels: List<String>,
        progressMilestoneTimeTexts: List<String>,
    ): JSONObject {
        val totalMillis = (endAtMillis - startAtMillis).coerceAtLeast(1L)
        val now = System.currentTimeMillis()
        val elapsedMillis = (now - startAtMillis).coerceIn(0L, totalMillis)
        val progressPercent = classProgress?.progressPercent
            ?: ((elapsedMillis.toDouble() / totalMillis.toDouble()) * 100).toInt().coerceIn(0, 100)

        val islandContentText = when (stage) {
            "beforeClass" -> remainingTextForIsland(stage, startAtMillis, endAtMillis)
            else -> classProgress?.compactDisplayText ?: getString(R.string.stage_in_class)
        }

        val bigIslandArea = JSONObject().apply {
            // A 区：图文组件1
            val imageTextInfoLeft = JSONObject().apply {
                put("type", 1)
                put(
                    "textInfo",
                    JSONObject().apply {
                        put("title", islandName)
                        put("content", islandContentText)
                    }
                )
                // 上课中阶段显示环形进度
                if (stage == "duringClass" && classProgress != null) {
                    put(
                        "progressInfo",
                        JSONObject().apply {
                            put("progress", progressPercent)
                            put("colorReach", "#4CAF50")
                            put("colorUnReach", "#33FFFFFF")
                        }
                    )
                }
            }
            put("imageTextInfoLeft", imageTextInfoLeft)

            // B 区：仅上课中阶段显示线性进度+节点
            if (stage == "duringClass" && classProgress != null) {
                val milestonePoints = buildMilestonePoints(
                    progressBreakOffsetsMillis,
                    progressMilestoneLabels,
                    progressMilestoneTimeTexts,
                    totalMillis,
                )
                val progressTextInfo = JSONObject().apply {
                    put(
                        "progressInfo",
                        JSONObject().apply {
                            put("progress", progressPercent)
                            put("colorReach", "#4CAF50")
                            put("colorUnReach", "#33FFFFFF")
                            if (milestonePoints.isNotEmpty()) {
                                put("picMiddle", milestonePoints.first().picKey)
                            }
                        }
                    )
                    put(
                        "textInfo",
                        JSONObject().apply {
                            val nextMilestone = classProgress.nextMilestoneDisplayText
                            if (nextMilestone != null) {
                                put("title", nextMilestone)
                            } else {
                                put("title", classProgress.finalDismissDisplayText)
                            }
                        }
                    )
                }
                put("progressTextInfo", progressTextInfo)
            }
        }

        val smallIslandArea = JSONObject()

        return JSONObject().apply {
            put("islandProperty", 1)
            put("islandTimeout", 3600)
            put("bigIslandArea", bigIslandArea)
            put("smallIslandArea", smallIslandArea)
        }
    }

    private fun remainingTextForIsland(
        stage: String?,
        startAtMillis: Long,
        endAtMillis: Long,
    ): String {
        val now = System.currentTimeMillis()
        return when (stage) {
            "beforeClass" -> {
                val remaining = startAtMillis - now
                if (remaining > 0) {
                    getString(R.string.remaining_until_class_start, formatCountdownDuration(remaining))
                } else {
                    getString(R.string.stage_before_class)
                }
            }
            else -> getString(R.string.stage_in_class)
        }
    }

    private data class MilestonePoint(
        val position: Int,
        val picKey: String,
    )

    private fun buildMilestonePoints(
        progressBreakOffsetsMillis: LongArray,
        progressMilestoneLabels: List<String>,
        progressMilestoneTimeTexts: List<String>,
        totalMillis: Long,
    ): List<MilestonePoint> {
        if (progressBreakOffsetsMillis.isEmpty() || totalMillis <= 0) return emptyList()
        val points = mutableListOf<MilestonePoint>()
        for (index in progressBreakOffsetsMillis.indices) {
            val offsetMillis = progressBreakOffsetsMillis[index]
            val position = ((offsetMillis.toDouble() / totalMillis.toDouble()) * 100)
                .toInt().coerceIn(1, 99)
            val label = progressMilestoneLabels.getOrNull(index) ?: continue
            points.add(MilestonePoint(position = position, picKey = "miui.focus.pic_milestone_$index"))
        }
        return points.distinctBy { it.position }.sortedBy { it.position }
    }

    private fun decodeSquareBitmap(path: String, targetSize: Int): Bitmap? {
        val source = BitmapFactory.decodeFile(path) ?: return null
        val side = minOf(source.width, source.height)
        if (side <= 0) {
            source.recycle()
            return null
        }
        val offsetX = ((source.width - side) / 2).coerceAtLeast(0)
        val offsetY = ((source.height - side) / 2).coerceAtLeast(0)
        val cropped = Bitmap.createBitmap(source, offsetX, offsetY, side, side)
        if (cropped != source) {
            source.recycle()
        }
        val resolvedTargetSize = targetSize.coerceAtLeast(1)
        if (cropped.width == resolvedTargetSize && cropped.height == resolvedTargetSize) {
            return cropped
        }
        val scaled = Bitmap.createScaledBitmap(cropped, resolvedTargetSize, resolvedTargetSize, true)
        if (scaled != cropped) {
            cropped.recycle()
        }
        return scaled
    }

    private fun decodeExpandedIconBitmap(path: String): Bitmap? {
        val targetSize = dp(56f).toInt().coerceAtLeast(96)
        return decodeSquareBitmap(path, targetSize)
    }

    /**
     * 【实验】逆向的 OPPO 私有字段试探 —— 让流体云卡片用我们下发的阶段图标，
     * 而不是被系统换成的应用图标。
     *
     * 真机 dump（PLA110 / ColorOS 16）显示：ColorOS 会自己往通知 extras 里塞
     * `oplus_smallicon_use_app_icon=true`，并把 `oplus_small_icon` 覆盖成
     * `mipmap/ic_launcher`，于是卡片右上角永远显示应用图标，而不是 `setSmallIcon`
     * 下发的时钟 / 书图标。
     *
     * 这里反向主张一次：显式给出我们想要的图标，并把「用应用图标」关掉。这两个键
     * 不在任何公开文档里，ColorOS 完全可能忽略 —— 属试探性改动，确认无效即撤。
     * 注意它只影响图标**内容**，图标**位置**（卡片右上）由系统布局决定，改不了。
     */
    private fun Bundle.putOplusIslandIcon(context: Context, iconRes: Int) {
        putParcelable("oplus_small_icon", Icon.createWithResource(context, iconRes))
        putBoolean("oplus_smallicon_use_app_icon", false)
    }

    /**
     * 流体云展开卡片的**左侧大图位**。
     *
     * 实机对照（ColorOS 16 / PLA110，酷狗媒体卡 vs 本应用卡）确认卡片有两个
     * 互不相干的图标槽：
     * - **右上角**是「应用身份」位，恒由系统绘制（本应用上系统还会用
     *   `oplus_small_icon` 把它覆盖成应用图标，我们设的 `setSmallIcon` 不生效）；
     * - **左侧那张大图来自 `setLargeIcon`** —— 酷狗用专辑封面填它。
     *
     * ⚠️ 回归记录：曾按「展开态图标只在小米岛生效」把这里对非小米系提前 return，
     * 结果 ColorOS 上左侧大图位空掉、卡片只剩右上角的应用图标，看起来就是
     * 「图标跑到右边了」。该判断是错的：largeIcon 在 ColorOS 上**正是左侧大图位的
     * 来源**，必须照常下发。
     */
    private fun applyExpandedLargeIcon(builder: Notification.Builder) {
        when (miuiIslandExpandedIconMode) {
            "hidden" -> return
            "custom_image" -> {
                val path = miuiIslandExpandedIconPath ?: return
                decodeExpandedIconBitmap(path)?.let(builder::setLargeIcon)
            }
            else -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    builder.setLargeIcon(Icon.createWithResource(this, R.mipmap.ic_launcher))
                }
            }
        }
    }

    private fun buildRoundedLauncherIcon(targetSizePx: Int, cornerRadiusPx: Float): Icon? {
        val size = targetSizePx.coerceAtLeast(1)
        return try {
            val drawable = packageManager.getApplicationIcon(packageName)
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val clipPath = Path().apply {
                addRoundRect(
                    RectF(0f, 0f, size.toFloat(), size.toFloat()),
                    cornerRadiusPx,
                    cornerRadiusPx,
                    Path.Direction.CW
                )
            }
            canvas.save()
            canvas.clipPath(clipPath)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            canvas.restore()
            Icon.createWithBitmap(bitmap)
        } catch (e: Exception) {
            Log.w(TAG, DiagnosticLogMessages.LOG_BUILD_ROUNDED_LAUNCHER_ICON_FAILED, e)
            null
        }
    }

    private fun buildNotification(remainingText: String): Notification {
        val now = System.currentTimeMillis()
        val stage = resolveStage(now)
        // 常驻：会话不成立时落到情侣卡片形态。判在这里而不只判在 ticker 里，是因为
        // onStartCommand 带着负载启动时也直接调本方法，那条路径必须得到同一个结论
        // —— 例如课前提醒被关掉时，调度器仍可能把一个 beforeClass 负载送进来。
        if (stage == null && permanentNotification) {
            enterIdleMode()
            return buildIdleNotification(liveIdleContent(now))
        }
        // 会话形态：清掉空闲标记。这样会话结束后重新进空闲时 enterIdleMode 会重置
        // 签名，第一帧必定重绘 —— 否则签名与上一帧空闲内容相同就会跳过 notify，
        // 屏幕上留着的是那个已经过期的课程会话形态。
        idleMode = false
        val isUpcoming = stage == "beforeClass"
        val isDuringClassStatusBar = stage == "duringClassStatusBar"
        val isDuringClass = stage == "duringClass" || isDuringClassStatusBar
        // 只有上课前上岛；课中与临近下课改走普通通知。见 liveShouldPromoteStage。
        val shouldPromote = liveShouldPromoteStage(stage)
        val showStandardNotification = when {
            isDuringClassStatusBar -> true
            isDuringClass -> showNotificationDuringClass
            else -> true
        }
        val classProgress = if (stage == "duringClass") buildDuringClassProgress(now) else null
        val usesProgressExpandedStyle = Build.VERSION.SDK_INT >= 36 && classProgress != null

        val shortCourseName = if (courseName.length > 8) courseName.substring(0, 8) + ".." else courseName
        val nameToUse = if (useShortNameInIsland && shortCourseNameRaw.isNotBlank()) shortCourseNameRaw else courseName
        // 【岛专用】只喂胶囊/岛，绝不进下拉通知。两个面用各自独立的变量是刻意的：
        // 关掉「岛上显示地点」不该让下拉通知里的地点一起消失（见下方下拉各面的字段）。
        val islandCourseName = if (showCourseNameInIsland) {
            if (nameToUse.length > 5) nameToUse.substring(0, 5) else nameToUse
        } else ""
        val islandLocation = if (showLocationInIsland) location else ""
        val miuiIslandLabelText = when (miuiIslandLabelContent) {
            "location" -> location
            "course_name_and_location" -> listOf(
                nameToUse.takeIf { it.isNotBlank() },
                location.takeIf { it.isNotBlank() }
            ).filterNotNull().joinToString(" ")
            else -> nameToUse
        }
        val miuiIslandLabelBitmap = resolveIslandLabelBitmap(miuiIslandLabelText)
        val surfaceBrand = liveSurfaceBrand(Build.MANUFACTURER, Build.BRAND)

        val stageTitle = when (stage) {
            "beforeClass" -> getString(R.string.stage_before_class)
            else -> getString(R.string.stage_in_class)
        }
        val visibleStatusText = when {
            !showCountdown && showStageText -> stageTitle
            !showCountdown -> ""
            else -> remainingText.ifBlank { stageTitle }
        }
        // 课前卡片第一行给「即将上课 + 倒计时」（倒计时是这一屏唯一随时间变化的东西，
        // 放第一行最醒目）；课名与地点下移到正文行 —— 见 buildPromotedDetailLines 的调用点。
        // 进入最后 5 秒时倒计时会变成「开始上课」，此时直接用它当标题，拼成
        // 「即将上课 开始上课」就重复了。
        val title = when (stage) {
            "beforeClass" -> if (liveShouldShowClassStartingPrompt(stage, now, startAtMillis)) {
                getString(R.string.island_class_starting)
            } else {
                listOf(getString(R.string.stage_before_class), visibleStatusText)
                    .filter { it.isNotBlank() }
                    .joinToString(" ")
            }
            else -> shortCourseName
        }
        val shortNameLabel = shortCourseNameRaw.takeIf { it.isNotBlank() && it != courseName }
        val timeRangeText = if (startTimeText.isNotBlank() || endTimeText.isNotBlank()) {
            "$startTimeText - $endTimeText".trim()
        } else {
            ""
        }
        val subText = if (isUpcoming) {
            listOf(
                timeRangeText.takeIf { it.isNotBlank() }?.let { getString(R.string.label_class_start_time, it) },
                location.takeIf { it.isNotBlank() }?.let { getString(R.string.label_location, it) }
            ).filterNotNull().joinToString("  ·  ")
        } else {
            ""
        }
        val summaryText = if ((isDuringClass) && classProgress != null && showCountdown) {
            listOf(
                classProgress.nextMilestoneDisplayText,
                classProgress.finalDismissDisplayText,
                location.takeIf { it.isNotBlank() }
            ).filterNotNull().joinToString(" · ")
        } else {
            listOf(
                location.takeIf { it.isNotBlank() },
                teacher.takeIf { it.isNotBlank() },
                visibleStatusText.takeIf { it.isNotBlank() }
            ).filterNotNull().joinToString(" · ")
        }

        val pendingIntent = buildAppLaunchPendingIntent()

        val detailStatusText = when {
            (isDuringClass) && classProgress != null && showCountdown -> null
            visibleStatusText.isNotBlank() && !shouldPromote -> visibleStatusText
            else -> null
        }

        val expandedDetailText = buildString {
            append(stageTitle)
            if (shortNameLabel != null) {
                append("\n").append(getString(R.string.detail_short_name, shortNameLabel))
            }
            if ((isDuringClass) && classProgress != null && showCountdown) {
                if (classProgress.nextMilestoneDisplayText != null) {
                    append("\n").append(
                        getString(R.string.detail_next_milestone, classProgress.nextMilestoneDisplayText)
                    )
                }
                append("\n").append(
                    getString(R.string.detail_final_dismiss, classProgress.finalDismissDisplayText)
                )
            } else if (detailStatusText != null) {
                append("\n").append(getString(R.string.detail_status, detailStatusText))
            }
            if (timeRangeText.isNotBlank()) append("\n").append(getString(R.string.detail_time, timeRangeText))
            if (location.isNotBlank()) append("\n").append(getString(R.string.label_location, location))
            if (teacher.isNotBlank()) append("\n").append(getString(R.string.detail_teacher, teacher))
            if (nextName.isNotBlank()) append("\n").append(getString(R.string.detail_next_course, nextName))
            if (note.isNotBlank()) append("\n").append(getString(R.string.detail_note, note))
        }

        val promotedContentText = if ((isDuringClass) && classProgress != null && showCountdown) {
            listOf(
                classProgress.compactDisplayText,
                location.takeIf { it.isNotBlank() }
            ).filterNotNull().joinToString(" · ")
        } else {
            listOf(
                visibleStatusText.takeIf { it.isNotBlank() },
                timeRangeText.takeIf { it.isNotBlank() },
                location.takeIf { it.isNotBlank() },
                teacher.takeIf { it.isNotBlank() }
            ).filterNotNull().joinToString(" · ")
        }
        // 课前卡片正文两行：① 课程名　② 上课地点。第一行是标题里的「即将上课 + 倒计时」。
        //
        // 为什么不再是「时间:/地点:/教师:」逐行表单：卡片正文只渲染两行，那些条目会被
        // 挤到第三四行、写了也看不到；而且每行带标签会在系统约 17 字的截断额度上白费字符。
        // 时间区间与教师因此不上卡片（仍保留在通知栏正文与摘要里）。
        //
        // 两行都先过 truncateIslandLine：超长课名交给系统截会在行尾补「…」，且截点由系统
        // 决定，自己先截能保证关键内容（课名开头、地点）留在可见范围内。
        val promotedExpandedDetailText = buildPromotedDetailLines(
            duringClassLines = if ((isDuringClass) && classProgress != null && showCountdown) {
                listOfNotNull(
                    classProgress.nextMilestoneDisplayText?.let {
                        getString(R.string.detail_next_milestone, it)
                    },
                    getString(R.string.detail_final_dismiss, classProgress.finalDismissDisplayText),
                )
            } else {
                null
            },
            beforeClassLines = listOf(
                truncateIslandLine(courseName),
                truncateIslandLine(location),
            ),
        ).joinToString("\n")

        // 普通通知（非提升态）的正文。下拉通知是「全部显示」的那一面：
        // 课名、地点、教师、状态都进正文，且一律读完整字段 —— 不受岛开关
        // （showCourseNameInIsland / showLocationInIsland）影响，也不受胶囊影响。
        val contentText = if (!showStandardNotification) {
            ""
        } else if ((isDuringClass) && classProgress != null) {
            promotedContentText
        } else {
            listOf(courseName, location, teacher, visibleStatusText)
                .filter { it.isNotBlank() }
                .joinToString(" · ")
        }
            
        val miuiFocusHintText = if (
            liveShouldMirrorStatusIntoMiuiFocusHint(
                sdkInt = Build.VERSION.SDK_INT,
                shouldPromote = shouldPromote,
            )
        ) {
            visibleStatusText
        } else {
            ""
        }

        val miuiFocusParam = if (!shouldPromote || isDuringClassStatusBar) {
            null
        } else {
            buildMiuiFocusParam(
                title = title,
                remainingText = miuiFocusHintText,
                timeRangeText = timeRangeText,
                bodyContent = promotedContentText,
                visibleLocation = islandLocation,
                stage = stage,
                classProgress = classProgress,
                startAtMillis = startAtMillis,
                endAtMillis = endAtMillis,
                islandName = nameToUse,
                progressBreakOffsetsMillis = progressBreakOffsetsMillis,
                progressMilestoneLabels = progressMilestoneLabels,
                progressMilestoneTimeTexts = progressMilestoneTimeTexts,
            )
        }

        val islandCriticalStatusText = if ((isDuringClass) && classProgress != null && showCountdown) {
            classProgress.criticalTimeText
        } else {
            visibleStatusText
        }

        // 胶囊和下拉是两个互不干扰的面，各自只读自己那一组变量：
        //
        // * ColorOS（流体云）—— 胶囊固定只有「上课前」这一档：到上课的分钟数，
        //   最后 5 秒换成「开始上课」。课名、地点、教师、时间区间一概不上胶囊，
        //   只进下拉通知。所以这一支**完全不读** islandCourseName / islandLocation
        //   / islandCriticalStatusText，修改下拉的内容也不会影响胶囊。
        // * 其它品牌 —— 维持原有行为：胶囊由岛开关（showCourseNameInIsland /
        //   showLocationInIsland）决定要不要带课名与地点。这条规则不随 ColorOS 变。
        val islandCriticalText = when {
            surfaceBrand == LiveSurfaceBrand.COLOROS -> buildColorosIslandText(stage, now)
            shouldPromote && !showCourseNameInIsland && !showLocationInIsland ->
                islandCriticalStatusText
            else ->
                listOf(islandCourseName, islandLocation, islandCriticalStatusText)
                    .filter { it.isNotBlank() }
                    .joinToString(" ")
        }

        val iconRes = when (stage) {
            "beforeClass" -> R.drawable.ic_upcoming
            else -> R.drawable.ic_course
        }
        // 提升态请求，外加上一处【实验】的 OPPO 私有图标字段；三个分支共用同一份。
        val promotionExtras = Bundle().apply {
            if (shouldPromote && !isDuringClassStatusBar) {
                putBoolean(EXTRA_REQUEST_PROMOTED_ONGOING, true)
            }
            putOplusIslandIcon(this@LiveUpdateService, iconRes)
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }

        val notificationTitle = if (shouldPromote || showStandardNotification) {
            title
        } else {
            ""
        }
        val notificationContentText = if (shouldPromote) {
            promotedContentText
        } else if (!showStandardNotification) {
            ""
        } else {
            contentText
        }
        val notificationExpandedText = if (shouldPromote) {
            promotedExpandedDetailText
        } else if (!showStandardNotification) {
            ""
        } else {
            expandedDetailText
        }

        builder.apply {
            setContentTitle(notificationTitle)
            setContentText(notificationContentText)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && miuiIslandLabelBitmap != null) {
                setSmallIcon(Icon.createWithBitmap(miuiIslandLabelBitmap))
            } else {
                setSmallIcon(iconRes)
            }
            applyExpandedLargeIcon(this)
            setContentIntent(pendingIntent)
            setOngoing(true)
            setAutoCancel(false)
            setOnlyAlertOnce(true)
            setCategory(
                if (isDuringClassStatusBar) {
                    Notification.CATEGORY_REMINDER
                } else {
                    Notification.CATEGORY_PROGRESS
                }
            )
            // 恒为 false：ColorOS 上置 true 会让通知失去提升资格，
            // 详见 LiveUpdatePromotionGate 里的实机回归记录。
            setColorized(liveShouldRequestColorizedForPromotion(shouldPromote))
            setShowWhen(!shouldPromote)
            setWhen(if (isUpcoming) startAtMillis else endAtMillis)
            setUsesChronometer(false)
            if (usesProgressExpandedStyle) {
                val progress = requireNotNull(classProgress)
                setProgress(progress.progressMax, progress.progressUnits, false)
            } else {
                setProgress(0, 0, false)
            }

            if (showStandardNotification && !shouldPromote && subText.isNotBlank()) {
                setSubText(subText)
            }

            if (Build.VERSION.SDK_INT >= 36) {
                if (isDuringClassStatusBar) {
                    setShortCriticalText("")
                    setExtras(promotionExtras)
                } else if (shouldPromote) {
                    setShortCriticalText(islandCriticalText)
                    setExtras(promotionExtras)
                } else {
                    setShortCriticalText("")
                    setExtras(promotionExtras)
                }
            }
        }

        if (isUpcoming) {
            buildBeforeClassQuickActions().forEach(builder::addAction)
        }
        if (isDuringClassStatusBar) {
            builder.addAction(buildDismissStatusBarAction())
        }

        if (usesProgressExpandedStyle) {
            val progress = requireNotNull(classProgress)
            builder.setStyle(
                Notification.ProgressStyle()
                    .setStyledByProgress(true)
                    .setProgress(progress.progressUnits)
                    .setProgressSegments(
                        listOf(
                            Notification.ProgressStyle.Segment(
                                progress.progressMax
                            )
                        )
                    )
                    .setProgressTrackerIcon(
                        buildRoundedLauncherIcon(dp(28f).toInt(), dp(9f))
                            ?: Icon.createWithResource(this, R.mipmap.ic_launcher)
                    )
                    .setProgressPoints(
                        progress.breakPointUnits.map { point ->
                            Notification.ProgressStyle.Point(point)
                        }
                    )
            )
        } else {
            builder.setStyle(
                Notification.BigTextStyle()
                    .setBigContentTitle(notificationTitle)
                    .bigText(notificationExpandedText)
                    .setSummaryText(if (showStandardNotification) summaryText else "")
            )
        }

        val notification = builder.build()
        miuiFocusParam?.let { notification.extras.putString("miui.focus.param", it) }

        val canPostPromoted = if (Build.VERSION.SDK_INT >= 36) {
            getSystemService(NotificationManager::class.java)?.canPostPromotedNotifications() == true
        } else {
            false
        }
        val hasPromotableCharacteristics = if (Build.VERSION.SDK_INT >= 36) {
            notification.hasPromotableCharacteristics()
        } else {
            null
        }
        val isMiuiFocusIslandReady =
            isXiaomiFamilyDevice() &&
                miuiFocusParam != null &&
                shouldPromote &&
                !isDuringClassStatusBar
        // 应用级或渠道级通知任一被关时 notify() 都会被系统静默丢弃，
        // 必须先于两条就绪路径拦截，否则自检页会误报「已满足上岛条件」而实际无法上岛。
        val notificationsAllowed = areNotificationsEnabledCompat(this)
        val liveChannelEnabled = isLiveUpdateChannelEnabledCompat(this)
        val isActuallyPromotable = when {
            isDuringClassStatusBar || !shouldPromote -> false
            !notificationsAllowed || !liveChannelEnabled -> false
            Build.VERSION.SDK_INT >= 36 &&
                canPostPromoted &&
                hasPromotableCharacteristics == true -> true
            isMiuiFocusIslandReady -> true
            else -> false
        }
        // 平台能力类原因在 OPPO / realme / 一加上改用「流体云」措辞：ColorOS 16 完整
        // 接入了 Android 16 的标准提升通知通道，这些文案最该把他们引导到正确开关上。
        fun surfaceReason(colorosResId: Int, genericResId: Int): String = getString(
            if (surfaceBrand == LiveSurfaceBrand.COLOROS) colorosResId else genericResId,
        )

        val notIslandReason = when {
            !hasStartedForeground -> getString(R.string.debug_foreground_not_started)
            stage == null -> getString(R.string.debug_stage_not_displayable)
            isDuringClassStatusBar -> getString(R.string.debug_status_bar_only)
            !shouldPromote && isDuringClass && !promoteDuringClass ->
                getString(R.string.debug_during_class_normal_notification)
            !shouldPromote -> getString(R.string.debug_promote_not_requested)
            !notificationsAllowed -> getString(R.string.debug_notification_permission_off)
            !liveChannelEnabled -> getString(R.string.debug_notification_channel_disabled)
            isActuallyPromotable -> ""
            Build.VERSION.SDK_INT >= 36 && !isPromotedPermissionDeclaredCompat(this) ->
                getString(R.string.debug_promoted_permission_not_declared)
            Build.VERSION.SDK_INT >= 36 && !canPostPromoted && !isMiuiFocusIslandReady ->
                surfaceReason(
                    R.string.debug_system_denied_promoted_coloros,
                    R.string.debug_system_denied_promoted,
                )
            Build.VERSION.SDK_INT >= 36 && hasPromotableCharacteristics == false && !isMiuiFocusIslandReady ->
                surfaceReason(
                    R.string.debug_notification_not_promotable_coloros,
                    R.string.debug_notification_not_promotable,
                )
            isXiaomiFamilyDevice() && miuiFocusParam == null ->
                getString(R.string.debug_miui_focus_param_missing)
            Build.VERSION.SDK_INT < 36 && !isXiaomiFamilyDevice() ->
                surfaceReason(
                    R.string.debug_os_not_supported_coloros,
                    R.string.debug_os_not_supported,
                )
            else -> getString(R.string.debug_try_return_home)
        }

        updateDebugSnapshot(
            linkedMapOf(
                "summary" to linkedMapOf(
                    "serviceRunning" to true,
                    "currentStage" to activityStage,
                    "resolvedStage" to stage,
                    "isExpectedToShowIsland" to shouldPromote,
                    "isActuallyPromotable" to isActuallyPromotable,
                    "statusText" to if (isActuallyPromotable) {
                        getString(R.string.debug_island_ready)
                    } else {
                        getString(R.string.debug_island_not_ready)
                    },
                    "notIslandReason" to notIslandReason,
                ),
                "service" to linkedMapOf(
                    "serviceRunning" to true,
                    "hasStartedForeground" to hasStartedForeground,
                    "activityStage" to activityStage,
                    "resolvedStage" to stage,
                    "lastRemainingText" to remainingText,
                    "lastProgressUnits" to lastProgressUnits,
                    "lastCriticalTimeText" to lastCriticalTimeText,
                ),
                "course" to linkedMapOf(
                    "courseName" to courseName,
                    "shortCourseNameRaw" to shortCourseNameRaw,
                    "nextCourseName" to nextName,
                    "location" to location,
                    "teacher" to teacher,
                    "note" to note,
                    "startTimeText" to startTimeText,
                    "endTimeText" to endTimeText,
                ),
                "timing" to linkedMapOf(
                    "nowMillis" to now,
                    "startAtMillis" to startAtMillis,
                    "endAtMillis" to endAtMillis,
                    "remainingToStartMillis" to (startAtMillis - now).coerceAtLeast(0L),
                    "remainingToEndMillis" to (endAtMillis - now).coerceAtLeast(0L),
                    "liveClassReminderStartMinutes" to liveClassReminderStartMinutes,
                    "autoDismissAfterStartMinutes" to autoDismissAfterStartMinutes,
                ),
                "switches" to linkedMapOf(
                    "enableBeforeClass" to enableBeforeClass,
                    "enableDuringClass" to enableDuringClass,
                    "promoteDuringClass" to promoteDuringClass,
                    "showNotificationDuringClass" to showNotificationDuringClass,
                ),
                "display" to linkedMapOf(
                    "showCountdown" to showCountdown,
                    "countdownTextStyle" to countdownTextStyle,
                    "showStageText" to showStageText,
                    "showCourseNameInIsland" to showCourseNameInIsland,
                    "showLocationInIsland" to showLocationInIsland,
                    "useShortNameInIsland" to useShortNameInIsland,
                    "hidePrefixText" to hidePrefixText,
                    "duringClassTimeDisplayMode" to duringClassTimeDisplayMode,
                    "enableMiuiIslandLabelImage" to enableMiuiIslandLabelImage,
                    "miuiIslandLabelStyle" to miuiIslandLabelStyle,
                    "miuiIslandLabelContent" to miuiIslandLabelContent,
                    "miuiIslandLabelFontColor" to miuiIslandLabelFontColor,
                    "miuiIslandLabelFontWeight" to miuiIslandLabelFontWeight,
                    "miuiIslandLabelRenderQuality" to miuiIslandLabelRenderQuality,
                    "miuiIslandLabelFontSize" to miuiIslandLabelFontSize,
                    "miuiIslandLabelOffsetX" to miuiIslandLabelOffsetX,
                    "miuiIslandLabelOffsetY" to miuiIslandLabelOffsetY,
                    "miuiIslandLabelLogoPath" to miuiIslandLabelLogoPath,
                    "miuiIslandLabelLogoCornerRadius" to miuiIslandLabelLogoCornerRadius,
                    "miuiIslandExpandedIconMode" to miuiIslandExpandedIconMode,
                    "miuiIslandExpandedIconPath" to miuiIslandExpandedIconPath,
                    "beforeClassQuickAction" to beforeClassQuickAction,
                    "quickActionAutoLeadMillis" to quickActionAutoLeadMillis,
                ),
                "notification" to linkedMapOf(
                    "shouldPromote" to shouldPromote,
                    "showStandardNotification" to showStandardNotification,
                    "isDuringClassStatusBar" to isDuringClassStatusBar,
                    "notificationsAllowed" to notificationsAllowed,
                    "liveUpdateChannelEnabled" to liveChannelEnabled,
                    "canPostPromotedNotifications" to canPostPromoted,
                    "hasPromotableCharacteristics" to hasPromotableCharacteristics,
                    "miuiFocusParamPresent" to (miuiFocusParam != null),
                    "notificationTitle" to notificationTitle,
                    "notificationContentText" to notificationContentText,
                    "notificationExpandedText" to notificationExpandedText,
                    "visibleStatusText" to visibleStatusText,
                    "islandCriticalText" to islandCriticalText,
                    "promotedContentText" to promotedContentText,
                ),
            )
        )

        if (Build.VERSION.SDK_INT >= 36) {
            if (shouldPromote && (hasPromotableCharacteristics != true || !canPostPromoted)) {
                UmengDiagnosticReporter.record(
                    context = applicationContext,
                    category = "live_update_not_promoted",
                    message = DiagnosticLogMessages.LIVE_UPDATE_NOT_PROMOTED,
                    extras = mapOf(
                        "courseName" to courseName,
                        "stage" to stage,
                        "canPostPromoted" to canPostPromoted,
                        "hasPromotableCharacteristics" to hasPromotableCharacteristics,
                        "notificationsAllowed" to notificationsAllowed,
                        "liveChannelEnabled" to liveChannelEnabled,
                        "miuiIslandExpandedIconMode" to miuiIslandExpandedIconMode,
                    )
                )
                UmengDiagnosticReporter.report(
                    context = applicationContext,
                    category = "live_update_promoted_not_shown",
                    message = DiagnosticLogMessages.LIVE_UPDATE_PROMOTED_NOT_SHOWN,
                    dedupeKey = "live_update_promoted_not_shown:${courseName}:${activityStage}",
                    extras = mapOf(
                        "courseName" to courseName,
                        "stage" to stage,
                        "canPostPromoted" to canPostPromoted,
                        "hasPromotableCharacteristics" to hasPromotableCharacteristics,
                        "notificationsAllowed" to notificationsAllowed,
                        "liveChannelEnabled" to liveChannelEnabled,
                        "showStandardNotification" to showStandardNotification,
                        "remainingText" to remainingText,
                        "miuiIslandExpandedIconMode" to miuiIslandExpandedIconMode,
                    )
                )
            }
        }

        return notification
    }

    private fun sanitizeTextExtra(value: String?): String {
        val normalized = value?.trim().orEmpty()
        return if (normalized.equals("null", ignoreCase = true)) "" else normalized
    }

    private fun stopAndRemoveNotification() {
        restoreBeforeClassQuickActionIfClassEnded()
        markServiceStopped(getString(R.string.stop_reminder_ended))
        UmengDiagnosticReporter.record(
            context = applicationContext,
            category = "live_update_service_stopped",
            message = DiagnosticLogMessages.LIVE_UPDATE_SERVICE_STOPPED,
            extras = mapOf(
                "courseName" to courseName,
                "stage" to activityStage,
            )
        )
        stopTicker()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        LiveUpdateScheduler.onLiveUpdateStopped(applicationContext)
        stopSelf()
    }

    private fun buildCourseTimeMillis(timeText: String): Long? {
        val parts = timeText.split(":")
        if (parts.size != 2) {
            return null
        }

        val hour = parts[0].toIntOrNull() ?: return null
        val minute = parts[1].toIntOrNull() ?: return null

        return Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
    }

    private fun formatCountdownDuration(
        durationMillis: Long,
        secondsThresholdMillis: Long = 60_000L,
    ): String = CountdownFormat.formatDuration(durationMillis, countdownTextStyle, secondsThresholdMillis)

    private data class DuringClassProgress(
        val progressMax: Int,
        val progressUnits: Int,
        val progressPercent: Int,
        val nextMilestoneDisplayText: String?,
        val finalDismissDisplayText: String,
        val compactDisplayText: String,
        val criticalTimeText: String,
        val breakPointUnits: List<Int>,
        val updatesEverySecond: Boolean,
    )

    private fun buildDuringClassProgress(now: Long): DuringClassProgress? {
        val totalMillis = (endAtMillis - startAtMillis).coerceAtLeast(1L)
        val elapsedMillis = (now - startAtMillis).coerceIn(0L, totalMillis)
        val remainingMillis = (endAtMillis - now).coerceAtLeast(0L)
        val progressMax = 1000
        val progressUnits =
            ((elapsedMillis.toDouble() / totalMillis.toDouble()) * progressMax)
                .toInt()
                .coerceIn(0, progressMax)
        val progressPercent = ((progressUnits * 100L) / progressMax).toInt().coerceIn(0, 100)
        val breakPointUnits = progressBreakOffsetsMillis
            .map { offsetMillis ->
                ((offsetMillis.coerceIn(0L, totalMillis).toDouble() / totalMillis.toDouble()) * progressMax)
                    .toInt()
                    .coerceIn(1, progressMax - 1)
            }
            .distinct()
            .sorted()
        val nextMilestoneIndex =
            progressBreakOffsetsMillis.indexOfFirst { it > elapsedMillis }.takeIf { it >= 0 }
        val nextMilestoneLabel =
            nextMilestoneIndex?.let { progressMilestoneLabels.getOrNull(it)?.takeIf { label -> label.isNotBlank() } }
        val nextMilestoneRemainingText =
            nextMilestoneIndex?.let { formatCountdownDuration(progressBreakOffsetsMillis[it] - elapsedMillis) }
        val finalDismissRemainingText = formatCountdownDuration(remainingMillis)
        val nextMilestoneDisplayText =
            if (nextMilestoneLabel != null && nextMilestoneRemainingText != null) {
                "$nextMilestoneLabel $nextMilestoneRemainingText"
            } else if (nextMilestoneRemainingText != null) {
                nextMilestoneRemainingText
            } else {
                null
            }
        val finalDismissDisplayText = getString(R.string.final_dismiss_with_time, finalDismissRemainingText)
        val compactDisplayText = if (duringClassTimeDisplayMode == "total") {
            finalDismissDisplayText
        } else {
            nextMilestoneDisplayText ?: finalDismissDisplayText
        }
        val criticalTimeText = if (duringClassTimeDisplayMode == "total") {
            finalDismissRemainingText
        } else {
            nextMilestoneRemainingText ?: finalDismissRemainingText
        }
        return DuringClassProgress(
            progressMax = progressMax,
            progressUnits = progressUnits,
            progressPercent = progressPercent,
            nextMilestoneDisplayText = nextMilestoneDisplayText,
            finalDismissDisplayText = finalDismissDisplayText,
            compactDisplayText = compactDisplayText,
            criticalTimeText = criticalTimeText,
            breakPointUnits = breakPointUnits,
            updatesEverySecond = shouldRefreshEverySecond(
                durationMillis = nextMilestoneIndex?.let { progressBreakOffsetsMillis[it] - elapsedMillis }
                    ?: remainingMillis,
                secondsThresholdMillis = 60_000L,
            ),
        )
    }

    private fun shouldRefreshEverySecond(
        durationMillis: Long,
        secondsThresholdMillis: Long,
    ): Boolean {
        if (!showCountdown) {
            return false
        }
        return when (countdownTextStyle) {
            "minute_second_cn",
            "minute_second_colon",
            "minute_second_min_s",
            "minute_second_min_slash_s",
            "second_only_cn",
            "second_only_short",
            "second_only_slash" -> true
            "smart",
            "smart_min_s" -> durationMillis <= secondsThresholdMillis
            else -> false
        }
    }

    private fun nextCountdownTextChangeDelayMillis(
        durationMillis: Long,
        secondsThresholdMillis: Long,
    ): Long {
        if (!showCountdown) {
            return 60_000L
        }
        val safeDurationMillis = durationMillis.coerceAtLeast(0L)
        val totalSeconds = (safeDurationMillis / 1000L).coerceAtLeast(0L)
        return when (countdownTextStyle) {
            "minute_second_cn",
            "minute_second_colon",
            "minute_second_min_s",
            "minute_second_min_slash_s",
            "second_only_cn",
            "second_only_short",
            "second_only_slash" -> 1_000L
            "minute_only_cn",
            "minute_only_min",
            "minute_only_slash" -> {
                val currentMinutes = (totalSeconds / 60L).coerceAtLeast(1L)
                if (currentMinutes <= 1L) {
                    safeDurationMillis.coerceAtLeast(1_000L)
                } else {
                    (safeDurationMillis - currentMinutes * 60_000L + 1L).coerceAtLeast(1_000L)
                }
            }
            else -> {
                when {
                    safeDurationMillis <= secondsThresholdMillis -> 1_000L
                    totalSeconds > 120L -> {
                        val currentMinutes = (totalSeconds / 60L).coerceAtLeast(1L)
                        (safeDurationMillis - currentMinutes * 60_000L + 1L).coerceAtLeast(1_000L)
                    }
                    totalSeconds > 60L -> {
                        (safeDurationMillis - secondsThresholdMillis + 1L).coerceAtLeast(1_000L)
                    }
                    else -> 1_000L
                }
            }
        }
    }

    private fun computeNextTickDelayMillis(
        now: Long,
        stage: String?,
        duringClassProgress: DuringClassProgress?,
    ): Long {
        val refreshEverySecond = when (stage) {
            "beforeClass" -> shouldRefreshEverySecond(
                durationMillis = (startAtMillis - now).coerceAtLeast(0L),
                secondsThresholdMillis = 60_000L,
            )
            "duringClass" -> duringClassProgress?.updatesEverySecond == true
            else -> false
        }
        if (refreshEverySecond) {
            return 1000L
        }
        val stageDelay = when (stage) {
            "beforeClass" -> {
                val remainingMillis = (startAtMillis - now).coerceAtLeast(0L)
                listOfNotNull(
                    remainingMillis.coerceAtLeast(1_000L),
                    nextCountdownTextChangeDelayMillis(
                        durationMillis = remainingMillis,
                        secondsThresholdMillis = 60_000L,
                    ),
                    // 必须有一次 tick 落在「开始上课」窗口开启处：课前文案按分钟
                    // 跳，否则这 5 秒会被整段跳过。
                    (remainingMillis - CLASS_STARTING_PROMPT_WINDOW_MILLIS)
                        .takeIf { it > 0L },
                ).minOrNull() ?: 60_000L
            }
            "duringClass" -> {
                val elapsedMillis = (now - startAtMillis).coerceAtLeast(0L)
                val nextMilestoneDelay = progressBreakOffsetsMillis
                    .firstOrNull { it > elapsedMillis }
                    ?.minus(elapsedMillis)
                listOfNotNull(
                    nextMilestoneDelay?.takeIf { it > 0L },
                    (endAtMillis - now).takeIf { it > 0L },
                    nextCountdownTextChangeDelayMillis(
                        durationMillis = nextMilestoneDelay ?: (endAtMillis - now).coerceAtLeast(0L),
                        secondsThresholdMillis = 60_000L,
                    ),
                ).minOrNull() ?: 60_000L
            }
            "duringClassStatusBar" -> {
                // 到重点提醒起点就切课中，必须在那一点落一次 tick。
                val duringClassStartMillis = maxOf(
                    startAtMillis,
                    endAtMillis - liveClassReminderStartMinutes * 60_000L,
                )
                listOfNotNull(
                    (duringClassStartMillis - now).takeIf { it > 0L },
                    (endAtMillis - now).takeIf { it > 0L },
                ).minOrNull() ?: 60_000L
            }
            else -> 60_000L
        }
        return stageDelay.coerceIn(1_000L, 60_000L)
    }
}

/**
 * 按显示宽度硬截断，**不加省略号**。
 *
 * 流体云卡片正文每行约 17 个半角单位就会被系统截断并补上「…」，而截点由系统决定
 * （实测与卡片剩余宽度无关：截断点右侧仍留着一大截空白）。我们自己先截到 [maxUnits]
 * 以内，既让关键内容留在前面，也避免行尾出现系统补的省略号。
 *
 * 宽度按「汉字/全角记 2、其余记 1」粗略估算 —— 系统给的是像素额度，这里用等宽近似。
 */
internal fun truncateIslandLine(text: String, maxUnits: Int = 16): String {
    var units = 0
    val kept = StringBuilder()
    for (ch in text) {
        val width = if (ch.code > 0x2E80) 2 else 1
        if (units + width > maxUnits) break
        units += width
        kept.append(ch)
    }
    return kept.toString()
}

/**
 * 组装提升态（流体云）展开卡片的详情行，返回行列表，由调用方用 `"\n"` 拼接。
 *
 * 逐行收集而非「先判空再 `append("\n")`」：后者在首段为空时会拼出一个**前导空行**，
 * 那一行会被卡片吃掉，正文只剩被截断的第二行（实机曾表现为「时间: 19:13 - 19:1...」）。
 *
 * @param duringClassLines 课中进度行；非 null 时取代 [beforeClassLines] 作为开头
 * @param beforeClassLines 课前的内容行（课程名、上课地点，调用方已用
 *   [truncateIslandLine] 硬截断）；空白项自动跳过，避免产生空行
 */
internal fun buildPromotedDetailLines(
    duringClassLines: List<String>?,
    beforeClassLines: List<String>,
): List<String> = buildList {
    if (duringClassLines != null) {
        addAll(duringClassLines)
    } else {
        beforeClassLines.forEach { line ->
            line.takeIf { it.isNotBlank() }?.let { add(it) }
        }
    }
}

/** 课前倒计时最后 5 秒改显示「开始上课」的窗口。 */
internal const val CLASS_STARTING_PROMPT_WINDOW_MILLIS = 5_000L

/**
 * 是否处于「开始上课」提示窗口：课前阶段的最后 5 秒。
 *
 * 这段时间用 [R.string.island_class_starting] 顶掉倒计时，作为上课信号。
 * 课中与下课提醒不再上岛（见 [liveShouldPromoteStage]），所以这个信号放在
 * 唯一会上岛的课前阶段末尾。
 *
 * 这个判据同时要驱动 tick 落点：课前文案按分钟跳，若不在窗口开启处补一次
 * tick，这 5 秒会被整段跳过（见 `LiveUpdateService.computeNextTickDelayMillis`）。
 */
internal fun liveShouldShowClassStartingPrompt(
    stage: String?,
    nowMillis: Long,
    startAtMillis: Long,
): Boolean {
    if (stage != "beforeClass") {
        return false
    }
    val remainingMillis = startAtMillis - nowMillis
    return remainingMillis in 0..CLASS_STARTING_PROMPT_WINDOW_MILLIS
}
