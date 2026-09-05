package com.mutx163.qingyu

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat

class CoupleTimetableWidgetProvider : BaseQingyuWidgetProvider() {
    override fun providerClass(): Class<out BaseQingyuWidgetProvider> =
        CoupleTimetableWidgetProvider::class.java

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            renderWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun renderWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
    ) {
        val views = RemoteViews(context.packageName, R.layout.widget_couple_timetable)
        val snapshot = CoupleTimetableStore.readSnapshot(context)

        val leftColor = snapshot?.leftColorHex
            ?.let(::parseColorOrNull)
            ?: leftAccentColor(context)
        val rightColor = snapshot?.rightColorHex
            ?.let(::parseColorOrNull)
            ?: rightAccentColor(context)

        snapshot?.myName?.let { name ->
            CoupleTimetableRenderSupport.createNameBitmap(context, name, leftColor)
        }?.let { views.setImageViewBitmap(R.id.widget_couple_left_name, it) }
        snapshot?.partnerName?.let { name ->
            CoupleTimetableRenderSupport.createNameBitmap(context, name, rightColor)
        }?.let { views.setImageViewBitmap(R.id.widget_couple_right_name, it) }
        views.setInt(R.id.widget_couple_heart, "setColorFilter", rightColor)

        bindColumn(
            context,
            views,
            appWidgetId,
            isLeft = true,
            courses = snapshot?.mine,
            accentColor = leftColor,
        )
        bindColumn(
            context,
            views,
            appWidgetId,
            isLeft = false,
            courses = snapshot?.partner,
            accentColor = rightColor,
        )

        views.setOnClickPendingIntent(
            R.id.widget_couple_root,
            buildLaunchPendingIntent(context, appWidgetId, isLeft = true)
        )
        views.setOnClickPendingIntent(
            R.id.widget_couple_left_column,
            buildLaunchPendingIntent(context, appWidgetId, isLeft = true)
        )
        views.setOnClickPendingIntent(
            R.id.widget_couple_right_column,
            buildLaunchPendingIntent(context, appWidgetId, isLeft = false)
        )

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun bindColumn(
        context: Context,
        views: RemoteViews,
        appWidgetId: Int,
        isLeft: Boolean,
        courses: CoupleWidgetDayCourses?,
        accentColor: Int,
    ) {
        val listId = if (isLeft) {
            R.id.widget_couple_left_list
        } else {
            R.id.widget_couple_right_list
        }
        val emptyId = if (isLeft) {
            R.id.widget_couple_left_empty
        } else {
            R.id.widget_couple_right_empty
        }
        val footerId = if (isLeft) {
            R.id.widget_couple_left_footer
        } else {
            R.id.widget_couple_right_footer
        }
        val sidePrefix = if (isLeft) "left" else "right"
        val display = if (courses == null) {
            CoupleWidgetDisplay(
                items = emptyList(),
                footerText = context.getString(R.string.widget_couple_no_course_tomorrow)
            )
        } else {
            CoupleTimetableDisplayBuilder.build(context, courses)
        }

        views.setTextViewText(footerId, display.footerText)
        if (display.items.isEmpty()) {
            views.setViewVisibility(listId, View.GONE)
            views.setViewVisibility(emptyId, View.VISIBLE)
            return
        }

        views.setViewVisibility(listId, View.VISIBLE)
        views.setViewVisibility(emptyId, View.GONE)
        val serviceIntent = Intent(context, CoupleTimetableViewsService::class.java).apply {
            putExtra(EXTRA_APP_WIDGET_ID, appWidgetId)
            putExtra(EXTRA_IS_LEFT, isLeft)
            putExtra(EXTRA_ACCENT_COLOR, accentColor)
            data = Uri.parse("qingyu://couple-widget/$appWidgetId/$sidePrefix")
        }
        views.setRemoteAdapter(listId, serviceIntent)
    }

    private fun buildLaunchPendingIntent(
        context: Context,
        appWidgetId: Int,
        isLeft: Boolean,
    ): PendingIntent {
        val side = if (isLeft) "left" else "right"
        val intent = Intent(context, MainActivity::class.java).apply {
            putExtra(TodayWidgetSupport.EXTRA_WIDGET_LAUNCH, true)
            putExtra(TodayWidgetSupport.EXTRA_WIDGET_LAUNCH_APP_WIDGET_ID, appWidgetId)
            putExtra(TodayWidgetSupport.EXTRA_WIDGET_LAUNCH_SIDE, side)
            data = Uri.parse("qingyu://widget-launch/$appWidgetId/$side")
        }
        return PendingIntent.getActivity(
            context,
            appWidgetId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun parseColorOrNull(value: String): Int? {
        return try {
            Color.parseColor(value)
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    companion object {
        const val EXTRA_APP_WIDGET_ID = "couple_widget_app_widget_id"
        const val EXTRA_IS_LEFT = "couple_widget_is_left"
        const val EXTRA_ACCENT_COLOR = "couple_widget_accent_color"

        fun updateAll(context: Context) {
            CoupleTimetableWidgetProvider().updateAll(context)
        }

        fun findNextRefreshAtMillis(nowMillis: Long): Long = nowMillis + 60_000L

        fun leftAccentColor(context: Context): Int {
            return ContextCompat.getColor(context, R.color.widget_couple_left_accent)
        }

        fun rightAccentColor(context: Context): Int {
            return ContextCompat.getColor(context, R.color.widget_couple_right_accent)
        }
    }
}
