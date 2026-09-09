package vip.qinghan.withu

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

object HomeWidgetStorage {
    private const val PREFS_NAME = "home_widget_prefs"
    private const val KEY_SNAPSHOT_JSON = "snapshot_json"
    private const val KEY_REFRESH_TIMES_JSON = "refresh_times_json"
    private const val KEY_WIDGET_SNAPSHOT_PREFIX = "widget_snapshot_"
    private const val REQUEST_CODE_REFRESH = 4201
    private const val REQUEST_CODE_COUPLE_REFRESH = 4202

    fun syncSnapshot(context: Context, snapshot: Map<String, Any?>) {
        val payload = JSONObject(snapshot).toString()
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_SNAPSHOT_JSON, payload)
            .apply()
        TodayWidgetSupport.updateAll(context)
        rescheduleRefresh(context)
        // WorkManager backup: ensures widget refresh even when
        // AlarmManager is suppressed by the ROM (e.g. MIUI/HyperOS).
        WidgetRefreshWorker.ensureScheduled(context)
    }

    fun clearSnapshot(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_SNAPSHOT_JSON)
            .remove(KEY_REFRESH_TIMES_JSON)
            .apply()
        cancelFullRefreshAlarm(context)
        cancelCoupleRefreshAlarm(context)
        WidgetRefreshWorker.cancel(context)
        TodayWidgetSupport.updateAll(context)
    }

    fun scheduleRefresh(context: Context, triggerAtMillis: List<Long>) {
        val payload = JSONArray(triggerAtMillis).toString()
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_REFRESH_TIMES_JSON, payload)
            .apply()
        rescheduleRefresh(context)
    }

    fun getSnapshotJson(context: Context): String? {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_SNAPSHOT_JSON, null)
    }

    /**
     * 按 appWidgetId 存一张绑定卡片的专属快照（Flutter 为绑定课表单独生成）。
     * 未绑定的卡片不写这份，渲染继续走全局快照/实时计算。
     */
    fun syncWidgetSnapshot(context: Context, appWidgetId: Int, snapshot: Map<String, Any?>) {
        val payload = JSONObject(snapshot).toString()
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(widgetSnapshotKey(appWidgetId), payload)
            .apply()
        TodayWidgetSupport.updateAll(context)
        rescheduleRefresh(context)
    }

    fun getWidgetSnapshotJson(context: Context, appWidgetId: Int): String? {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(widgetSnapshotKey(appWidgetId), null)
    }

    /** 绑定被移除或绑定的课表已消失时，清掉该卡片的专属快照。 */
    fun clearWidgetSnapshot(context: Context, appWidgetId: Int) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(widgetSnapshotKey(appWidgetId))
            .apply()
        TodayWidgetSupport.updateAll(context)
    }

    fun getRefreshTimesJson(context: Context): String? {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_REFRESH_TIMES_JSON, null)
    }

    fun rescheduleRefresh(context: Context) {
        // 桌面上没有任何卡片时，精确闹钟与 WorkManager 兜底都没有意义，全部停掉。
        // 避免装了应用却没加卡片的用户被空转唤醒。
        if (!TodayWidgetSupport.hasAnyWidget(context)) {
            cancelFullRefreshAlarm(context)
            cancelCoupleRefreshAlarm(context)
            WidgetRefreshWorker.cancel(context)
            return
        }
        val nowMillis = System.currentTimeMillis()
        scheduleFullRefresh(context, nowMillis)
        scheduleCoupleRefresh(context, nowMillis)
        WidgetRefreshWorker.ensureScheduled(context)
    }

    /**
     * 全量刷新：课程边界 / 绑定课表 / 倒计时 / 跨天，触发时重绘全部卡片。
     */
    private fun scheduleFullRefresh(context: Context, nowMillis: Long) {
        cancelFullRefreshAlarm(context)
        // 刷新点 = 当前课表 + 所有已绑定课表的并集：TA 第三节课开始时
        // 闹钟也必须响，不能只按当前课表的时间调度。
        val triggerAtMillis = buildList {
            add(TodayWidgetSupport.findNextRefreshAtMillis(context, nowMillis))
            for ((_, profileId) in WidgetBindingStore.allBindings(context)) {
                val profileJson =
                    TodayWidgetSupport.readProfileJsonById(context, profileId) ?: continue
                add(TodayWidgetSupport.findNextRefreshAtMillis(context, nowMillis, profileJson))
            }
        }
            .filterNotNull()
            .filter { it > nowMillis }
            .minOrNull()
            ?: loadRefreshTimes(context)
                .filter { it > nowMillis }
                .minOrNull()
            ?: return
        setAlarm(context, triggerAtMillis, buildFullRefreshPendingIntent(context))
    }

    /**
     * 情侣卡片专用刷新：当前课进度按分钟推进，但只重绘情侣卡片本身，
     * 不再像以前那样每分钟把所有卡片都全量重建一遍。
     */
    private fun scheduleCoupleRefresh(context: Context, nowMillis: Long) {
        cancelCoupleRefreshAlarm(context)
        if (!hasCoupleWidget(context)) return
        setAlarm(
            context,
            CoupleTimetableWidgetProvider.findNextRefreshAtMillis(nowMillis),
            buildCoupleRefreshPendingIntent(context),
        )
    }

    /** 情侣卡片 tick 只重排自己，避免每分钟重新解析全部绑定课表。 */
    fun scheduleCoupleRefreshOnly(context: Context) {
        scheduleCoupleRefresh(context, System.currentTimeMillis())
    }

    private fun setAlarm(context: Context, triggerAtMillis: Long, pendingIntent: PendingIntent) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            !alarmManager.canScheduleExactAlarms()
        ) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent,
            )
        } else {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                pendingIntent,
            )
        }
    }

    /** 桌面上是否存在情侣课表卡片（决定是否启用按分钟刷新的触发点）。 */
    private fun hasCoupleWidget(context: Context): Boolean {
        return AppWidgetManager.getInstance(context)
            .getAppWidgetIds(ComponentName(context, CoupleTimetableWidgetProvider::class.java))
            .isNotEmpty()
    }

    private fun cancelFullRefreshAlarm(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(buildFullRefreshPendingIntent(context))
    }

    private fun cancelCoupleRefreshAlarm(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(buildCoupleRefreshPendingIntent(context))
    }

    private fun buildFullRefreshPendingIntent(context: Context): PendingIntent {
        return buildRefreshPendingIntent(
            context,
            REQUEST_CODE_REFRESH,
            AppWidgetManager.ACTION_APPWIDGET_UPDATE,
        )
    }

    private fun buildCoupleRefreshPendingIntent(context: Context): PendingIntent {
        return buildRefreshPendingIntent(
            context,
            REQUEST_CODE_COUPLE_REFRESH,
            HomeWidgetRefreshReceiver.ACTION_COUPLE_REFRESH,
        )
    }

    private fun buildRefreshPendingIntent(
        context: Context,
        requestCode: Int,
        action: String,
    ): PendingIntent {
        val intent = Intent(context, HomeWidgetRefreshReceiver::class.java).apply {
            this.action = action
            component = ComponentName(context, HomeWidgetRefreshReceiver::class.java)
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun refreshSnapshotFromFlutterState(context: Context): Boolean {
        val snapshot = TodayWidgetSupport.buildSnapshotFromFlutterState(context) ?: return false
        val payload = JSONObject().apply {
            put("profileName", snapshot.profileName)
            put("currentWeek", snapshot.currentWeek)
            put("state", snapshot.state)
            put("backgroundStyle", snapshot.backgroundStyle)
            put("showLocation", snapshot.showLocation)
            put("showCountdown", snapshot.showCountdown)
            put("hideCompletedCourses", snapshot.hideCompletedCourses)
            put("heightAdjustment", snapshot.heightAdjustment)
            put("cornerRadius", snapshot.cornerRadius)
            put("totalTodayCourseCount", snapshot.totalTodayCourseCount)
            put("todayCourses", coursesToJson(snapshot.todayCourses))
            put("visibleTodayCourses", coursesToJson(snapshot.visibleTodayCourses))
            put("highlightedCourse", snapshot.highlightedCourse?.let(::courseToJson))
            put("nextCourse", snapshot.nextCourse?.let(::courseToJson))
        }.toString()
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_SNAPSHOT_JSON, payload)
            .apply()
        return true
    }

    private fun coursesToJson(courses: List<TodayWidgetCourseInfo>): JSONArray {
        return JSONArray().apply {
            courses.forEach { put(courseToJson(it)) }
        }
    }

    private fun courseToJson(course: TodayWidgetCourseInfo): JSONObject {
        return JSONObject().apply {
            put("id", course.id)
            put("name", course.name)
            put("shortName", course.shortName)
            put("location", course.location)
            put("startTime", course.startTime)
            put("endTime", course.endTime)
        }
    }

    private fun widgetSnapshotKey(appWidgetId: Int) = "$KEY_WIDGET_SNAPSHOT_PREFIX$appWidgetId"

    private fun loadRefreshTimes(context: Context): List<Long> {
        val payload = getRefreshTimesJson(context) ?: return emptyList()
        return try {
            val json = JSONArray(payload)
            buildList {
                for (index in 0 until json.length()) {
                    add(json.optLong(index))
                }
            }.filter { it > 0L }
        } catch (_: Exception) {
            emptyList()
        }
    }
}
