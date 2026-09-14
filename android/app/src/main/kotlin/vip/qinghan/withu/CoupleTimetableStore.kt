package vip.qinghan.withu

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
    val color: String? = null,
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

enum class CoupleWidgetStatus {
    OK,
    COUPLE_MODE_OFF,
    NOT_LOGGED_IN;

    companion object {
        fun from(value: String?): CoupleWidgetStatus = when (value) {
            "couple_mode_off" -> COUPLE_MODE_OFF
            "not_logged_in" -> NOT_LOGGED_IN
            else -> OK
        }
    }
}

data class CoupleTimetableWidgetSnapshot(
    val myName: String,
    val partnerName: String,
    val leftColorHex: String?,
    val rightColorHex: String?,
    val status: CoupleWidgetStatus,
    val generatedAtMillis: Long,
    val mine: CoupleWidgetDayCourses,
    val partner: CoupleWidgetDayCourses,
)

object CoupleTimetableStore {
    private const val PREFS_NAME = "couple_widget_prefs"
    private const val KEY_SNAPSHOT_JSON = "snapshot_json"

    const val DEFAULT_MY_NAME = "xoveg"
    const val DEFAULT_PARTNER_NAME = "govex"

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
        val stored = try {
            parseSnapshot(JSONObject(payload))
        } catch (_: Exception) {
            null
        } ?: return null
        // 快照里的 today/tomorrow 是 Flutter 同步那一刻按当时日期烘焙好的具体列表，
        // App 不打开时跨天、跨周都不会翻转。状态/昵称/配色原生无从得知，继续取快照；
        // 只有当天课程按当前日期与周次在原生侧重算。重算不可用（档案缺失或损坏）时
        // 保留快照列表，退化成旧行为，不会画出空卡。
        if (stored.status != CoupleWidgetStatus.OK) {
            return stored
        }
        val rebuilt = CoupleWidgetNativeSource.rebuild(context) ?: return stored
        return stored.copy(mine = rebuilt.mine, partner = rebuilt.partner)
    }

    private fun parseSnapshot(json: JSONObject): CoupleTimetableWidgetSnapshot {
        return CoupleTimetableWidgetSnapshot(
            myName = json.stringOrEmpty("myName"),
            partnerName = json.stringOrEmpty("partnerName"),
            leftColorHex = json.stringOrEmpty("leftColorHex").takeIf { it.isNotBlank() },
            rightColorHex = json.stringOrEmpty("rightColorHex").takeIf { it.isNotBlank() },
            status = CoupleWidgetStatus.from(
                if (json.isNull("status")) null else json.optString("status")
            ),
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
                        id = course.stringOrEmpty("id"),
                        name = course.stringOrEmpty("name"),
                        shortName = course.stringOrEmpty("shortName").takeIf { it.isNotBlank() },
                        location = course.stringOrEmpty("location"),
                        color = course.stringOrEmpty("color").takeIf { it.isNotBlank() },
                        startSection = course.optInt("startSection", 1),
                        endSection = course.optInt("endSection", 1),
                        startTime = course.stringOrEmpty("startTime"),
                        endTime = course.stringOrEmpty("endTime"),
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
                        startTime = item.stringOrEmpty("startTime"),
                        endTime = item.stringOrEmpty("endTime"),
                    )
                )
            }
        }
    }

    // org.json 的 optString 会把 JSON null 强转成字面量 "null"（快照里
    // shortName/location 等可空字段经 MethodChannel 落盘就是 null），必须
    // 先判 isNull 归一成空串，否则「TA 的课」一栏会显示 null。
    private fun JSONObject.stringOrEmpty(key: String): String =
        if (isNull(key)) "" else optString(key)
}
