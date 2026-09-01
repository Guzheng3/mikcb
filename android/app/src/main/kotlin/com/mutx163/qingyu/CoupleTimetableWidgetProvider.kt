package com.mutx163.qingyu

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

private data class CoupleWidgetCourse(
    val name: String,
    val time: String,
    val location: String,
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
        private const val MY_NAME = "阿屿"
        private const val PARTNER_NAME = "小星"

        private val myCourses = listOf(
            CoupleWidgetCourse("高等数学", "08:00-09:40", "一教C104"),
            CoupleWidgetCourse("大学英语", "10:10-11:45", "二教A205"),
            CoupleWidgetCourse("线性代数", "14:00-15:35", "一教B301"),
        )

        private val partnerCourses = listOf(
            CoupleWidgetCourse("数据结构", "08:00-09:35", "二教B208"),
            CoupleWidgetCourse("现代史", "13:30-15:05", "文科楼303"),
            CoupleWidgetCourse("大学物理", "15:20-16:55", "理科楼106"),
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
            val profile = TodayWidgetSupport.sizeProfile(appWidgetManager, appWidgetId)
            val primaryColor = TodayWidgetSupport.primaryTextColor("solid")
            val secondaryColor = TodayWidgetSupport.secondaryTextColor("solid")

            views.setInt(
                R.id.widget_card,
                "setBackgroundResource",
                TodayWidgetSupport.backgroundRes("solid", TodayWidgetSupport.DEFAULT_CORNER_RADIUS_DP),
            )
            TodayWidgetSupport.applyAdaptiveVerticalPadding(
                views,
                R.id.widget_root,
                profile,
                baseVerticalDp = 8,
                heightAdjustmentDp = 0,
                targetAspect = 2f,
            )

            views.setTextViewText(R.id.widget_couple_left_name, MY_NAME)
            views.setTextViewText(R.id.widget_couple_right_name, PARTNER_NAME)

            bindColumn(
                views,
                myCourses,
                intArrayOf(
                    R.id.widget_couple_left_title_1,
                    R.id.widget_couple_left_title_2,
                    R.id.widget_couple_left_title_3,
                ),
                intArrayOf(
                    R.id.widget_couple_left_meta_1,
                    R.id.widget_couple_left_meta_2,
                    R.id.widget_couple_left_meta_3,
                ),
                primaryColor,
                secondaryColor,
            )
            bindColumn(
                views,
                partnerCourses,
                intArrayOf(
                    R.id.widget_couple_right_title_1,
                    R.id.widget_couple_right_title_2,
                    R.id.widget_couple_right_title_3,
                ),
                intArrayOf(
                    R.id.widget_couple_right_meta_1,
                    R.id.widget_couple_right_meta_2,
                    R.id.widget_couple_right_meta_3,
                ),
                primaryColor,
                secondaryColor,
            )

            val nameSize = if (profile.isShort) 11f else 12f
            val titleSize = if (profile.isShort) 10f else 11f
            val metaSize = if (profile.isShort) 8f else 9f
            TodayWidgetSupport.setTextSizeSp(views, R.id.widget_couple_left_name, nameSize)
            TodayWidgetSupport.setTextSizeSp(views, R.id.widget_couple_right_name, nameSize)
            listOf(
                R.id.widget_couple_left_title_1,
                R.id.widget_couple_left_title_2,
                R.id.widget_couple_left_title_3,
                R.id.widget_couple_right_title_1,
                R.id.widget_couple_right_title_2,
                R.id.widget_couple_right_title_3,
            ).forEach { id -> TodayWidgetSupport.setTextSizeSp(views, id, titleSize) }
            listOf(
                R.id.widget_couple_left_meta_1,
                R.id.widget_couple_left_meta_2,
                R.id.widget_couple_left_meta_3,
                R.id.widget_couple_right_meta_1,
                R.id.widget_couple_right_meta_2,
                R.id.widget_couple_right_meta_3,
            ).forEach { id -> TodayWidgetSupport.setTextSizeSp(views, id, metaSize) }

            val launchIntent = TodayWidgetSupport.buildLaunchPendingIntent(context, appWidgetId)
            views.setOnClickPendingIntent(R.id.widget_couple_left_column, launchIntent)
            views.setOnClickPendingIntent(R.id.widget_couple_right_column, launchIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun bindColumn(
            views: RemoteViews,
            courses: List<CoupleWidgetCourse>,
            titleIds: IntArray,
            metaIds: IntArray,
            primaryColor: Int,
            secondaryColor: Int,
        ) {
            courses.forEachIndexed { index, course ->
                views.setTextViewText(titleIds[index], course.name)
                views.setTextColor(titleIds[index], primaryColor)
                // Keep the default compact time; location is reserved for the
                // real backend, where wider cells can show "time - location".
                views.setTextViewText(metaIds[index], course.time)
                views.setTextColor(metaIds[index], secondaryColor)
            }
        }
    }
}
