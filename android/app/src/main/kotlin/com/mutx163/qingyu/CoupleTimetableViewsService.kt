package com.mutx163.qingyu

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.Build
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import android.appwidget.AppWidgetManager
import androidx.core.content.ContextCompat
import androidx.core.content.res.ResourcesCompat
import android.text.TextUtils
import android.text.TextPaint
import kotlin.math.roundToInt
import java.util.Calendar

internal sealed class CoupleWidgetDisplayItem {
    data class Course(
        val course: CoupleWidgetCourse,
        val isOngoing: Boolean,
    ) : CoupleWidgetDisplayItem()

    data class Notice(val text: String) : CoupleWidgetDisplayItem()
    data object NoticeDivider : CoupleWidgetDisplayItem()
    data object Divider : CoupleWidgetDisplayItem()
}

internal data class CoupleWidgetDisplay(
    val items: List<CoupleWidgetDisplayItem>,
    val footerText: String,
    val emptyText: String? = null,
)

internal object CoupleTimetableDisplayBuilder {
    private const val MAX_VISIBLE_COURSES = 5
    private const val MAX_VISIBLE_COURSES_WITH_NOTICE = 5

    fun build(
        context: Context,
        courses: CoupleWidgetDayCourses,
        nowMillis: Long = System.currentTimeMillis(),
        status: CoupleWidgetStatus = CoupleWidgetStatus.OK,
        maxVisibleCourses: Int = MAX_VISIBLE_COURSES,
    ): CoupleWidgetDisplay {
        if (status != CoupleWidgetStatus.OK) {
            val text = when (status) {
                CoupleWidgetStatus.COUPLE_MODE_OFF ->
                    context.getString(R.string.widget_couple_mode_off)
                CoupleWidgetStatus.NOT_LOGGED_IN ->
                    context.getString(R.string.widget_couple_not_logged_in)
                CoupleWidgetStatus.OK -> ""
            }
            return CoupleWidgetDisplay(
                items = emptyList(),
                footerText = "",
                emptyText = text,
            )
        }

        val now = Calendar.getInstance().apply { timeInMillis = nowMillis }
        val today = courses.today.sortedWith(
            compareBy({ it.startTime }, { it.startSection }, { it.id })
        )
        val tomorrow = courses.tomorrow.sortedWith(
            compareBy({ it.startTime }, { it.startSection }, { it.id })
        )
        val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val hasRemainingCourse = today.any {
            parseClockMinutes(it.endTime)?.let { it > nowMinutes } == true
        }
        val remainingCount = today.count {
            parseClockMinutes(it.endTime)?.let { it > nowMinutes } == true
        }
        val statusText = when {
            today.isNotEmpty() -> context.getString(R.string.widget_couple_today_ended)
            now.get(Calendar.DAY_OF_WEEK) == Calendar.SATURDAY ||
                now.get(Calendar.DAY_OF_WEEK) == Calendar.SUNDAY ->
                context.getString(R.string.widget_couple_weekend_no_course)
            else -> context.getString(R.string.widget_couple_no_course_today)
        }

        val shownCourses = if (hasRemainingCourse) today else tomorrow
        val items = if (!hasRemainingCourse && tomorrow.isEmpty()) {
            emptyList()
        } else {
            buildList {
                if (!hasRemainingCourse) {
                    add(CoupleWidgetDisplayItem.Notice(statusText))
                    add(CoupleWidgetDisplayItem.NoticeDivider)
                }
                shownCourses.take(
                    maxVisibleCourses.coerceIn(0, MAX_VISIBLE_COURSES)
                ).forEachIndexed { index, course ->
                    if (index > 0) add(CoupleWidgetDisplayItem.Divider)
                    val start = parseClockMinutes(course.startTime)
                    val end = parseClockMinutes(course.endTime)
                    add(
                        CoupleWidgetDisplayItem.Course(
                            course = course,
                            isOngoing = start != null && end != null &&
                                nowMinutes >= start && nowMinutes < end,
                        )
                    )
                }
            }
        }
        val footerText = when {
            hasRemainingCourse -> context.getString(
                R.string.widget_couple_today_remaining,
                remainingCount,
                today.size,
            )
            tomorrow.isNotEmpty() ->
                context.getString(R.string.widget_couple_tomorrow_count, tomorrow.size)
            else -> context.getString(R.string.widget_couple_no_course_tomorrow)
        }
        return CoupleWidgetDisplay(
            items = items,
            footerText = footerText,
            emptyText = if (items.isEmpty()) statusText else null,
        )
    }

    fun parseClockMinutes(value: String): Int? {
        val parts = value.split(":")
        if (parts.size != 2) return null
        val hour = parts[0].toIntOrNull() ?: return null
        val minute = parts[1].toIntOrNull() ?: return null
        if (hour !in 0..23 || minute !in 0..59) return null
        return hour * 60 + minute
    }
}

internal data class CoupleTimetableSizing(
    val availableListHeightPx: Float,
    val visibleCourseCount: Int,
    val courseRowHeightPx: Float,
    val noticeRowHeightPx: Float = 0f,
)

internal object CoupleTimetableSizingSupport {
    private const val CARD_VERTICAL_PADDING_DP = 14f
    private const val HEADER_HEIGHT_DP = 20f
    private const val HEADER_TOP_MARGIN_DP = 5f
    private const val FOOTER_HEIGHT_DP = 13f
    private const val MIN_COURSE_ROW_DP = 34f
    private const val DIVIDER_TOTAL_DP = 5f

    fun calculate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        display: CoupleWidgetDisplay,
    ): CoupleTimetableSizing {
        val density = context.resources.displayMetrics.density
        val availableHeightPx = availableListHeightPx(context, appWidgetManager, appWidgetId)
        val maxCourseCount = display.items.count { it is CoupleWidgetDisplayItem.Course }
        val hasNotice = display.items.any { it is CoupleWidgetDisplayItem.Notice }
        val courseCount = if (maxCourseCount == 0) {
            0
        } else {
            val courseAreaHeightPx = if (hasNotice) {
                availableHeightPx / 2f
            } else {
                availableHeightPx
            }
            (maxCourseCount downTo 1).firstOrNull { count ->
                val dividerCount = if (hasNotice) count else (count - 1).coerceAtLeast(0)
                val requiredHeightPx = count * MIN_COURSE_ROW_DP * density +
                    dividerCount * DIVIDER_TOTAL_DP * density
                courseAreaHeightPx >= requiredHeightPx
            } ?: 0
        }
        val dividerCount = if (hasNotice) {
            courseCount
        } else {
            (courseCount - 1).coerceAtLeast(0)
        }
        val dividerHeightPx = dividerCount * DIVIDER_TOTAL_DP * density
        val rowHeightPx = if (courseCount == 0) {
            0f
        } else {
            val courseAreaHeightPx = if (hasNotice) {
                availableHeightPx / 2f
            } else {
                availableHeightPx
            }
            ((courseAreaHeightPx - dividerHeightPx) / courseCount)
                .coerceAtLeast(MIN_COURSE_ROW_DP * density)
        }
        val noticeHeightPx = if (hasNotice) availableHeightPx / 2f else 0f
        return CoupleTimetableSizing(
            availableListHeightPx = availableHeightPx,
            visibleCourseCount = courseCount,
            courseRowHeightPx = rowHeightPx,
            noticeRowHeightPx = noticeHeightPx,
        )
    }

    fun calculateSynced(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        display: CoupleWidgetDisplay,
        oppositeDisplay: CoupleWidgetDisplay,
    ): CoupleTimetableSizing {
        val current = calculate(context, appWidgetManager, appWidgetId, display)
        val opposite = calculate(context, appWidgetManager, appWidgetId, oppositeDisplay)
        val sharedRowHeightPx = listOf(
            current.courseRowHeightPx.takeIf { it > 0f },
            opposite.courseRowHeightPx.takeIf { it > 0f },
        ).filterNotNull().minOrNull() ?: return current

        val density = context.resources.displayMetrics.density
        val availableHeightPx = availableListHeightPx(context, appWidgetManager, appWidgetId)
        val maxCourseCount = display.items.count { it is CoupleWidgetDisplayItem.Course }
        val hasNotice = display.items.any { it is CoupleWidgetDisplayItem.Notice }
        val courseAreaHeightPx = if (hasNotice) {
            availableHeightPx / 2f
        } else {
            availableHeightPx
        }
        val courseCount = if (maxCourseCount == 0) {
            0
        } else {
            (maxCourseCount downTo 1).firstOrNull { count ->
                val dividerCount = if (hasNotice) count else (count - 1).coerceAtLeast(0)
                val requiredHeightPx = count * sharedRowHeightPx +
                    dividerCount * DIVIDER_TOTAL_DP * density
                courseAreaHeightPx >= requiredHeightPx
            } ?: 0
        }
        return current.copy(
            visibleCourseCount = courseCount,
            courseRowHeightPx = sharedRowHeightPx,
        )
    }

    fun applyRowHeight(views: RemoteViews, viewId: Int, heightPx: Float) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && heightPx > 0f) {
            views.setViewLayoutHeight(viewId, heightPx, TypedValue.COMPLEX_UNIT_PX)
        }
    }

    private fun availableListHeightPx(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
    ): Float {
        val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
        val isPortrait = context.resources.configuration.orientation ==
            android.content.res.Configuration.ORIENTATION_PORTRAIT
        val optionHeightDp = if (isPortrait) {
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
        } else {
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        }
        val heightDp = optionHeightDp.takeIf { it > 0 }
            ?: appWidgetManager.getAppWidgetInfo(appWidgetId)?.minHeight?.takeIf { it > 0 }
            ?: 180
        val reservedHeightDp = CARD_VERTICAL_PADDING_DP +
            HEADER_HEIGHT_DP +
            HEADER_TOP_MARGIN_DP +
            FOOTER_HEIGHT_DP
        val listHeightDp = (heightDp - reservedHeightDp).coerceAtLeast(0f)
        return listHeightDp * context.resources.displayMetrics.density
    }
}

internal object CoupleTimetableRenderSupport {
    fun createNameBitmap(context: Context, text: String, color: Int): Bitmap? {
        val value = text.trim()
        if (value.isEmpty()) return null
        val density = context.resources.displayMetrics.density
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            textSize = sp(context, 13f)
            typeface = ResourcesCompat.getFont(context, R.font.pacifico)
            setShadowLayer(
                density,
                density * 0.5f,
                density * 0.5f,
                ContextCompat.getColor(context, R.color.widget_couple_shadow)
            )
        }
        val maxWidth = density * 104f
        val label = TextUtils.ellipsize(value, paint, maxWidth, TextUtils.TruncateAt.END)
        val metrics = paint.fontMetrics
        val textHeight = metrics.descent - metrics.ascent
        val height = (density * 20f).toInt().coerceAtLeast(textHeight.toInt() + 1)
        val width = (paint.measureText(label, 0, label.length) + density * 3f)
            .toInt()
            .coerceAtMost(maxWidth.toInt())
            .coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val baseline = (height - textHeight) / 2f - metrics.ascent
        canvas.drawText(label, 0, label.length, density * 1.5f, baseline, paint)
        return bitmap
    }

    fun createProgressBitmap(
        context: Context,
        accentColor: Int,
        course: CoupleWidgetCourse,
        nowMinutes: Int,
    ): Bitmap? {
        val start = CoupleTimetableDisplayBuilder.parseClockMinutes(course.startTime) ?: return null
        val end = CoupleTimetableDisplayBuilder.parseClockMinutes(course.endTime) ?: return null
        if (end <= start || nowMinutes !in start until end) return null

        val density = context.resources.displayMetrics.density
        val width = (density * 220f).toInt().coerceAtLeast(1)
        val height = (density * 3f).toInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val trackColor = ContextCompat.getColor(context, R.color.widget_couple_divider)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = trackColor }
        val radius = height / 2f
        canvas.drawRoundRect(RectF(0f, 0f, width.toFloat(), height.toFloat()), radius, radius, paint)

        val progress = ((nowMinutes - start).toFloat() / (end - start).toFloat())
            .coerceIn(0f, 1f)
        paint.color = accentColor
        canvas.drawRoundRect(
            RectF(0f, 0f, width * progress, height.toFloat()),
            radius,
            radius,
            paint
        )

        val markerWidth = density * 1.2f
        paint.color = ContextCompat.getColor(context, R.color.widget_couple_current_bg)
        for (breakTime in course.breaks) {
            val boundary = CoupleTimetableDisplayBuilder.parseClockMinutes(breakTime.startTime)
                ?: continue
            if (boundary <= start || boundary >= end) continue
            val x = width * ((boundary - start).toFloat() / (end - start).toFloat())
            canvas.drawRect(x - markerWidth / 2f, 0f, x + markerWidth / 2f, height.toFloat(), paint)
        }
        return bitmap
    }

    private fun sp(context: Context, value: Float): Float {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP,
            value,
            context.resources.displayMetrics
        )
    }
}

class CoupleTimetableViewsService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return CoupleTimetableViewsFactory(applicationContext, intent)
    }

    private class CoupleTimetableViewsFactory(
        private val context: Context,
        intent: Intent,
    ) : RemoteViewsFactory {
        private val appWidgetId = intent.getIntExtra(
            CoupleTimetableWidgetProvider.EXTRA_APP_WIDGET_ID,
            -1
        )
        private val isLeft = intent.getBooleanExtra(
            CoupleTimetableWidgetProvider.EXTRA_IS_LEFT,
            true
        )
        private val accentColor = intent.getIntExtra(
            CoupleTimetableWidgetProvider.EXTRA_ACCENT_COLOR,
            if (isLeft) {
                CoupleTimetableWidgetProvider.leftAccentColor(context)
            } else {
                CoupleTimetableWidgetProvider.rightAccentColor(context)
            }
        )
        private var items: List<CoupleWidgetDisplayItem> = emptyList()
        private var courseRowHeightPx = 0f
        private var noticeRowHeightPx = 0f

        override fun onCreate() {
            onDataSetChanged()
        }

        override fun onDataSetChanged() {
            val snapshot = CoupleTimetableStore.readSnapshot(context)
            val status = snapshot?.status ?: CoupleWidgetStatus.COUPLE_MODE_OFF
            val courses = if (isLeft) snapshot?.mine else snapshot?.partner
            if (status != CoupleWidgetStatus.OK || courses == null) {
                items = emptyList()
                courseRowHeightPx = 0f
                noticeRowHeightPx = 0f
            } else {
                val appWidgetManager = AppWidgetManager.getInstance(context)
                val oppositeCourses = if (isLeft) snapshot?.partner else snapshot?.mine
                val unconstrainedDisplay = CoupleTimetableDisplayBuilder.build(
                    context,
                    courses,
                    status = status,
                )
                val oppositeUnconstrainedDisplay = CoupleTimetableDisplayBuilder.build(
                    context,
                    oppositeCourses ?: CoupleWidgetDayCourses(emptyList(), emptyList()),
                    status = status,
                )
                val sizing = CoupleTimetableSizingSupport.calculateSynced(
                    context,
                    appWidgetManager,
                    appWidgetId,
                    unconstrainedDisplay,
                    oppositeUnconstrainedDisplay,
                )
                val display = CoupleTimetableDisplayBuilder.build(
                    context,
                    courses,
                    status = status,
                    maxVisibleCourses = sizing.visibleCourseCount,
                )
                items = display.items
                courseRowHeightPx = sizing.courseRowHeightPx
                noticeRowHeightPx = sizing.noticeRowHeightPx
            }
        }

        override fun onDestroy() {
            items = emptyList()
        }

        override fun getCount(): Int = items.size

        override fun getViewAt(position: Int): RemoteViews {
            return when (val item = items.getOrNull(position)) {
                is CoupleWidgetDisplayItem.Course -> renderCourse(item).apply {
                    attachSideTap(R.id.widget_couple_course_root)
                }
                is CoupleWidgetDisplayItem.Notice ->
                    renderNotice(item.text).apply {
                        attachSideTap(R.id.widget_couple_today_ended)
                    }
                CoupleWidgetDisplayItem.NoticeDivider ->
                    RemoteViews(
                        context.packageName,
                        R.layout.widget_couple_notice_divider
                    ).apply {
                        attachSideTap(R.id.widget_couple_notice_divider)
                    }
                CoupleWidgetDisplayItem.Divider ->
                    RemoteViews(
                        context.packageName,
                        R.layout.widget_couple_course_divider
                    ).apply {
                        attachSideTap(R.id.widget_couple_course_divider)
                    }
                null -> RemoteViews(
                    context.packageName,
                    R.layout.widget_couple_today_ended_item
                ).apply {
                    attachSideTap(R.id.widget_couple_today_ended)
                }
            }
        }

        // 行点击随 PendingIntentTemplate 派发到对应一侧；不挂 fill intent
        // 的行不会触发模板，导致课程行区域成为点击死区。
        private fun RemoteViews.attachSideTap(rootId: Int) {
            setOnClickFillInIntent(
                rootId,
                Intent().putExtra(
                    TodayWidgetSupport.EXTRA_WIDGET_LAUNCH_SIDE,
                    if (isLeft) "left" else "right"
                )
            )
        }

        private fun renderCourse(item: CoupleWidgetDisplayItem.Course): RemoteViews {
            val views = RemoteViews(
                context.packageName,
                R.layout.widget_couple_course_item
            )
            CoupleTimetableSizingSupport.applyRowHeight(
                views,
                R.id.widget_couple_course_root,
                courseRowHeightPx,
            )
            val course = item.course
            views.setTextViewText(
                R.id.widget_couple_course_name,
                course.shortName?.takeIf { it.isNotBlank() } ?: course.name
            )
            views.setTextViewText(
                R.id.widget_couple_course_location,
                course.location.takeIf { it.isNotBlank() } ?: " "
            )
            views.setTextViewText(
                R.id.widget_couple_course_time,
                "${course.startTime} - ${course.endTime}"
            )
            views.setInt(
                R.id.widget_couple_course_indicator,
                "setColorFilter",
                accentColor
            )
            if (item.isOngoing) {
                views.setInt(
                    R.id.widget_couple_course_root,
                    "setBackgroundResource",
                    R.drawable.widget_couple_current_bg
                )
                val now = Calendar.getInstance()
                val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
                val progress = CoupleTimetableRenderSupport.createProgressBitmap(
                    context,
                    accentColor,
                    course,
                    nowMinutes
                )
                if (progress != null) {
                    views.setImageViewBitmap(R.id.widget_couple_course_progress, progress)
                    views.setViewVisibility(R.id.widget_couple_course_progress, View.VISIBLE)
                } else {
                    views.setViewVisibility(R.id.widget_couple_course_progress, View.GONE)
                }
            } else {
                views.setViewVisibility(R.id.widget_couple_course_progress, View.GONE)
            }
            return views
        }

        private fun renderNotice(text: String): RemoteViews {
            val views = RemoteViews(
                context.packageName,
                R.layout.widget_couple_today_ended_item
            )
            views.setTextViewText(R.id.widget_couple_today_ended, text)
            CoupleTimetableSizingSupport.applyRowHeight(
                views,
                R.id.widget_couple_today_ended,
                noticeRowHeightPx,
            )
            return views
        }

        override fun getLoadingView(): RemoteViews? = null

        override fun getViewTypeCount(): Int = 4

        override fun getItemId(position: Int): Long {
            return when (val item = items.getOrNull(position)) {
                is CoupleWidgetDisplayItem.Course ->
                    (item.course.id.hashCode().toLong() * 31L) + item.course.startSection
                is CoupleWidgetDisplayItem.Notice -> item.text.hashCode().toLong()
                CoupleWidgetDisplayItem.NoticeDivider -> "notice-divider".hashCode().toLong()
                CoupleWidgetDisplayItem.Divider -> "divider".hashCode().toLong()
                null -> 0L
            }
        }

        override fun hasStableIds(): Boolean = true
    }
}
