package vip.qinghan.withu

import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/**
 * 情侣卡片「今天/明天」两栏课程的原生重算。
 *
 * 卡片此前只读 Flutter 在 App 运行时写入的静态快照（见 [CoupleTimetableStore]），
 * 快照里的 today/tomorrow 是同步那一刻用 `DateTime.now()` 烘焙好的具体课程列表，
 * 因此 App 长期不打开时跨天、跨周、单双周翻转都不会发生，卡片会一直停在
 * 上次同步那天的课程上。
 *
 * 这里按 Dart 侧 `_liveBuildCoupleWidgetSnapshot` 的口径，用同一份课表档案
 * （`flutter.timetable_profiles`）、时间模板（`flutter.time_schemes`）与地点分组
 * （`flutter.location_time_groups`）在原生侧重算当天的课程列表，使卡片不依赖
 * App 进程也能跨天推进。渲染层仍完全复用 [CoupleTimetableDisplayBuilder]，
 * 本文件只负责产出与快照同构的 [CoupleWidgetDayCourses]。
 */

internal data class CoupleNativeSectionTime(
    val startTime: String,
    val endTime: String,
)

internal data class CoupleNativeTimeScheme(
    val id: String,
    val sections: List<CoupleNativeSectionTime>,
)

/** 地点关键字匹配模式，取值与 Dart `LocationKeywordMatchMode.name` 一致。 */
internal enum class CoupleNativeMatchMode {
    PREFIX,
    CONTAINS,
    EXACT;

    companion object {
        fun from(value: String?): CoupleNativeMatchMode = when (value) {
            "contains" -> CONTAINS
            "exact" -> EXACT
            else -> PREFIX
        }
    }
}

internal data class CoupleNativeKeyword(
    val pattern: String,
    val mode: CoupleNativeMatchMode,
)

internal data class CoupleNativeLocationGroup(
    val id: String,
    val name: String,
    val timeSchemeId: String,
    val enabled: Boolean,
    val priority: Int,
    val keywords: List<CoupleNativeKeyword>,
)

internal data class CoupleNativeSettings(
    val activeTimeSchemeId: String?,
    val sections: List<CoupleNativeSectionTime>,
    val semesterStartMillis: Long?,
    val semesterWeekCount: Int,
)

internal data class CoupleNativeCourse(
    val id: String,
    val name: String,
    val shortName: String?,
    val location: String,
    val color: String?,
    val dayOfWeek: Int,
    val startSection: Int,
    val endSection: Int,
    val startTime: String,
    val endTime: String,
    val startWeek: Int,
    val endWeek: Int,
    val isOddWeek: Boolean,
    val isEvenWeek: Boolean,
    val customWeeks: List<Int>?,
    val suspendedWeeks: List<Int>?,
    val timeSchemeIdOverride: String?,
)

internal data class CoupleNativeProfile(
    val id: String,
    val name: String,
    val currentWeek: Int,
    val lastUsedAt: Long,
    val isPartnerImported: Boolean,
    val courses: List<CoupleNativeCourse>,
    val settings: CoupleNativeSettings,
)

internal data class CoupleWidgetRebuiltDays(
    val mine: CoupleWidgetDayCourses,
    val partner: CoupleWidgetDayCourses,
)

internal object CoupleWidgetNativeBuilder {

    /** TA 课表的固定档案 id，与 Dart `PartnerTimetableService.partnerProfileId` 一致。 */
    const val PARTNER_PROFILE_ID = "partner-imported"

    /** 周次偏移上限，与 Dart `CoupleTimetableLogic.min/maxWeekOffset` 一致。 */
    private const val MIN_WEEK_OFFSET = -15
    private const val MAX_WEEK_OFFSET = 15

    private const val MILLIS_PER_DAY = 86_400_000L

    /**
     * 重算双方「今天/明天」四份课程列表。任何一步缺少必要档案都返回 null，
     * 由调用方回落到快照里的存量列表——最坏情况退化成今日行为，不会画出空卡。
     */
    fun rebuild(
        profiles: List<CoupleNativeProfile>,
        activeProfileId: String?,
        schemes: List<CoupleNativeTimeScheme>,
        locationGroups: List<CoupleNativeLocationGroup>,
        partnerProfileId: String?,
        partnerWeekOffset: Int,
        nowMillis: Long,
    ): CoupleWidgetRebuiltDays? {
        val myProfile = resolveMyProfile(profiles, activeProfileId) ?: return null
        val partnerProfile = profiles.firstOrNull {
            it.id == (partnerProfileId ?: PARTNER_PROFILE_ID)
        } ?: return null
        // 昵称回落要查「当前课表」的课程（与 Dart host.resolveCourseShortName 的
        // 遍历范围一致），当前课表缺失时退回我的课表。
        val activeCourses = profiles.firstOrNull { it.id == activeProfileId }?.courses
            ?: myProfile.courses

        val todayStart = dayStartMillis(nowMillis)
        val tomorrowStart = nextDayStartMillis(nowMillis)
        // 伙伴栏的周次基准取「当前课表」的开学时间（Dart 用 host._calculateCalendarWeekForDate），
        // 我的栏则始终按我自己课表的开学时间对齐。
        val hostSettings = profiles.firstOrNull { it.id == activeProfileId }?.settings
            ?: myProfile.settings
        val mySemesterStart = myProfile.settings.semesterStartMillis
        val hostSemesterStart = hostSettings.semesterStartMillis

        fun myWeek(dateMillis: Long): Int = calendarWeekFor(
            dateMillis = dateMillis,
            semesterStartMillis = mySemesterStart,
            fallback = myProfile.currentWeek,
        )

        fun partnerWeek(dateMillis: Long): Int = partnerWeekFor(
            hostWeek = calendarWeekFor(
                dateMillis = dateMillis,
                semesterStartMillis = hostSemesterStart,
                fallback = partnerProfile.currentWeek,
            ),
            weekOffset = partnerWeekOffset,
        )

        return CoupleWidgetRebuiltDays(
            mine = CoupleWidgetDayCourses(
                today = buildDayCourses(
                    myProfile, todayStart, myWeek(todayStart),
                    schemes, locationGroups, activeCourses,
                ),
                tomorrow = buildDayCourses(
                    myProfile, tomorrowStart, myWeek(tomorrowStart),
                    schemes, locationGroups, activeCourses,
                ),
            ),
            partner = CoupleWidgetDayCourses(
                today = buildDayCourses(
                    partnerProfile, todayStart, partnerWeek(todayStart),
                    schemes, locationGroups, activeCourses,
                ),
                tomorrow = buildDayCourses(
                    partnerProfile, tomorrowStart, partnerWeek(tomorrowStart),
                    schemes, locationGroups, activeCourses,
                ),
            ),
        )
    }

    /**
     * 「我的课表」：优先当前激活课表；激活的是 TA 的课表时，取最近使用的
     * 非 TA 课表（与 Dart `myTimetableProfile` 同口径）。
     */
    fun resolveMyProfile(
        profiles: List<CoupleNativeProfile>,
        activeProfileId: String?,
    ): CoupleNativeProfile? {
        val active = profiles.firstOrNull { it.id == activeProfileId }
        if (active != null && !active.isPartnerImported) {
            return active
        }
        return profiles.filter { !it.isPartnerImported }.maxByOrNull { it.lastUsedAt }
    }

    /** 伙伴周次 = 我方周次 + 限幅后的偏移（Dart `partnerWeekForMyWeek`）。 */
    fun partnerWeekFor(hostWeek: Int, weekOffset: Int): Int {
        return hostWeek + weekOffset.coerceIn(MIN_WEEK_OFFSET, MAX_WEEK_OFFSET)
    }

    /**
     * 日历周次，与 Dart `WeekCalculator.calendarWeekForDate` 一致：未配置开学
     * 时间时返回 [fallback]；早于开学日期返回 0（此时任何课程都因 week < startWeek
     * 而不显示）；不做学期周数钳制。
     */
    fun calendarWeekFor(
        dateMillis: Long,
        semesterStartMillis: Long?,
        fallback: Int,
    ): Int {
        if (semesterStartMillis == null || semesterStartMillis <= 0L) {
            return fallback
        }
        // 与 Dart 相同：两端先对齐到周一，再按 UTC 日历日求差，避免夏令时误差。
        val alignedStart = alignedEpochDay(semesterStartMillis)
        val alignedTarget = alignedEpochDay(dateMillis)
        val diffDays = alignedTarget - alignedStart
        if (diffDays < 0) {
            return 0
        }
        return (diffDays / 7).toInt() + 1
    }

    /** 当天本地零点，作为重算结果与缓存的有效期锚点。 */
    fun dayStartMillis(nowMillis: Long): Long {
        return Calendar.getInstance().apply {
            timeInMillis = nowMillis
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
    }

    /**
     * 次日本地零点。按日历日推进再归零，而不是加 24 小时——夏令时切换那天
     * 只有 23 或 25 小时，直接加固定时长会落到当天或第三天。
     */
    fun nextDayStartMillis(nowMillis: Long): Long {
        return Calendar.getInstance().apply {
            timeInMillis = dayStartMillis(nowMillis)
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
    }

    private fun buildDayCourses(
        profile: CoupleNativeProfile,
        dateMillis: Long,
        week: Int,
        schemes: List<CoupleNativeTimeScheme>,
        locationGroups: List<CoupleNativeLocationGroup>,
        activeCourses: List<CoupleNativeCourse>,
    ): List<CoupleWidgetCourse> {
        val weekday = weekdayOf(dateMillis)
        val courses = profile.courses
            .filter { it.dayOfWeek == weekday && isActiveInWeek(it, week) }
            .sortedWith(compareBy({ it.startSection }, { it.startTime }))
        return courses.mapNotNull { course ->
            val sections = resolveSections(course, profile.settings, schemes, locationGroups)
            val startTime = resolveRealTime(course, isStart = true, sections = sections)
            val endTime = resolveRealTime(course, isStart = false, sections = sections)
            if (startTime.isEmpty() || endTime.isEmpty()) {
                return@mapNotNull null
            }
            CoupleWidgetCourse(
                id = course.id,
                name = course.name,
                shortName = resolveShortName(course, activeCourses),
                location = course.location,
                color = course.color,
                startSection = course.startSection,
                endSection = course.endSection,
                startTime = startTime,
                endTime = endTime,
                breaks = buildBreaks(course, sections),
            )
        }
    }

    /** 课程是否在该周生效（Dart `Course.isActiveInWeek`）。 */
    fun isActiveInWeek(course: CoupleNativeCourse, week: Int): Boolean {
        if (course.suspendedWeeks?.contains(week) == true) {
            return false
        }
        // 自定义周次为空列表时视为未使用自定义周次（Dart normalizedCustomWeeks 同语义）。
        val custom = course.customWeeks?.takeIf { it.isNotEmpty() }
        if (custom != null) {
            return custom.contains(week)
        }
        if (week < course.startWeek || week > course.endWeek) {
            return false
        }
        if (course.isOddWeek && week % 2 == 0) {
            return false
        }
        if (course.isEvenWeek && week % 2 != 0) {
            return false
        }
        return true
    }

    /**
     * 生效时间模板的节次表：课程级覆盖 → 地点关键字分组 → 课表默认模板 →
     * [settings] 自带的节次表（Dart `_resolveSectionsForCourse`）。
     */
    fun resolveSections(
        course: CoupleNativeCourse,
        settings: CoupleNativeSettings,
        schemes: List<CoupleNativeTimeScheme>,
        locationGroups: List<CoupleNativeLocationGroup>,
    ): List<CoupleNativeSectionTime> {
        schemeById(schemes, course.timeSchemeIdOverride)?.let { return it.sections }
        val matchedSchemeId = matchLocationSchemeId(course.location, locationGroups)
        schemeById(schemes, matchedSchemeId)?.let { return it.sections }
        schemeById(schemes, settings.activeTimeSchemeId)?.let { return it.sections }
        return settings.sections
    }

    /** 按节次取真实钟点，越界时回落课程存量钟点（Dart `resolveRealTime`）。 */
    fun resolveRealTime(
        course: CoupleNativeCourse,
        isStart: Boolean,
        sections: List<CoupleNativeSectionTime>,
    ): String {
        val index = (if (isStart) course.startSection else course.endSection) - 1
        if (index in sections.indices) {
            val section = sections[index]
            return if (isStart) section.startTime else section.endTime
        }
        return if (isStart) course.startTime else course.endTime
    }

    /**
     * 多节连排课在节间休息处的断点，供进行中课程的进度条打刻痕
     * （Dart `_liveBuildCoupleCoursesForDate` 的 breaks 计算）。
     */
    private fun buildBreaks(
        course: CoupleNativeCourse,
        sections: List<CoupleNativeSectionTime>,
    ): List<CoupleWidgetBreak> {
        val firstIndex = course.startSection - 1
        val lastIndex = course.endSection - 1
        if (firstIndex < 0 || lastIndex <= firstIndex || lastIndex >= sections.size) {
            return emptyList()
        }
        return buildList {
            for (index in firstIndex until lastIndex) {
                val breakStart = sections[index].endTime
                val breakEnd = sections[index + 1].startTime
                if (breakStart.isNotEmpty() && breakEnd.isNotEmpty()) {
                    add(CoupleWidgetBreak(startTime = breakStart, endTime = breakEnd))
                }
            }
        }
    }

    /**
     * 地点关键字 → 时间模板。最长关键字优先，等长时取分组优先级高者，
     * 再按分组名、关键字字面量稳定排序（Dart `LocationTimeMatchLogic.match`）。
     */
    fun matchLocationSchemeId(
        location: String?,
        groups: List<CoupleNativeLocationGroup>,
    ): String? {
        val normalizedLocation = normalizeForMatch(location)
        if (normalizedLocation.isEmpty()) {
            return null
        }
        val candidates = buildList {
            for (group in groups) {
                if (!group.enabled || group.timeSchemeId.isEmpty()) {
                    continue
                }
                for (keyword in group.keywords) {
                    val pattern = normalizeForMatch(keyword.pattern)
                    if (pattern.isEmpty()) {
                        continue
                    }
                    add(LocationCandidate(group, keyword, pattern))
                }
            }
        }
        if (candidates.isEmpty()) {
            return null
        }
        val sorted = candidates.sortedWith(
            compareByDescending<LocationCandidate> { it.normalizedPattern.length }
                .thenByDescending { it.group.priority }
                .thenBy { it.group.name }
                .thenBy { it.keyword.pattern }
        )
        for (candidate in sorted) {
            if (matchesMode(normalizedLocation, candidate.normalizedPattern, candidate.keyword.mode)) {
                return candidate.group.timeSchemeId
            }
        }
        return null
    }

    /**
     * 课程显示短名：课程自带短名优先，否则从「同名课程」里取一个已有的短名
     * （Dart `resolveCourseShortName`，遍历范围是当前课表的课程）。
     */
    private fun resolveShortName(
        course: CoupleNativeCourse,
        activeCourses: List<CoupleNativeCourse>,
    ): String? {
        normalizeShortName(course.shortName)?.let { return it }
        val normalizedName = course.name.trim()
        if (normalizedName.isEmpty()) {
            return null
        }
        for (candidate in activeCourses) {
            if (candidate.id == course.id) {
                continue
            }
            if (candidate.name.trim() != normalizedName) {
                continue
            }
            normalizeShortName(candidate.shortName)?.let { return it }
        }
        return null
    }

    private fun normalizeShortName(value: String?): String? {
        val trimmed = value?.trim().orEmpty()
        return trimmed.takeIf { it.isNotEmpty() }
    }

    private fun schemeById(
        schemes: List<CoupleNativeTimeScheme>,
        id: String?,
    ): CoupleNativeTimeScheme? {
        val target = id?.trim().orEmpty()
        if (target.isEmpty()) {
            return null
        }
        return schemes.firstOrNull { it.id == target }
    }

    private fun matchesMode(
        location: String,
        pattern: String,
        mode: CoupleNativeMatchMode,
    ): Boolean = when (mode) {
        CoupleNativeMatchMode.EXACT -> location == pattern
        CoupleNativeMatchMode.PREFIX -> location.startsWith(pattern)
        CoupleNativeMatchMode.CONTAINS -> location.contains(pattern)
    }

    /** 周一到周日 → 1..7。 */
    private fun weekdayOf(millis: Long): Int {
        val calendarDay = Calendar.getInstance().apply { timeInMillis = millis }
            .get(Calendar.DAY_OF_WEEK)
        return ((calendarDay + 5) % 7) + 1
    }

    /** 本地日历日对齐到周一后的 epoch 天数（周一 00:00 为界，避免时区/夏令时干扰）。 */
    private fun alignedEpochDay(millis: Long): Long {
        val calendar = Calendar.getInstance().apply { timeInMillis = millis }
        val weekdayOffset = (calendar.get(Calendar.DAY_OF_WEEK) + 5) % 7
        return localEpochDay(calendar) - weekdayOffset
    }

    private fun localEpochDay(calendar: Calendar): Long {
        val utc = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            clear()
            set(
                calendar.get(Calendar.YEAR),
                calendar.get(Calendar.MONTH),
                calendar.get(Calendar.DAY_OF_MONTH),
            )
        }
        return utc.timeInMillis / MILLIS_PER_DAY
    }

    /**
     * 地点/关键字的匹配前归一化，逐条对齐 Dart
     * `LocationTimeMatchLogic._normalizeForMatch`：全角转半角、去空白与间隔号、
     * 破折号归一、括号内容展开、转小写。两边不一致会导致地点分组选错时间模板。
     */
    fun normalizeForMatch(text: String?): String {
        val raw = text?.trim().orEmpty()
        if (raw.isEmpty()) {
            return ""
        }
        val buffer = StringBuilder()
        for (char in raw) {
            val unit = char.code
            when {
                unit in 0xFF01..0xFF5E -> buffer.append((unit - 0xFEE0).toChar())
                unit == 0x3000 -> Unit
                unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D -> Unit
                unit == 0x00B7 || unit == 0x30FB || unit == 0x2022 ||
                    unit == 0x2027 || unit == 0x2219 -> Unit
                unit == 0x2014 || unit == 0x2013 || unit == 0xFF0D ->
                    buffer.append('-')
                unit == 0xFF0F -> buffer.append('/')
                else -> buffer.append(char)
            }
        }
        val withoutBrackets = BRACKET_PATTERN.replace(buffer.toString()) { match ->
            match.groupValues[1]
        }
        return withoutBrackets.lowercase(Locale.ROOT)
    }

    private val BRACKET_PATTERN = Regex("[（(]([^）)]{1,12})[）)]")

    private data class LocationCandidate(
        val group: CoupleNativeLocationGroup,
        val keyword: CoupleNativeKeyword,
        val normalizedPattern: String,
    )
}
