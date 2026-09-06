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

        // 整卡可点、左右分流：列容器（含列表下方的空白区）与名字区各自
        // 带 side；列表行经 PendingIntentTemplate 兜底（getViewAt 里逐项
        // 挂 fill intent）；卡片 padding、爱心等残余区域落到 shield 左右
        // 对半（垫在内容之下的透明层）；root 挂 left 作最终保险。
        views.setOnClickPendingIntent(
            R.id.widget_couple_left_shield,
            buildLaunchPendingIntent(context, appWidgetId, isLeft = true)
        )
        views.setOnClickPendingIntent(
            R.id.widget_couple_right_shield,
            buildLaunchPendingIntent(context, appWidgetId, isLeft = false)
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
        views.setOnClickPendingIntent(
            R.id.widget_couple_left_name_container,
            buildLaunchPendingIntent(context, appWidgetId, isLeft = true)
        )
        views.setOnClickPendingIntent(
            R.id.widget_couple_right_name_container,
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
        // 行点击走模板 + 逐项 fill intent（见 CoupleTimetableViewsFactory），
        // 否则 ListView 会吞掉整块区域的点击。模板必须是 MUTABLE：系统要把
        // 各行的 fill intent 合并进 PendingIntent，IMMUTABLE 会让部分启动器
        // 在应用 RemoteViews 时抛异常（表现为「载入窗口小部件时出现问题」）。
        // 模板使用独立 requestCode：PendingIntent 按 (requestCode, intent) 认
        // 同身份，与普通点击共用身份会复用旧实例且 mutability 无法后改。
        views.setPendingIntentTemplate(
            listId,
            buildLaunchPendingIntent(
                context,
                appWidgetId,
                isLeft,
                mutable = true,
                requestCode = templateRequestCode(appWidgetId, isLeft),
            )
        )
    }

    private fun buildLaunchPendingIntent(
        context: Context,
        appWidgetId: Int,
        isLeft: Boolean,
        mutable: Boolean = false,
        requestCode: Int = appWidgetId,
    ): PendingIntent {
        val side = if (isLeft) "left" else "right"
        val intent = Intent(context, MainActivity::class.java).apply {
            putExtra(TodayWidgetSupport.EXTRA_WIDGET_LAUNCH, true)
            putExtra(TodayWidgetSupport.EXTRA_WIDGET_LAUNCH_APP_WIDGET_ID, appWidgetId)
            putExtra(TodayWidgetSupport.EXTRA_WIDGET_LAUNCH_SIDE, side)
            data = Uri.parse("qingyu://widget-launch/$appWidgetId/$side")
        }
        val mutabilityFlag =
            if (mutable) PendingIntent.FLAG_MUTABLE else PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or mutabilityFlag
        )
    }

    private fun templateRequestCode(appWidgetId: Int, isLeft: Boolean): Int {
        // 与普通点击的 requestCode（appWidgetId）错开，避免复用旧实例。
        return 1_000_000 + appWidgetId * 2 + if (isLeft) 0 else 1
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
