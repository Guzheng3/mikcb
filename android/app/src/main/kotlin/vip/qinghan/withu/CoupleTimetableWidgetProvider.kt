package vip.qinghan.withu

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.TypedValue
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
        // 卡片被添加或开机恢复时补排一次刷新调度：零卡片时全量闹钟、分钟级 tick
        // 与 WorkManager 兜底都被停掉了，必须在这里重新武装，分钟级进度才会推进。
        if (appWidgetIds.isNotEmpty()) {
            HomeWidgetStorage.rescheduleRefresh(context)
        }
    }

    override fun renderWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
    ) {
        val views = RemoteViews(context.packageName, R.layout.widget_couple_timetable)
        val snapshot = CoupleTimetableStore.readSnapshot(context)
        val status = snapshot?.status ?: CoupleWidgetStatus.COUPLE_MODE_OFF

        // 昵称配色按性别固定：男生天蓝 #3B82F6，女生粉红 #EC4899。性别取不到
        // （旧快照 / 未登录）时按左男右女兜底，与历史观感一致。
        val leftColor = genderAccentColor(context, snapshot?.myGender)
            ?: maleAccentColor(context)
        val rightColor = genderAccentColor(context, snapshot?.partnerGender)
            ?: femaleAccentColor(context)

        val leftName = snapshot?.myName?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: CoupleTimetableStore.DEFAULT_MY_NAME
        val rightName = snapshot?.partnerName?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: CoupleTimetableStore.DEFAULT_PARTNER_NAME
        CoupleTimetableRenderSupport.createNameBitmap(context, leftName, leftColor)?.let {
            views.setImageViewBitmap(R.id.widget_couple_left_name, it)
        }
        CoupleTimetableRenderSupport.createNameBitmap(context, rightName, rightColor)?.let {
            views.setImageViewBitmap(R.id.widget_couple_right_name, it)
        }
        views.setInt(R.id.widget_couple_heart, "setColorFilter", rightColor)

        bindColumn(
            context,
            appWidgetManager,
            views,
            appWidgetId,
            isLeft = true,
            courses = snapshot?.mine,
            accentColor = leftColor,
            status = status,
        )
        bindColumn(
            context,
            appWidgetManager,
            views,
            appWidgetId,
            isLeft = false,
            courses = snapshot?.partner,
            accentColor = rightColor,
            status = status,
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
        appWidgetManager: AppWidgetManager,
        views: RemoteViews,
        appWidgetId: Int,
        isLeft: Boolean,
        courses: CoupleWidgetDayCourses?,
        accentColor: Int,
        status: CoupleWidgetStatus,
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
        val display = CoupleTimetableDisplayBuilder.build(
            context,
            courses ?: CoupleWidgetDayCourses(emptyList(), emptyList()),
            status = status,
        )

        if (status == CoupleWidgetStatus.OK) {
            views.setTextViewText(footerId, display.footerText)
        }
        display.emptyText?.let { views.setTextViewText(emptyId, it) }
        views.setTextViewTextSize(
            emptyId,
            TypedValue.COMPLEX_UNIT_SP,
            CoupleTimetableDisplayBuilder.HINT_TEXT_SIZE_SP,
        )
        if (display.items.isEmpty()) {
            views.setViewVisibility(listId, View.GONE)
            views.setViewVisibility(emptyId, View.VISIBLE)
            // 高度每次都要下发：桌面（AppWidgetHostView）在布局 id 不变时是
            // 把动作重放到同一个 View 上的，少发一次就会留着上一次的行高。
            val density = context.resources.displayMetrics.density
            CoupleTimetableSizingSupport.applyRowHeight(
                views,
                emptyId,
                CoupleTimetableSizingSupport.emptyRowHeightPx(
                    availableListHeightPx = CoupleTimetableSizingSupport.availableListHeightPx(
                        context,
                        appWidgetManager,
                        appWidgetId,
                    ),
                    courseRowHeightPx = CoupleTimetableSizingSupport.COURSE_ROW_HEIGHT_DP * density,
                    endedNotice = display.emptyEndedNotice,
                ),
            )
            if (status == CoupleWidgetStatus.OK) {
                views.setTextViewText(footerId, display.footerText)
                views.setViewVisibility(footerId, View.VISIBLE)
            } else {
                views.setViewVisibility(footerId, View.GONE)
            }
            return
        }

        views.setViewVisibility(listId, View.VISIBLE)
        views.setViewVisibility(emptyId, View.GONE)
        views.setViewVisibility(footerId, View.VISIBLE)
        val serviceIntent = Intent(context, CoupleTimetableViewsService::class.java).apply {
            putExtra(EXTRA_APP_WIDGET_ID, appWidgetId)
            putExtra(EXTRA_IS_LEFT, isLeft)
            putExtra(EXTRA_ACCENT_COLOR, accentColor)
            data = Uri.parse("qingyu://couple-widget/$appWidgetId/$sidePrefix")
        }
        views.setRemoteAdapter(listId, serviceIntent)
        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, listId)
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

    companion object {
        const val EXTRA_APP_WIDGET_ID = "couple_widget_app_widget_id"
        const val EXTRA_IS_LEFT = "couple_widget_is_left"
        const val EXTRA_ACCENT_COLOR = "couple_widget_accent_color"

        fun updateAll(context: Context) {
            CoupleTimetableWidgetProvider().updateAll(context)
        }

        fun findNextRefreshAtMillis(nowMillis: Long): Long = nowMillis + 60_000L

        fun maleAccentColor(context: Context): Int {
            return ContextCompat.getColor(context, R.color.widget_couple_male_accent)
        }

        fun femaleAccentColor(context: Context): Int {
            return ContextCompat.getColor(context, R.color.widget_couple_female_accent)
        }

        private fun genderAccentColor(context: Context, gender: String?): Int? {
            return when (gender?.trim()?.lowercase()) {
                "male" -> maleAccentColor(context)
                "female" -> femaleAccentColor(context)
                else -> null
            }
        }
    }
}
