package com.mutx163.qingyu

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class CoupleWidgetBreak(
    val startTime: String,
    val endTime: String,
)

data class CoupleWidgetCourse(
    val id: String,
    val name: String,
    val shortName: String?,
    val location: String,
    val startSection: Int,
    val endSection: Int,
    val startTime: String,
    val endTime: String,
    val breaks: List<CoupleWidgetBreak> = emptyList(),
)

data class CoupleWidgetDayCourses(
    val today: List<CoupleWidgetCourse>,
    val tomorrow: List<CoupleWidgetCourse>,
)

data class CoupleTimetableWidgetSnapshot(
    val myName: String,
    val partnerName: String,
    val leftColorHex: String?,
    val rightColorHex: String?,
    val generatedAtMillis: Long,
    val mine: CoupleWidgetDayCourses,
    val partner: CoupleWidgetDayCourses,
)

object CoupleTimetableStore {
    private const val PREFS_NAME = "couple_widget_prefs"
    private const val KEY_SNAPSHOT_JSON = "snapshot_json"

    fun syncSnapshot(context: Context, snapshot: Map<String, Any?>) {
        val payload = JSONObject(snapshot).toString()
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_SNAPSHOT_JSON, payload)
            .apply()
        TodayWidgetSupport.updateAll(context)
        HomeWidgetStorage.rescheduleRefresh(context)
        WidgetRefreshWorker.ensureScheduled(context)
    }

    fun clearSnapshot(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_SNAPSHOT_JSON)
            .apply()
        TodayWidgetSupport.updateAll(context)
        HomeWidgetStorage.rescheduleRefresh(context)
    }

    fun readSnapshot(context: Context): CoupleTimetableWidgetSnapshot? {
        val payload = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_SNAPSHOT_JSON, null) ?: return null
        return try {
            parseSnapshot(JSONObject(payload))
        } catch (_: Exception) {
            null
        }
    }

    private fun parseSnapshot(json: JSONObject): CoupleTimetableWidgetSnapshot {
        return CoupleTimetableWidgetSnapshot(
            myName = json.optString("myName"),
            partnerName = json.optString("partnerName"),
            leftColorHex = json.optString("leftColorHex").takeIf { it.isNotBlank() },
            rightColorHex = json.optString("rightColorHex").takeIf { it.isNotBlank() },
            generatedAtMillis = json.optLong("generatedAtMillis"),
            mine = parseDayCourses(json.optJSONObject("mine")),
            partner = parseDayCourses(json.optJSONObject("partner")),
        )
    }

    private fun parseDayCourses(json: JSONObject?): CoupleWidgetDayCourses {
        if (json == null) return CoupleWidgetDayCourses(emptyList(), emptyList())
        return CoupleWidgetDayCourses(
            today = parseCourses(json.optJSONArray("today")),
            tomorrow = parseCourses(json.optJSONArray("tomorrow")),
        )
    }

    private fun parseCourses(json: JSONArray?): List<CoupleWidgetCourse> {
        if (json == null) return emptyList()
        return buildList {
            for (index in 0 until json.length()) {
                val course = json.optJSONObject(index) ?: continue
                add(
                    CoupleWidgetCourse(
                        id = course.optString("id"),
                        name = course.optString("name"),
                        shortName = course.optString("shortName").takeIf { it.isNotBlank() },
                        location = course.optString("location"),
                        startSection = course.optInt("startSection", 1),
                        endSection = course.optInt("endSection", 1),
                        startTime = course.optString("startTime"),
                        endTime = course.optString("endTime"),
                        breaks = parseBreaks(course.optJSONArray("breaks")),
                    )
                )
            }
        }
    }

    private fun parseBreaks(json: JSONArray?): List<CoupleWidgetBreak> {
        if (json == null) return emptyList()
        return buildList {
            for (index in 0 until json.length()) {
                val item = json.optJSONObject(index) ?: continue
                add(
                    CoupleWidgetBreak(
                        startTime = item.optString("startTime"),
                        endTime = item.optString("endTime"),
                    )
                )
            }
        }
    }
}
