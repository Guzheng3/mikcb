package vip.qinghan.withu

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * WorkManager-based backup for widget refresh.
 *
 * On MIUI/HyperOS, AlarmManager.setExactAndAllowWhileIdle() may be
 * suppressed by the ROM, which breaks the primary widget refresh
 * mechanism (HomeWidgetRefreshReceiver).
 *
 * This worker runs every 15 minutes (WorkManager minimum) and triggers
 * a widget update + reschedule, ensuring the widget stays fresh even
 * when AlarmManager alarms are suppressed.
 */
class WidgetRefreshWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        // 卡片已被全部移除：停掉周期任务，避免每 15 分钟空转唤醒。
        if (!TodayWidgetSupport.hasAnyWidget(applicationContext)) {
            cancel(applicationContext)
            return Result.success()
        }
        return try {
            TodayWidgetSupport.updateAll(applicationContext)
            StatsWidgetSupport.updateAll(applicationContext)
            HomeWidgetStorage.rescheduleRefresh(applicationContext)
            Result.success()
        } catch (e: Exception) {
            Log.w(TAG, DiagnosticLogMessages.LOG_WIDGET_REFRESH_WORKER_FAILED, e)
            Result.retry()
        }
    }

    companion object {
        private const val TAG = "WidgetRefreshWorker"
        private const val WORK_NAME = "home_widget_periodic_refresh"

        /**
         * Enqueue a periodic widget refresh.
         * Uses UPDATE policy so constraint/config changes propagate.
         */
        fun ensureScheduled(context: Context) {
            // 零卡片时不需要周期兜底，顺手把已排的取消掉。
            if (!TodayWidgetSupport.hasAnyWidget(context)) {
                cancel(context)
                return
            }
            val request = PeriodicWorkRequestBuilder<WidgetRefreshWorker>(
                15, TimeUnit.MINUTES,
            ).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request,
            )
        }

        /**
         * Cancel the periodic refresh (e.g. when widget is removed).
         */
        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }
    }
}
