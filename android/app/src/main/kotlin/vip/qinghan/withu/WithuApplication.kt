package vip.qinghan.withu

import android.app.Application

class WithuApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        // 金标联盟公平运行内存：进程级动态注册，不依赖 Flutter 引擎是否存活。
        FairMemoryAdapter.initialize(this)
        // 调试版 / 性能版：启动内存会话采样（正式版 no-op）。
        MemoryStatsCollector.initializeIfAllowed(this)

        BeforeClassQuickActionRestore.restoreIfClassEnded(applicationContext)
    }

    override fun onLowMemory() {
        super.onLowMemory()
        MemoryStatsCollector.onSystemLowMemory()
    }
}