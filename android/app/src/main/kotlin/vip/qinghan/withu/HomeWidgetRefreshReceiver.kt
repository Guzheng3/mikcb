package vip.qinghan.withu

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class HomeWidgetRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            // 情侣卡片按分钟推进的专用 tick：只重绘情侣卡片本身，
            // 不再每分钟把所有卡片都全量重建一遍。
            ACTION_COUPLE_REFRESH -> {
                CoupleTimetableWidgetProvider.updateAll(context)
                HomeWidgetStorage.scheduleCoupleRefreshOnly(context)
            }
            AppWidgetManager.ACTION_APPWIDGET_UPDATE,
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED -> {
                // Don't overwrite Flutter-synced snapshot with native-computed data.
                // TodayWidgetSupport.readSnapshot already falls back to native
                // computation when no synced snapshot exists.
                TodayWidgetSupport.updateAll(context)
                StatsWidgetSupport.updateAll(context)
                HomeWidgetStorage.rescheduleRefresh(context)
                AppStartupCoordinator.rescheduleFallbackWorkers(context)
            }
        }
    }

    companion object {
        /** 只刷新情侣卡片的专用 tick（由显式 PendingIntent 投递，不注册到 manifest）。 */
        const val ACTION_COUPLE_REFRESH = "vip.qinghan.withu.ACTION_COUPLE_WIDGET_REFRESH"
    }
}
