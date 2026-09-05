package com.mutx163.qingyu

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import androidx.core.content.ContextCompat
import androidx.core.content.res.ResourcesCompat
import android.text.TextUtils
import android.text.TextPaint
import java.util.Calendar

internal sealed class CoupleWidgetDisplayItem {
    data class Course(
        val course: CoupleWidgetCourse,
        val isOngoing: Boolean,
    ) : CoupleWidgetDisplayItem()

    data class Notice(val text: String) : CoupleWidgetDisplayItem()
    data object Divider : CoupleWidgetDisplayItem()
}

internal data class CoupleWidgetDisplay(
    val items: List<CoupleWidgetDisplayItem>,
    val footerText: String,
)

internal object CoupleTimetableDisplayBuilder {
    fun build(
        context: Context,
        courses: CoupleWidgetDayCourses,
        nowMillis: Long = System.currentTimeMillis(),
    ): CoupleWidgetDisplay {
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

        val shownCourses = if (hasRemainingCourse) today else tomorrow
        val items = buildList {
            if (!hasRemainingCourse) {
                val noticeText = if (today.isEmpty()) {
                    context.getString(R.string.widget_no_course_today)
                } else {
                    context.getString(R.string.widget_today_ended_short)
                }
                add(CoupleWidgetDisplayItem.Notice(noticeText))
            }
            shownCourses.forEachIndexed { index, course ->
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
        val footerText = when {
            hasRemainingCourse -> context.getString(R.string.widget_today_count, today.size)
            tomorrow.isNotEmpty() ->
                context.getString(R.string.widget_couple_tomorrow_count, tomorrow.size)
            else -> context.getString(R.string.widget_couple_no_course_tomorrow)
        }
        return CoupleWidgetDisplay(items, footerText)
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

        override fun onCreate() {
            onDataSetChanged()
        }

        override fun onDataSetChanged() {
            val snapshot = CoupleTimetableStore.readSnapshot(context)
            val courses = if (isLeft) snapshot?.mine else snapshot?.partner
            items = if (courses == null) {
                emptyList()
            } else {
                CoupleTimetableDisplayBuilder.build(context, courses).items
            }
        }

        override fun onDestroy() {
            items = emptyList()
        }

        override fun getCount(): Int = items.size

        override fun getViewAt(position: Int): RemoteViews {
            return when (val item = items.getOrNull(position)) {
                is CoupleWidgetDisplayItem.Course -> renderCourse(item)
                is CoupleWidgetDisplayItem.Notice -> renderNotice(item.text)
                CoupleWidgetDisplayItem.Divider ->
                    RemoteViews(context.packageName, R.layout.widget_couple_course_divider)
                null -> RemoteViews(context.packageName, R.layout.widget_couple_today_ended_item)
            }
        }

        private fun renderCourse(item: CoupleWidgetDisplayItem.Course): RemoteViews {
            val views = RemoteViews(
                context.packageName,
                R.layout.widget_couple_course_item
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
            return views
        }

        override fun getLoadingView(): RemoteViews? = null

        override fun getViewTypeCount(): Int = 3

        override fun getItemId(position: Int): Long {
            return when (val item = items.getOrNull(position)) {
                is CoupleWidgetDisplayItem.Course ->
                    (item.course.id.hashCode().toLong() * 31L) + item.course.startSection
                is CoupleWidgetDisplayItem.Notice -> item.text.hashCode().toLong()
                CoupleWidgetDisplayItem.Divider -> "divider".hashCode().toLong()
                null -> 0L
            }
        }

        override fun hasStableIds(): Boolean = true
    }
}
