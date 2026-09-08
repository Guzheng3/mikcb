package com.mutx163.qingyu

import android.content.Context

/**
 * Re-arm persistent background work after reboot, quick-boot or package
 * replacement. Each feature re-registers its own alarms; these WorkManager
 * calls repair periodic fallbacks after vendor cleanup or an interrupted update.
 */
object AppStartupCoordinator {
    fun rescheduleFallbackWorkers(context: Context) {
        val appContext = context.applicationContext
        LiveUpdateRefreshWorker.ensureScheduled(appContext)
        WidgetRefreshWorker.ensureScheduled(appContext)
    }
}
