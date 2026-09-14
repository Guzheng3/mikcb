package vip.qinghan.withu

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/**
 * 供 [CoupleWidgetNativeBuilder] 使用的课表档案读取与解析。
 *
 * 数据全部来自 Flutter 落盘的 `FlutterSharedPreferences`（前缀 `flutter.`），
 * 与今日系列卡片读取当前课表的口径一致——因此不依赖 App 进程存活。
 * 解析结果按「当天零点 + 输入原文」缓存：分钟级 tick 重绘时日期未变即命中，
 * 不会每分钟重新解析整份课表。
 */
internal object CoupleWidgetNativeSource {

    private const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_TIMETABLE_PROFILES = "flutter.timetable_profiles"
    private const val KEY_ACTIVE_PROFILE_ID = "flutter.active_timetable_profile_id"
    private const val KEY_TIME_SCHEMES = "flutter.time_schemes"
    private const val KEY_LOCATION_TIME_GROUPS = "flutter.location_time_groups"
    private const val KEY_PARTNER_BINDING = "flutter.partner_timetable_binding"

    private var cachedDayStart = Long.MIN_VALUE
    private var cachedProfiles: String? = null
    private var cachedSchemes: String? = null
    private var cachedGroups: String? = null
    private var cachedBinding: String? = null
    private var cachedActiveProfileId: String? = null
    private var cachedResult: CoupleWidgetRebuiltDays? = null
    private var cachedResolved = false

    /**
     * 重算当前「今天/明天」两栏课程；档案缺失或解析失败返回 null，
     * 调用方应回落到 Flutter 快照里的存量列表。
     *
     * 调用方可能同时来自主线程（闹钟广播）、WorkManager 工作线程与
     * RemoteViews 的 binder 线程，缓存字段必须串行访问，否则可能读到
     * 「过半更新」的组合（例如日期已换、结果还是上一天的）。
     */
    @Synchronized
    fun rebuild(
        context: Context,
        nowMillis: Long = System.currentTimeMillis(),
    ): CoupleWidgetRebuiltDays? {
        val prefs = context.getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
        val profilesJson = prefs.getString(KEY_TIMETABLE_PROFILES, null) ?: return null
        val schemesJson = prefs.getString(KEY_TIME_SCHEMES, null).orEmpty()
        val groupsJson = prefs.getString(KEY_LOCATION_TIME_GROUPS, null).orEmpty()
        val bindingJson = prefs.getString(KEY_PARTNER_BINDING, null).orEmpty()
        val activeProfileId = prefs.getString(KEY_ACTIVE_PROFILE_ID, null)
        val dayStart = CoupleWidgetNativeBuilder.dayStartMillis(nowMillis)

        val cacheHit = cachedResolved &&
            dayStart == cachedDayStart &&
            profilesJson == cachedProfiles &&
            schemesJson == cachedSchemes &&
            groupsJson == cachedGroups &&
            bindingJson == cachedBinding &&
            activeProfileId == cachedActiveProfileId
        if (cacheHit) {
            return cachedResult
        }

        val result = try {
            build(profilesJson, schemesJson, groupsJson, bindingJson, activeProfileId, nowMillis)
        } catch (_: Exception) {
            // 档案损坏（半写入 / 旧版本结构）时静默回落到快照，绝不因解析失败清空卡片。
            null
        }

        cachedDayStart = dayStart
        cachedProfiles = profilesJson
        cachedSchemes = schemesJson
        cachedGroups = groupsJson
        cachedBinding = bindingJson
        cachedActiveProfileId = activeProfileId
        cachedResult = result
        cachedResolved = true
        return result
    }

    private fun build(
        profilesJson: String,
        schemesJson: String,
        groupsJson: String,
        bindingJson: String,
        activeProfileId: String?,
        nowMillis: Long,
    ): CoupleWidgetRebuiltDays? {
        val profiles = parseProfiles(JSONArray(profilesJson))
        if (profiles.isEmpty()) {
            return null
        }
        val binding = bindingJson.takeIf { it.isNotBlank() }?.let { JSONObject(it) }
        return CoupleWidgetNativeBuilder.rebuild(
            profiles = profiles,
            activeProfileId = activeProfileId,
            schemes = parseSchemes(schemesJson),
            locationGroups = parseLocationGroups(groupsJson),
            partnerProfileId = binding?.stringOrNull("partnerProfileId"),
            partnerWeekOffset = binding?.optInt("weekOffset", 0) ?: 0,
            nowMillis = nowMillis,
        )
    }

    private fun parseProfiles(json: JSONArray): List<CoupleNativeProfile> = buildList {
        for (index in 0 until json.length()) {
            val item = json.optJSONObject(index) ?: continue
            val id = item.optString("id")
            if (id.isBlank()) {
                continue
            }
            add(
                CoupleNativeProfile(
                    id = id,
                    name = item.optString("name"),
                    currentWeek = item.optInt("currentWeek", 1).coerceIn(1, 30),
                    lastUsedAt = parseIsoMillis(item.optString("lastUsedAt")),
                    isPartnerImported = item.optString("profileKind") == "partnerImported",
                    courses = parseCourses(item.optJSONArray("courses")),
                    settings = parseSettings(item.optJSONObject("settings")),
                )
            )
        }
    }

    private fun parseCourses(json: JSONArray?): List<CoupleNativeCourse> {
        if (json == null) {
            return emptyList()
        }
        return buildList {
            for (index in 0 until json.length()) {
                val item = json.optJSONObject(index) ?: continue
                val id = item.optString("id")
                if (id.isBlank()) {
                    continue
                }
                add(
                    CoupleNativeCourse(
                        id = id,
                        name = item.optString("name"),
                        shortName = item.stringOrNull("shortName"),
                        location = item.stringOrNull("location").orEmpty(),
                        color = item.stringOrNull("color"),
                        dayOfWeek = item.optInt("dayOfWeek", 1),
                        startSection = item.optInt("startSection", 1),
                        endSection = item.optInt("endSection", 1),
                        startTime = item.optString("startTime"),
                        endTime = item.optString("endTime"),
                        startWeek = item.optInt("startWeek", 1),
                        endWeek = item.optInt("endWeek", 20),
                        isOddWeek = item.optBoolean("isOddWeek", false),
                        isEvenWeek = item.optBoolean("isEvenWeek", false),
                        customWeeks = item.optJSONArray("customWeeks").toWeekListOrNull(),
                        suspendedWeeks = item.optJSONArray("suspendedWeeks").toWeekListOrNull(),
                        timeSchemeIdOverride = item.stringOrNull("timeSchemeIdOverride"),
                    )
                )
            }
        }
    }

    private fun parseSettings(json: JSONObject?): CoupleNativeSettings {
        if (json == null) {
            return CoupleNativeSettings(
                activeTimeSchemeId = null,
                sections = emptyList(),
                semesterStartMillis = null,
                semesterWeekCount = 20,
            )
        }
        return CoupleNativeSettings(
            activeTimeSchemeId = json.stringOrNull("activeTimeSchemeId"),
            sections = parseSections(json.optJSONArray("sections")),
            semesterStartMillis = if (json.isNull("semesterStartDate")) {
                null
            } else {
                json.optLong("semesterStartDate", 0L).takeIf { it > 0L }
            },
            semesterWeekCount = json.optInt("semesterWeekCount", 20),
        )
    }

    private fun parseSchemes(json: String): List<CoupleNativeTimeScheme> {
        if (json.isBlank()) {
            return emptyList()
        }
        val array = JSONArray(json)
        return buildList {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                val id = item.optString("id")
                if (id.isBlank()) {
                    continue
                }
                add(
                    CoupleNativeTimeScheme(
                        id = id,
                        sections = parseSections(item.optJSONArray("sections")),
                    )
                )
            }
        }
    }

    private fun parseSections(json: JSONArray?): List<CoupleNativeSectionTime> {
        if (json == null) {
            return emptyList()
        }
        return buildList {
            for (index in 0 until json.length()) {
                val item = json.optJSONObject(index) ?: continue
                val startTime = item.optString("startTime")
                val endTime = item.optString("endTime")
                if (startTime.isBlank() || endTime.isBlank()) {
                    continue
                }
                add(CoupleNativeSectionTime(startTime = startTime, endTime = endTime))
            }
        }
    }

    private fun parseLocationGroups(json: String): List<CoupleNativeLocationGroup> {
        if (json.isBlank()) {
            return emptyList()
        }
        val array = JSONArray(json)
        return buildList {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                val id = item.optString("id")
                if (id.isBlank()) {
                    continue
                }
                add(
                    CoupleNativeLocationGroup(
                        id = id,
                        name = item.optString("name"),
                        timeSchemeId = item.optString("timeSchemeId"),
                        enabled = item.optBoolean("enabled", true),
                        priority = item.optInt("priority", 0),
                        keywords = parseKeywords(item.optJSONArray("keywords")),
                    )
                )
            }
        }
    }

    private fun parseKeywords(json: JSONArray?): List<CoupleNativeKeyword> {
        if (json == null) {
            return emptyList()
        }
        return buildList {
            for (index in 0 until json.length()) {
                val item = json.optJSONObject(index) ?: continue
                val pattern = item.optString("pattern").trim()
                if (pattern.isEmpty()) {
                    continue
                }
                add(
                    CoupleNativeKeyword(
                        pattern = pattern,
                        mode = CoupleNativeMatchMode.from(item.stringOrNull("mode")),
                    )
                )
            }
        }
    }

    private fun JSONArray?.toWeekListOrNull(): List<Int>? {
        val array = this ?: return null
        if (array.length() == 0) {
            return null
        }
        return buildList {
            for (index in 0 until array.length()) {
                add(array.optInt(index, 0))
            }
        }
    }

    /**
     * Flutter 的 `toIso8601String()` 本地时间不带时区后缀、且可能带微秒，
     * 这里只取到秒。该字段仅用于「最近使用」排序，同级误差不影响结果。
     */
    private fun parseIsoMillis(value: String?): Long {
        val raw = value?.trim().orEmpty()
        if (raw.length < 19) {
            return 0L
        }
        return try {
            val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).apply {
                timeZone = TimeZone.getDefault()
                isLenient = true
            }
            formatter.parse(raw.substring(0, 19))?.time ?: 0L
        } catch (_: Exception) {
            0L
        }
    }

    /** org.json 会把 JSON null 强转成字面量 "null"，必须先判 isNull 再取串。 */
    private fun JSONObject.stringOrNull(key: String): String? {
        if (isNull(key)) {
            return null
        }
        return optString(key).takeIf { it.isNotBlank() }
    }
}
