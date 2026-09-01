package com.mutx163.qingyu

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.content.Intent
import androidx.core.content.res.ResourcesCompat
import android.view.View
import android.widget.RemoteViews
import java.util.Calendar
import kotlin.math.roundToInt

private data class CoupleWidgetBreak(
    val startTime: String,
    val endTime: String,
)

private data class CoupleWidgetCourse(
    val name: String,
    val location: String,
    val startTime: String,
    val endTime: String,
    val breaks: List<CoupleWidgetBreak> = emptyList(),
)

private data class CoupleWidgetProgressSegment(
    val weight: Float,
    val progress: Float,
    val isBreak: Boolean = false,
)

private data class CoupleWidgetDisplayCourse(
    val course: CoupleWidgetCourse,
    val isOngoing: Boolean = false,
    val progressSegments: List<CoupleWidgetProgressSegment> = emptyList(),
)

private data class CoupleWidgetDisplay(
    val courses: List<CoupleWidgetDisplayCourse>,
    val emptyTextRes: Int,
    val footerText: String,
)

/**
 * Couple timetable desktop card (4x2): left column shows my courses, right
 * column shows my partner's courses. Uses mock data until the backend exists.
 */
class CoupleTimetableWidgetProvider : AppWidgetProvider() {
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        updateWidget(context, appWidgetManager, appWidgetId)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, CoupleTimetableWidgetProvider::class.java)
            )
            onUpdate(context, manager, ids)
        }
    }

    companion object {
        private const val MY_NAME = "govex"
        private const val PARTNER_NAME = "xoveg"

        private val myCourses = listOf(
            CoupleWidgetCourse(
                "高等数学",
                "一教104",
                "08:00",
                "09:40",
                breaks = listOf(CoupleWidgetBreak("08:45", "08:55")),
            ),
            CoupleWidgetCourse(
                "大学英语",
                "二教A205",
                "10:10",
                "11:45",
                breaks = listOf(CoupleWidgetBreak("10:55", "11:05")),
            ),
            CoupleWidgetCourse(
                "界面设计",
                "设计楼302",
                "12:00",
                "13:30",
                breaks = listOf(CoupleWidgetBreak("12:45", "12:55")),
            ),
            CoupleWidgetCourse(
                "线性代数",
                "一教B301",
                "14:00",
                "15:35",
                breaks = listOf(CoupleWidgetBreak("14:45", "14:55")),
            ),
        )

        private val partnerCourses = listOf(
            CoupleWidgetCourse(
                "数据结构",
                "二教B208",
                "08:00",
                "09:35",
                breaks = listOf(CoupleWidgetBreak("08:45", "08:50")),
            ),
            CoupleWidgetCourse(
                "现代史",
                "文科楼103",
                "13:30",
                "15:05",
                breaks = listOf(CoupleWidgetBreak("14:15", "14:20")),
            ),
            CoupleWidgetCourse(
                "数据库原理",
                "三教C302",
                "12:30",
                "14:00",
                breaks = listOf(
                    CoupleWidgetBreak("12:55", "13:00"),
                    CoupleWidgetBreak("13:20", "13:25"),
                ),
            ),
            CoupleWidgetCourse(
                "大学物理",
                "理科楼206",
                "15:20",
                "16:55",
                breaks = listOf(CoupleWidgetBreak("16:05", "16:10")),
            ),
        )

        private val myTomorrowCourses = listOf(
            CoupleWidgetCourse(
                "英语听力",
                "外语楼301",
                "08:00",
                "09:35",
                breaks = listOf(CoupleWidgetBreak("08:45", "08:50")),
            ),
            CoupleWidgetCourse(
                "程序设计",
                "机房502",
                "10:10",
                "11:45",
                breaks = listOf(CoupleWidgetBreak("10:55", "11:05")),
            ),
        )

        private val partnerTomorrowCourses = listOf(
            CoupleWidgetCourse(
                "计算机网络",
                "三教405",
                "09:50",
                "11:25",
                breaks = listOf(CoupleWidgetBreak("10:35", "10:40")),
            ),
            CoupleWidgetCourse(
                "体育",
                "运动场",
                "14:00",
                "15:35",
                breaks = listOf(CoupleWidgetBreak("14:45", "14:50")),
            ),
        )

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, CoupleTimetableWidgetProvider::class.java)
            )
            ids.forEach { appWidgetId ->
                updateWidget(context, manager, appWidgetId)
            }
        }

        private fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_couple_timetable)

            views.setImageViewBitmap(
                R.id.widget_couple_left_name,
                createNameBitmap(context, MY_NAME),
            )
            views.setImageViewBitmap(
                R.id.widget_couple_right_name,
                createNameBitmap(context, PARTNER_NAME),
            )
            views.setImageViewBitmap(R.id.widget_couple_heart, createHeartBitmap(context))

            val launchIntent = TodayWidgetSupport.buildLaunchPendingIntent(context, appWidgetId)
            views.setOnClickPendingIntent(R.id.widget_card, launchIntent)
            views.setOnClickPendingIntent(R.id.widget_couple_left_column, launchIntent)
            views.setOnClickPendingIntent(R.id.widget_couple_right_column, launchIntent)

            bindColumn(
                context,
                views,
                R.id.widget_couple_left_content,
                R.id.widget_couple_left_footer,
                R.id.widget_couple_left_empty,
                myCourses,
                myTomorrowCourses,
                context.getColor(R.color.widget_couple_left_accent),
            )
            bindColumn(
                context,
                views,
                R.id.widget_couple_right_content,
                R.id.widget_couple_right_footer,
                R.id.widget_couple_right_empty,
                partnerCourses,
                partnerTomorrowCourses,
                context.getColor(R.color.widget_couple_right_accent),
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun bindColumn(
            context: Context,
            views: RemoteViews,
            containerId: Int,
            footerId: Int,
            emptyId: Int,
            courses: List<CoupleWidgetCourse>,
            tomorrowCourses: List<CoupleWidgetCourse>,
            accentColor: Int,
        ) {
            val display = buildDisplay(context, courses, tomorrowCourses)
            views.removeAllViews(containerId)

            views.setTextViewText(footerId, display.footerText)
            views.setTextViewText(emptyId, context.getString(display.emptyTextRes))

            if (display.courses.isEmpty()) {
                views.setViewVisibility(containerId, View.GONE)
                views.setViewVisibility(emptyId, View.VISIBLE)
                return
            }

            views.setViewVisibility(containerId, View.VISIBLE)
            views.setViewVisibility(emptyId, View.GONE)
            views.setTextViewText(emptyId, context.getString(display.emptyTextRes))
            views.setTextViewText(footerId, display.footerText)

            val visibleCourses = display.courses.take(2)
            visibleCourses.forEachIndexed { index, displayCourse ->
                val course = displayCourse.course
                val item = RemoteViews(context.packageName, R.layout.widget_couple_course_item)
                item.setTextViewText(R.id.widget_couple_course_name, course.name)
                item.setTextViewText(R.id.widget_couple_course_location, course.location)
                item.setTextViewText(R.id.widget_couple_course_time, "${course.startTime} - ${course.endTime}")
                item.setInt(R.id.widget_couple_course_indicator, "setColorFilter", accentColor)
                if (displayCourse.isOngoing) {
                    item.setInt(
                        R.id.widget_couple_course_root,
                        "setBackgroundResource",
                        R.drawable.widget_couple_current_bg,
                    )
                }
                item.setViewVisibility(
                    R.id.widget_couple_course_progress,
                    if (displayCourse.isOngoing && displayCourse.progressSegments.isNotEmpty()) {
                        View.VISIBLE
                    } else {
                        View.GONE
                    },
                )
                if (displayCourse.isOngoing) {
                    item.setImageViewBitmap(
                        R.id.widget_couple_course_progress,
                        createProgressBitmap(context, displayCourse.progressSegments, accentColor),
                    )
                }
                views.addView(containerId, item)

                if (index < visibleCourses.size - 1) {
                    views.addView(
                        containerId,
                        RemoteViews(context.packageName, R.layout.widget_couple_course_divider),
                    )
                }
            }
        }

        private fun buildDisplay(
            context: Context,
            todayCourses: List<CoupleWidgetCourse>,
            tomorrowCourses: List<CoupleWidgetCourse>,
        ): CoupleWidgetDisplay {
            val nowMillis = Calendar.getInstance().timeInMillis
            val visibleCourses = todayCourses
                .mapNotNull { course ->
                    val startMillis = buildCourseTimeMillis(nowMillis, course.startTime)
                        ?: return@mapNotNull null
                    val endMillis = buildCourseTimeMillis(nowMillis, course.endTime)
                        ?: return@mapNotNull null
                    if (endMillis <= nowMillis) {
                        return@mapNotNull null
                    }
                    val isOngoing = nowMillis >= startMillis
                    val progressSegments = if (isOngoing) {
                        buildProgressSegments(nowMillis, course, startMillis, endMillis)
                    } else {
                        emptyList()
                    }
                    CoupleWidgetDisplayCourse(course, isOngoing, progressSegments)
                }
                .sortedWith(
                    compareByDescending<CoupleWidgetDisplayCourse> { it.isOngoing }
                        .thenBy { it.course.startTime }
                        .thenBy { it.course.endTime },
                )

            if (visibleCourses.isNotEmpty()) {
                return CoupleWidgetDisplay(
                    courses = visibleCourses,
                    emptyTextRes = R.string.widget_no_course_today,
                    footerText = context.getString(R.string.widget_today_count, todayCourses.size),
                )
            }

            val emptyTextRes = if (todayCourses.isNotEmpty()) {
                R.string.widget_today_ended_short
            } else {
                R.string.widget_no_course_today
            }
            val tomorrowDisplay = tomorrowCourses.map { CoupleWidgetDisplayCourse(it) }
            val footerText = if (tomorrowDisplay.isNotEmpty()) {
                context.getString(R.string.widget_couple_tomorrow_count, tomorrowDisplay.size)
            } else {
                context.getString(R.string.widget_couple_no_course_tomorrow)
            }
            return CoupleWidgetDisplay(tomorrowDisplay, emptyTextRes, footerText)
        }

        fun findNextRefreshAtMillis(nowMillis: Long = System.currentTimeMillis()): Long? {
            val today = myCourses + partnerCourses
            val triggers = buildList {
                today.forEach { course ->
                    add(buildCourseTimeMillis(nowMillis, course.startTime))
                    add(buildCourseTimeMillis(nowMillis, course.endTime)?.plus(1_000L))
                    course.breaks.forEach { courseBreak ->
                        add(buildCourseTimeMillis(nowMillis, courseBreak.startTime))
                        add(buildCourseTimeMillis(nowMillis, courseBreak.endTime)?.plus(1_000L))
                    }
                }
                if (today.any { course ->
                        val start = buildCourseTimeMillis(nowMillis, course.startTime)
                        val end = buildCourseTimeMillis(nowMillis, course.endTime)
                        start != null && end != null && nowMillis >= start && nowMillis < end
                    }
                ) {
                    add(nowMillis + 60_000L)
                }
                add(
                    Calendar.getInstance().apply {
                        timeInMillis = nowMillis
                        add(Calendar.DAY_OF_YEAR, 1)
                        set(Calendar.HOUR_OF_DAY, 0)
                        set(Calendar.MINUTE, 0)
                        set(Calendar.SECOND, 0)
                        set(Calendar.MILLISECOND, 0)
                    }.timeInMillis + 1_000L,
                )
            }
            return triggers.filterNotNull().filter { it > nowMillis }.minOrNull()
        }

        private fun buildCourseTimeMillis(
            nowMillis: Long,
            courseTime: String,
        ): Long? {
            val parts = courseTime.split(":")
            if (parts.size != 2) return null
            val hour = parts[0].toIntOrNull() ?: return null
            val minute = parts[1].toIntOrNull() ?: return null
            return Calendar.getInstance().apply {
                timeInMillis = nowMillis
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }.timeInMillis
        }

        private fun buildProgressSegments(
            nowMillis: Long,
            course: CoupleWidgetCourse,
            startMillis: Long,
            endMillis: Long,
        ): List<CoupleWidgetProgressSegment> {
            data class RawSegment(
                val start: Long,
                val end: Long,
                val isBreak: Boolean,
            )

            val segments = mutableListOf<RawSegment>()
            var cursor = startMillis
            course.breaks
                .mapNotNull { courseBreak ->
                    val breakStart = buildCourseTimeMillis(nowMillis, courseBreak.startTime)
                    val breakEnd = buildCourseTimeMillis(nowMillis, courseBreak.endTime)
                    if (breakStart == null || breakEnd == null) null else breakStart to breakEnd
                }
                .sortedBy { it.first }
                .forEach { (breakStart, breakEnd) ->
                    if (breakStart < cursor || breakEnd <= breakStart || breakEnd > endMillis) {
                        return@forEach
                    }
                    if (breakStart > cursor) {
                        segments.add(RawSegment(cursor, breakStart, isBreak = false))
                    }
                    segments.add(RawSegment(breakStart, breakEnd, isBreak = true))
                    cursor = breakEnd
                }
            if (cursor < endMillis) {
                segments.add(RawSegment(cursor, endMillis, isBreak = false))
            }
            if (segments.none { it.isBreak }) {
                segments.clear()
                segments.add(RawSegment(startMillis, endMillis, isBreak = false))
            }

            return segments.mapNotNull { segment ->
                val weight = (segment.end - segment.start) / 60_000f
                if (weight <= 0f) return@mapNotNull null
                val progress = if (segment.isBreak) {
                    1f
                } else {
                    ((nowMillis - segment.start).toFloat() / (segment.end - segment.start))
                        .coerceIn(0f, 1f)
                }
                CoupleWidgetProgressSegment(weight, progress, segment.isBreak)
            }
        }

        private fun createProgressBitmap(
            context: Context,
            segments: List<CoupleWidgetProgressSegment>,
            accentColor: Int,
        ): Bitmap {
            val density = context.resources.displayMetrics.density
            val width = (220f * density).roundToInt().coerceAtLeast(1)
            val height = (4f * density).roundToInt().coerceAtLeast(4)
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = context.getColor(R.color.widget_couple_divider)
            }
            val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = accentColor }
            val radius = height / 2f
            val totalClassWeight = segments
                .filter { !it.isBreak }
                .sumOf { it.weight.toDouble() }
                .toFloat()
                .coerceAtLeast(0.01f)

            canvas.drawRoundRect(
                RectF(0f, 0f, width.toFloat(), height.toFloat()),
                radius,
                radius,
                trackPaint,
            )

            var classWeight = 0f
            val breakPositions = mutableListOf<Float>()
            segments.forEach { segment ->
                if (segment.isBreak) {
                    breakPositions.add(width * (classWeight / totalClassWeight))
                } else {
                    val left = width * (classWeight / totalClassWeight)
                    classWeight += segment.weight
                    val right = width * (classWeight / totalClassWeight)
                    if (segment.progress > 0f) {
                        canvas.drawRoundRect(
                            left,
                            0f,
                            left + (right - left) * segment.progress,
                            height.toFloat(),
                            radius,
                            radius,
                            progressPaint,
                        )
                    }
                }
            }

            val markerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = context.getColor(R.color.widget_couple_current_bg)
            }
            val markerWidth = (1.2f * density).coerceAtLeast(1f)
            breakPositions.forEach { position ->
                canvas.drawRoundRect(
                    position - markerWidth / 2f,
                    0f,
                    position + markerWidth / 2f,
                    height.toFloat(),
                    markerWidth / 2f,
                    markerWidth / 2f,
                    markerPaint,
                )
            }
            return bitmap
        }

        private fun createNameBitmap(
            context: Context,
            text: String,
        ): Bitmap {
            val density = context.resources.displayMetrics.density
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                typeface = ResourcesCompat.getFont(context, R.font.pacifico_regular)
                textSize = 13f * density
                color = context.getColor(R.color.widget_couple_text_primary)
                setShadowLayer(
                    2f * density,
                    0f,
                    density,
                    context.getColor(R.color.widget_couple_shadow),
                )
            }
            val metrics = paint.fontMetrics
            val padding = (1.5f * density).roundToInt().coerceAtLeast(1)
            val width = (paint.measureText(text) + padding * 2f).roundToInt().coerceAtLeast(1)
            val height = (metrics.descent - metrics.ascent + padding * 2f)
                .roundToInt()
                .coerceAtLeast(1)
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            canvas.drawText(text, padding.toFloat(), padding - metrics.ascent, paint)
            return bitmap
        }

        private fun createHeartBitmap(context: Context): Bitmap {
            val density = context.resources.displayMetrics.density
            val size = (16f * density).roundToInt().coerceAtLeast(1)
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val heart = Path().apply {
                moveTo(12f, 21f)
                cubicTo(12f, 21f, 3f, 14.5f, 3f, 8.5f)
                cubicTo(3f, 5.5f, 5.5f, 3f, 8.5f, 3f)
                cubicTo(10.24f, 3f, 11.91f, 3.83f, 12f, 5.09f)
                cubicTo(12.09f, 3.83f, 13.76f, 3f, 15.5f, 3f)
                cubicTo(18.5f, 3f, 21f, 5.5f, 21f, 8.5f)
                cubicTo(21f, 14.5f, 12f, 21f, 12f, 21f)
                close()
            }
            val scale = size / 24f
            canvas.scale(scale, scale)
            canvas.drawPath(
                heart,
                Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = context.getColor(R.color.widget_couple_right_accent)
                    style = Paint.Style.FILL
                },
            )
            return bitmap
        }
    }
}
