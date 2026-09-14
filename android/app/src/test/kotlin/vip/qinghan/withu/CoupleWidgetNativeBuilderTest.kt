package vip.qinghan.withu

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import java.util.Calendar
import java.util.TimeZone

/**
 * 情侣卡片原生重算的口径测试：全部按 Dart 侧 `_liveBuildCoupleWidgetSnapshot`
 * 与 `LocationTimeMatchLogic` / `Course.isInWeek` 的行为对齐。
 *
 * 日期基于 Calendar（本地时区），固定 UTC 保证任意机器上结果一致。
 * 2026-09-14 是周一，2026-08-31 是第 1 周周一，故 09-14 落在第 3 周。
 */
class CoupleWidgetNativeBuilderTest {

    companion object {
        @BeforeClass
        @JvmStatic
        fun setUpTimeZone() {
            TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
        }
    }

    private val semesterStart = millis(2026, 8, 31)
    private val mondayOfWeek3 = millis(2026, 9, 14)

    // ---------- 跨天与周次 ----------

    @Test
    fun rebuild_splitsTodayAndTomorrow_byWeekday_andResolvesSectionTimes() {
        val mine = profile(
            id = "mine",
            courses = listOf(
                course(id = "mon", dayOfWeek = 1, startSection = 1, endSection = 2),
                course(id = "tue", dayOfWeek = 2, startSection = 3, endSection = 3),
            ),
        )

        val result = rebuild(mine = mine, partnerCourses = emptyList())

        // 今天（周一）只出周一的课，明天（周二）只出周二的课。
        assertEquals(listOf("mon"), result.mine.today.map { it.id })
        assertEquals(listOf("tue"), result.mine.tomorrow.map { it.id })
        // 钟点取解析出的节次表，而不是课程存量值。
        assertEquals("08:00", result.mine.today.single().startTime)
        assertEquals("09:40", result.mine.today.single().endTime)
        assertEquals("10:00", result.mine.tomorrow.single().startTime)
    }

    @Test
    fun rebuild_advancesWeekAcrossDays() {
        val mine = profile(
            id = "mine",
            courses = listOf(
                course(id = "w3", dayOfWeek = 1, startWeek = 3, endWeek = 3),
                course(id = "w4", dayOfWeek = 1, startWeek = 4, endWeek = 4),
            ),
        )

        // 同一张卡片：第 3 周周一显示 w3，下一周自动换成 w4——这正是
        // App 不打开时此前永远不会发生的事。
        assertEquals(
            listOf("w3"),
            rebuild(mine, emptyList(), now = mondayOfWeek3).mine.today.map { it.id },
        )
        assertEquals(
            listOf("w4"),
            rebuild(mine, emptyList(), now = millis(2026, 9, 21)).mine.today.map { it.id },
        )
        assertTrue(rebuild(mine, emptyList(), now = millis(2026, 9, 28)).mine.today.isEmpty())
    }

    @Test
    fun rebuild_appliesOddEvenWeekFilter() {
        val mine = profile(
            id = "mine",
            courses = listOf(
                course(id = "odd", dayOfWeek = 1, isOddWeek = true),
                course(id = "even", dayOfWeek = 1, isEvenWeek = true),
            ),
        )

        val week3 = rebuild(mine, emptyList(), now = mondayOfWeek3).mine.today
        assertEquals(listOf("odd"), week3.map { it.id })

        val week4 = rebuild(mine, emptyList(), now = millis(2026, 9, 21)).mine.today
        assertEquals(listOf("even"), week4.map { it.id })
    }

    @Test
    fun rebuild_skipsSuspendedWeek() {
        val mine = profile(
            id = "mine",
            courses = listOf(course(id = "c", dayOfWeek = 1, suspendedWeeks = listOf(3))),
        )

        assertTrue(rebuild(mine, emptyList(), now = mondayOfWeek3).mine.today.isEmpty())
        assertEquals(1, rebuild(mine, emptyList(), now = millis(2026, 9, 21)).mine.today.size)
    }

    @Test
    fun customWeeks_takePrecedence_andEmptyListFallsBackToRange() {
        val custom = profile(
            id = "mine",
            courses = listOf(
                course(
                    id = "custom",
                    dayOfWeek = 1,
                    startWeek = 1,
                    endWeek = 20,
                    customWeeks = listOf(5),
                ),
            ),
        )
        assertTrue(rebuild(custom, emptyList(), now = mondayOfWeek3).mine.today.isEmpty())
        assertEquals(
            1,
            rebuild(custom, emptyList(), now = millis(2026, 9, 28)).mine.today.size,
        )

        // 空列表等于未设置自定义周次，回落 startWeek/endWeek 区间。
        val emptyCustom = profile(
            id = "mine",
            courses = listOf(
                course(id = "c", dayOfWeek = 1, startWeek = 3, endWeek = 3, customWeeks = emptyList()),
            ),
        )
        assertEquals(1, rebuild(emptyCustom, emptyList(), now = mondayOfWeek3).mine.today.size)
    }

    @Test
    fun rebuild_sortsByStartSection() {
        val mine = profile(
            id = "mine",
            courses = listOf(
                course(id = "third", dayOfWeek = 1, startSection = 5),
                course(id = "first", dayOfWeek = 1, startSection = 1),
                course(id = "second", dayOfWeek = 1, startSection = 3),
            ),
        )

        assertEquals(
            listOf("first", "second", "third"),
            rebuild(mine, emptyList(), now = mondayOfWeek3).mine.today.map { it.id },
        )
    }

    // ---------- 周次计算 ----------

    @Test
    fun calendarWeekFor_countsFromSemesterStartMonday() {
        assertEquals(1, CoupleWidgetNativeBuilder.calendarWeekFor(semesterStart, semesterStart, 1))
        assertEquals(
            3,
            CoupleWidgetNativeBuilder.calendarWeekFor(mondayOfWeek3, semesterStart, 1),
        )
        // 同一周内的周日仍是第 3 周。
        assertEquals(
            3,
            CoupleWidgetNativeBuilder.calendarWeekFor(millis(2026, 9, 20), semesterStart, 1),
        )
    }

    @Test
    fun calendarWeekFor_returnsZeroBeforeSemesterStart_andFallbackWithoutStart() {
        assertEquals(0, CoupleWidgetNativeBuilder.calendarWeekFor(millis(2026, 8, 24), semesterStart, 1))
        assertEquals(7, CoupleWidgetNativeBuilder.calendarWeekFor(mondayOfWeek3, null, 7))
        // 未配置开学时间落盘为 0，与 null 同义，取 fallback。
        assertEquals(7, CoupleWidgetNativeBuilder.calendarWeekFor(mondayOfWeek3, 0L, 7))
    }

    @Test
    fun nextDayStartMillis_advancesOneCalendarDayAcrossDstFallBack() {
        val original = TimeZone.getDefault()
        try {
            // 2026-11-01（周日）是北美夏令时回拨日，当天有 25 小时：
            // 直接加 24 小时会退回当天，「明天」的课就永远出不来。
            TimeZone.setDefault(TimeZone.getTimeZone("America/New_York"))
            val sundayNoon = millis(2026, 11, 1, 12, 0)

            val tomorrow = CoupleWidgetNativeBuilder.nextDayStartMillis(sundayNoon)
            val calendar = Calendar.getInstance().apply { timeInMillis = tomorrow }
            assertEquals(11, calendar.get(Calendar.MONTH) + 1)
            assertEquals(2, calendar.get(Calendar.DAY_OF_MONTH))
            assertEquals(0, calendar.get(Calendar.HOUR_OF_DAY))

            // 端到端：周一的课必须落在「明天」栏。
            val result = rebuild(
                mine = profile(id = "mine", courses = listOf(course(id = "mon", dayOfWeek = 1))),
                partnerCourses = emptyList(),
                now = sundayNoon,
            )
            assertTrue(result.mine.today.isEmpty())
            assertEquals(listOf("mon"), result.mine.tomorrow.map { it.id })
        } finally {
            TimeZone.setDefault(original)
        }
    }

    @Test
    fun partnerWeekFor_clampsOffset() {
        assertEquals(5, CoupleWidgetNativeBuilder.partnerWeekFor(3, 2))
        // 偏移限幅到 ±15。
        assertEquals(18, CoupleWidgetNativeBuilder.partnerWeekFor(3, 99))
        assertEquals(0, CoupleWidgetNativeBuilder.partnerWeekFor(15, -99))
    }

    @Test
    fun rebuild_appliesPartnerWeekOffsetToPartnerColumnOnly() {
        val mine = profile(id = "mine", courses = listOf(course(id = "mineW3", dayOfWeek = 1)))
        val partnerCourses = listOf(
            course(id = "partnerW3", dayOfWeek = 1, startWeek = 3, endWeek = 3),
            course(id = "partnerW5", dayOfWeek = 1, startWeek = 5, endWeek = 5),
        )

        val result = rebuild(
            mine = mine,
            partnerCourses = partnerCourses,
            partnerWeekOffset = 2,
            now = mondayOfWeek3,
        )

        // 我方第 3 周；TA 栏按 +2 偏移取第 5 周，故只有 partnerW5 出现。
        assertEquals(listOf("mineW3"), result.mine.today.map { it.id })
        assertEquals(listOf("partnerW5"), result.partner.today.map { it.id })
    }

    // ---------- 时间模板与地点分组 ----------

    @Test
    fun resolveSections_followsOverrideThenLocationThenActiveSchemeThenSettings() {
        val settings = CoupleNativeSettings(
            activeTimeSchemeId = "active",
            sections = listOf(section("11:00", "11:45")),
            semesterStartMillis = semesterStart,
            semesterWeekCount = 20,
        )
        val schemes = listOf(
            CoupleNativeTimeScheme("override", listOf(section("07:00", "07:45"))),
            CoupleNativeTimeScheme("location", listOf(section("09:00", "09:45"))),
            CoupleNativeTimeScheme("active", listOf(section("10:00", "10:45"))),
        )
        val groups = listOf(
            CoupleNativeLocationGroup(
                id = "g",
                name = "主楼",
                timeSchemeId = "location",
                enabled = true,
                priority = 0,
                keywords = listOf(CoupleNativeKeyword("A主", CoupleNativeMatchMode.PREFIX)),
            ),
        )

        // 课程级覆盖最优先。
        assertEquals(
            "07:00",
            CoupleWidgetNativeBuilder.resolveSections(
                course(id = "a", timeSchemeIdOverride = "override", location = "A主101"),
                settings, schemes, groups,
            ).first().startTime,
        )
        // 无覆盖时地点分组命中。
        assertEquals(
            "09:00",
            CoupleWidgetNativeBuilder.resolveSections(
                course(id = "b", location = "A主101"),
                settings, schemes, groups,
            ).first().startTime,
        )
        // 地点未命中时用课表默认模板，而不是 settings.sections。
        assertEquals(
            "10:00",
            CoupleWidgetNativeBuilder.resolveSections(
                course(id = "c", location = "B楼202"),
                settings, schemes, groups,
            ).first().startTime,
        )
        // 默认模板不存在时回落 settings.sections。
        assertEquals(
            "11:00",
            CoupleWidgetNativeBuilder.resolveSections(
                course(id = "d", location = "B楼202"),
                settings.copy(activeTimeSchemeId = "missing"), schemes, groups,
            ).first().startTime,
        )
    }

    @Test
    fun matchLocationSchemeId_prefersLongestKeyword_thenPriority() {
        val groups = listOf(
            CoupleNativeLocationGroup(
                id = "short",
                name = "A",
                timeSchemeId = "shortScheme",
                enabled = true,
                priority = 9,
                keywords = listOf(CoupleNativeKeyword("A", CoupleNativeMatchMode.PREFIX)),
            ),
            CoupleNativeLocationGroup(
                id = "long",
                name = "B",
                timeSchemeId = "longScheme",
                enabled = true,
                priority = 0,
                keywords = listOf(CoupleNativeKeyword("A主", CoupleNativeMatchMode.PREFIX)),
            ),
        )

        // 更长关键字优先，即便对方分组优先级更高。
        assertEquals(
            "longScheme",
            CoupleWidgetNativeBuilder.matchLocationSchemeId("A主101", groups),
        )

        val samePattern = listOf(
            groups[0].copy(id = "low", timeSchemeId = "lowScheme", priority = 1),
            groups[1].copy(id = "high", timeSchemeId = "highScheme", priority = 5),
        )
        // 等长时取优先级高者。
        assertEquals(
            "highScheme",
            CoupleWidgetNativeBuilder.matchLocationSchemeId("A主101", samePattern),
        )
    }

    @Test
    fun matchLocationSchemeId_honorsModeAndNormalization() {
        val groups = listOf(
            CoupleNativeLocationGroup(
                id = "g",
                name = "主楼",
                timeSchemeId = "scheme",
                enabled = true,
                priority = 0,
                keywords = listOf(CoupleNativeKeyword("测试教室", CoupleNativeMatchMode.CONTAINS)),
            ),
        )

        // 全角空格与空格归一化后仍能命中。
        assertEquals(
            "scheme",
            CoupleWidgetNativeBuilder.matchLocationSchemeId("测试 教室 01", groups),
        )
        assertEquals(
            "scheme",
            CoupleWidgetNativeBuilder.matchLocationSchemeId("测试教室\u300001", groups),
        )
        assertNull(CoupleWidgetNativeBuilder.matchLocationSchemeId("", groups))
        // 分组被停用时不参与匹配。
        assertNull(
            CoupleWidgetNativeBuilder.matchLocationSchemeId(
                "测试教室01",
                listOf(groups.first().copy(enabled = false)),
            ),
        )
    }

    @Test
    fun resolveRealTime_fallsBackToStoredTime_whenSectionOutOfRange() {
        val sections = listOf(section("08:00", "08:45"))
        val beyond = course(
            id = "phantom",
            dayOfWeek = 1,
            startSection = 9,
            endSection = 9,
            startTime = "18:00",
            endTime = "18:45",
        )

        assertEquals("18:00", CoupleWidgetNativeBuilder.resolveRealTime(beyond, true, sections))
        assertEquals("18:45", CoupleWidgetNativeBuilder.resolveRealTime(beyond, false, sections))
        // 节次越界时课程仍保留，钟点回落存量值，而不是被丢弃。
        val built = rebuild(profile(id = "mine", courses = listOf(beyond)), emptyList(), now = mondayOfWeek3)
            .mine.today.single()
        assertEquals("18:00", built.startTime)
        assertEquals("18:45", built.endTime)
    }

    @Test
    fun rebuild_buildsBreakMarkersForMultiSectionCourses() {
        val mine = profile(
            id = "mine",
            courses = listOf(course(id = "three", dayOfWeek = 1, startSection = 1, endSection = 3)),
        )

        val built = rebuild(mine, emptyList(), now = mondayOfWeek3).mine.today.single()

        assertEquals("08:00", built.startTime)
        assertEquals("10:45", built.endTime)
        assertEquals(
            listOf(CoupleWidgetBreak("08:45", "08:55"), CoupleWidgetBreak("09:40", "10:00")),
            built.breaks,
        )
    }

    // ---------- 档案解析 ----------

    @Test
    fun resolveMyProfile_skipsPartnerProfileWhenPartnerIsActive() {
        val older = profile(id = "mine-old", courses = emptyList(), lastUsedAt = millis(2026, 9, 1))
        val newer = profile(id = "mine-new", courses = emptyList(), lastUsedAt = millis(2026, 9, 10))
        val partner = profile(
            id = CoupleWidgetNativeBuilder.PARTNER_PROFILE_ID,
            courses = emptyList(),
            isPartnerImported = true,
            lastUsedAt = millis(2026, 9, 12),
        )
        val profiles = listOf(older, newer, partner)

        // 激活的是自己的课表时直接用激活项。
        assertEquals("mine-old", resolveMyProfile(profiles, "mine-old")?.id)
        // 激活的是 TA 课表（或没有激活项）时退到最近使用的非 TA 课表。
        assertEquals(
            "mine-new",
            resolveMyProfile(profiles, CoupleWidgetNativeBuilder.PARTNER_PROFILE_ID)?.id,
        )
        assertEquals("mine-new", resolveMyProfile(profiles, null)?.id)
    }

    @Test
    fun rebuild_resolvesShortNameFromSameNamedCourse() {
        val mine = profile(
            id = "mine",
            courses = listOf(
                course(id = "lecture", dayOfWeek = 1, name = "高等数学", shortName = null),
                course(id = "other", dayOfWeek = 3, name = "高等数学", shortName = "高数"),
            ),
        )

        val built = rebuild(mine, emptyList(), now = mondayOfWeek3).mine.today.single()

        assertEquals("高数", built.shortName)
    }

    @Test
    fun rebuild_returnsNull_whenPartnerProfileMissing() {
        val mine = profile(id = "mine", courses = listOf(course(id = "c", dayOfWeek = 1)))

        assertNull(
            CoupleWidgetNativeBuilder.rebuild(
                profiles = listOf(mine),
                activeProfileId = "mine",
                schemes = emptyList(),
                locationGroups = emptyList(),
                partnerProfileId = CoupleWidgetNativeBuilder.PARTNER_PROFILE_ID,
                partnerWeekOffset = 0,
                nowMillis = mondayOfWeek3,
            ),
        )
    }

    // ---------- 测试夹具 ----------

    private fun rebuild(
        mine: CoupleNativeProfile,
        partnerCourses: List<CoupleNativeCourse>,
        partnerWeekOffset: Int = 0,
        now: Long = mondayOfWeek3,
    ): CoupleWidgetRebuiltDays {
        val partner = profile(
            id = CoupleWidgetNativeBuilder.PARTNER_PROFILE_ID,
            courses = partnerCourses,
            isPartnerImported = true,
        )
        return requireNotNull(
            CoupleWidgetNativeBuilder.rebuild(
                profiles = listOf(mine, partner),
                activeProfileId = mine.id,
                schemes = emptyList(),
                locationGroups = emptyList(),
                partnerProfileId = CoupleWidgetNativeBuilder.PARTNER_PROFILE_ID,
                partnerWeekOffset = partnerWeekOffset,
                nowMillis = now,
            ),
        )
    }

    private fun resolveMyProfile(
        profiles: List<CoupleNativeProfile>,
        activeProfileId: String?,
    ): CoupleNativeProfile? = CoupleWidgetNativeBuilder.resolveMyProfile(profiles, activeProfileId)

    private val defaultSections = listOf(
        section("08:00", "08:45"),
        section("08:55", "09:40"),
        section("10:00", "10:45"),
        section("10:55", "11:40"),
    )

    private fun section(start: String, end: String) = CoupleNativeSectionTime(start, end)

    private fun profile(
        id: String,
        courses: List<CoupleNativeCourse>,
        isPartnerImported: Boolean = false,
        lastUsedAt: Long = millis(2026, 9, 1),
    ) = CoupleNativeProfile(
        id = id,
        name = id,
        currentWeek = 1,
        lastUsedAt = lastUsedAt,
        isPartnerImported = isPartnerImported,
        courses = courses,
        settings = CoupleNativeSettings(
            activeTimeSchemeId = null,
            sections = defaultSections,
            semesterStartMillis = semesterStart,
            semesterWeekCount = 20,
        ),
    )

    private fun course(
        id: String,
        name: String = id,
        shortName: String? = null,
        location: String = "",
        dayOfWeek: Int = 1,
        startSection: Int = 1,
        endSection: Int = 1,
        startTime: String = "00:00",
        endTime: String = "00:00",
        startWeek: Int = 1,
        endWeek: Int = 20,
        isOddWeek: Boolean = false,
        isEvenWeek: Boolean = false,
        customWeeks: List<Int>? = null,
        suspendedWeeks: List<Int>? = null,
        timeSchemeIdOverride: String? = null,
    ) = CoupleNativeCourse(
        id = id,
        name = name,
        shortName = shortName,
        location = location,
        color = null,
        dayOfWeek = dayOfWeek,
        startSection = startSection,
        endSection = endSection,
        startTime = startTime,
        endTime = endTime,
        startWeek = startWeek,
        endWeek = endWeek,
        isOddWeek = isOddWeek,
        isEvenWeek = isEvenWeek,
        customWeeks = customWeeks,
        suspendedWeeks = suspendedWeeks,
        timeSchemeIdOverride = timeSchemeIdOverride,
    )

    private fun millis(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
    ): Long = Calendar.getInstance().apply {
        clear()
        set(year, month - 1, day, hour, minute, 0)
    }.timeInMillis
}
