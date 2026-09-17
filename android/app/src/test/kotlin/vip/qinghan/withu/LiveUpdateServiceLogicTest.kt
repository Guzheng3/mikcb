package vip.qinghan.withu

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveUpdateServiceLogicTest {
    @Test
    fun beforeClassQuickActionRestoresAfterClassEndWhenDue() {
        assertTrue(
            beforeClassQuickActionShouldRestoreAfterClassEnd(
                nowMillis = 1_700_000_000_000L,
                restoreAtMillis = 1_699_999_000_000L,
            )
        )
    }

    @Test
    fun beforeClassQuickActionDoesNotRestoreBeforeClassEnd() {
        assertFalse(
            beforeClassQuickActionShouldRestoreAfterClassEnd(
                nowMillis = 1_699_999_000_000L,
                restoreAtMillis = 1_700_000_000_000L,
            )
        )
    }

    @Test
    fun promotedApi36PlusDoesNotMirrorStatusIntoMiuiFocusHint() {
        assertFalse(
            liveShouldMirrorStatusIntoMiuiFocusHint(
                sdkInt = 36,
                shouldPromote = true,
            )
        )
    }

    @Test
    fun nonPromotedOrOlderBuildsKeepMiuiFocusHint() {
        assertTrue(
            liveShouldMirrorStatusIntoMiuiFocusHint(
                sdkInt = 35,
                shouldPromote = true,
            )
        )
        assertTrue(
            liveShouldMirrorStatusIntoMiuiFocusHint(
                sdkInt = 36,
                shouldPromote = false,
            )
        )
    }

    @Test
    fun quickActionButtonsNoneShowsNothing() {
        assertEquals(
            BeforeClassQuickActionButtons(),
            beforeClassQuickActionButtons(
                action = "none",
                silentCurrentlyActive = true,
                dndCurrentlyActive = true,
            ),
        )
    }

    @Test
    fun quickActionButtonsFlipToCancelWhenModeAlreadyActive() {
        // 静音未开 → 打开静音；已开 → 取消静音
        assertTrue(
            beforeClassQuickActionButtons(
                action = "silent",
                silentCurrentlyActive = false,
                dndCurrentlyActive = false,
            ).silentEnable
        )
        val active = beforeClassQuickActionButtons(
            action = "silent",
            silentCurrentlyActive = true,
            dndCurrentlyActive = false,
        )
        assertTrue(active.silentCancel)
        assertFalse(active.silentEnable)
        assertFalse(active.dndEnable)
        assertFalse(active.dndCancel)
    }

    @Test
    fun quickActionButtonsBothShowsIndependentToggles() {
        // both：静音已被（自动）打开，勿扰未开 → 一个取消按钮 + 一个打开按钮
        val mixed = beforeClassQuickActionButtons(
            action = "both",
            silentCurrentlyActive = true,
            dndCurrentlyActive = false,
        )
        assertTrue(mixed.silentCancel)
        assertFalse(mixed.silentEnable)
        assertTrue(mixed.dndEnable)
        assertFalse(mixed.dndCancel)

        val allActive = beforeClassQuickActionButtons(
            action = "both",
            silentCurrentlyActive = true,
            dndCurrentlyActive = true,
        )
        assertTrue(allActive.silentCancel)
        assertTrue(allActive.dndCancel)
        assertFalse(allActive.silentEnable)
        assertFalse(allActive.dndEnable)
    }

    @Test
    fun quickActionButtonsSignatureTracksStateFlip() {
        val inactive = beforeClassQuickActionButtons(
            action = "do_not_disturb",
            silentCurrentlyActive = false,
            dndCurrentlyActive = false,
        ).toString()
        val active = beforeClassQuickActionButtons(
            action = "do_not_disturb",
            silentCurrentlyActive = false,
            dndCurrentlyActive = true,
        ).toString()
        assertTrue(inactive != active)
    }

    @Test
    fun promotionFramesStayUncolorizedAfterColorOsRegression() {
        // 2026-09-11 实机回归（OPPO PLA110 / ColorOS 16.1 / Android 16）：
        // 置 true 后 hasPromotableCharacteristics() 反而返回 false，流体云彻底
        // 不出卡片；而同机 v5.2.0.1（恒 false）可正常上岛。以官方文档
        // “Must NOT setColorized to TRUE” 为准，提升帧与非提升帧一律保持 false。
        assertFalse(liveShouldRequestColorizedForPromotion(shouldPromote = true))
        assertFalse(liveShouldRequestColorizedForPromotion(shouldPromote = false))
    }

    @Test
    fun promotionIsRestrictedToBeforeClassStage() {
        // 产品决定：只有上课前上岛；课中与临近下课改走普通通知。
        assertTrue(liveShouldPromoteStage("beforeClass"))
        assertFalse(liveShouldPromoteStage("duringClass"))
        assertFalse(liveShouldPromoteStage("duringClassStatusBar"))
        assertFalse(liveShouldPromoteStage("beforeEnd"))
    }

    @Test
    fun islandLineTruncatesByDisplayWidthWithoutEllipsis() {
        // 汉字按 2 个单位计：16 个单位的额度只装得下 8 个汉字，且**不补省略号**
        // （系统的「…」由它自己加，截点不可控，所以我们先截）。
        // 8 个汉字 = 16 单位，刚好装满 → 原样返回
        assertEquals("中学生物学教学论", truncateIslandLine("中学生物学教学论"))
        // 第 9 个汉字放不下 → 硬截到 8 个，不补省略号
        assertEquals(
            "中学生物学教学论",
            truncateIslandLine("中学生物学教学论超长名字"),
        )
        // 半角按 1 单位计：13 个字符远未超，原样返回
        assertEquals("19:55 - 19:58", truncateIslandLine("19:55 - 19:58"))
        // 混排：4 汉字(8) + 3 数字(3) + 5 字母(5) = 16 装满，第 6 个字母起被截
        val mixed = truncateIslandLine("高博学楼329ABCDEFGH")
        assertEquals("高博学楼329ABCDE", mixed)
        assertFalse("不应出现省略号", mixed.contains("…"))
        assertFalse(
            "汉字换行拼接后也不应出现省略号",
            truncateIslandLine("中学生物学教学论超长名字").contains("…"),
        )
    }

    @Test
    fun promotedDetailLinesCarryTwoBeforeClassLines() {
        // 课前卡片正文两行：① 地点 · 倒计时　② 时间区间（不带「时间: 」标签）。
        // 回归背景（OPPO PLA110 / ColorOS 16）：旧写法把首段留空再 append("\n")，
        // 拼出前导空行；卡片正文只显示前两行，于是只露出被截断的「时间: 19:13 - 19:1...」。
        val lines = buildPromotedDetailLines(
            duringClassLines = null,
            beforeClassLines = listOf("高博学楼326 · 2分钟", "19:55 - 19:58"),
        )
        assertEquals(listOf("高博学楼326 · 2分钟", "19:55 - 19:58"), lines)
        assertTrue("不应出现任何空行", lines.none { it.isBlank() })
        assertFalse(
            "拼出来的 bigText 不能以换行开头",
            lines.joinToString("\n").startsWith("\n"),
        )
    }

    @Test
    fun promotedDetailLinesSkipBlankBeforeClassLines() {
        // 地点与倒计时都关掉时首行会拼成空串，时间区间也可能为空 —— 都不应产生空行。
        assertEquals(
            emptyList<String>(),
            buildPromotedDetailLines(
                duringClassLines = null,
                beforeClassLines = listOf("", ""),
            ),
        )
        assertEquals(
            listOf("19:55 - 19:58"),
            buildPromotedDetailLines(
                duringClassLines = null,
                beforeClassLines = listOf("", "19:55 - 19:58"),
            ),
        )
    }

    @Test
    fun promotedDetailLinesPreferDuringClassProgress() {
        // 课中带进度时，开头用进度行而不是课前内容行（保留课中若重新上岛的文案规则）。
        val lines = buildPromotedDetailLines(
            duringClassLines = listOf("下一节点 20分钟", "整节下课 32分钟"),
            beforeClassLines = listOf("教3-401 · 上课中", "14:00 - 15:40"),
        )
        assertEquals(listOf("下一节点 20分钟", "整节下课 32分钟"), lines)
    }

    @Test
    fun classStartingPromptCoversLastFiveSecondsOfBeforeClass() {
        val start = 1_700_000_000_000L
        // 窗口内：T-5s 到 T
        assertTrue(liveShouldShowClassStartingPrompt("beforeClass", start - 5_000L, start))
        assertTrue(liveShouldShowClassStartingPrompt("beforeClass", start - 1_000L, start))
        assertTrue(liveShouldShowClassStartingPrompt("beforeClass", start, start))
        // 窗口外：仍是到上课的倒计时
        assertFalse(liveShouldShowClassStartingPrompt("beforeClass", start - 5_001L, start))
        assertFalse(liveShouldShowClassStartingPrompt("beforeClass", start - 60_000L, start))
    }

    @Test
    fun classStartingPromptOnlyAppliesToBeforeClass() {
        val start = 1_700_000_000_000L
        // 课中与下课提醒不再上岛，这两档不该出现上课信号。
        assertFalse(liveShouldShowClassStartingPrompt("duringClass", start, start))
        assertFalse(liveShouldShowClassStartingPrompt("duringClassStatusBar", start, start))
        assertFalse(liveShouldShowClassStartingPrompt("beforeEnd", start - 1_000L, start))
        assertFalse(liveShouldShowClassStartingPrompt(null, start - 1_000L, start))
    }

    @Test
    fun endedOrUnknownStageNeverPromotes() {
        // null = 已过 endAtMillis、Service 尚未自停的 ≤30 秒窗口（ticker 的 +30s）。
        assertFalse(liveShouldPromoteStage(null))
        assertFalse(liveShouldPromoteStage(""))
    }

    @Test
    fun surfaceBrandRecognizesXiaomiFamily() {
        assertEquals(LiveSurfaceBrand.XIAOMI, liveSurfaceBrand("Xiaomi", "Xiaomi"))
        assertEquals(LiveSurfaceBrand.XIAOMI, liveSurfaceBrand("Xiaomi", "Redmi"))
        assertEquals(LiveSurfaceBrand.XIAOMI, liveSurfaceBrand("Xiaomi", "POCO"))
        // 合成样本：旧实现只在 brand 一侧查 redmi/poco，manufacturer 侧命中时会漏判。
        assertEquals(LiveSurfaceBrand.XIAOMI, liveSurfaceBrand("Redmi", "unknown"))
    }

    @Test
    fun surfaceBrandRecognizesColorOsFamily() {
        assertEquals(LiveSurfaceBrand.COLOROS, liveSurfaceBrand("OPPO", "OPPO"))
        assertEquals(LiveSurfaceBrand.COLOROS, liveSurfaceBrand("realme", "realme"))
        assertEquals(LiveSurfaceBrand.COLOROS, liveSurfaceBrand("OnePlus", "OnePlus"))
    }

    @Test
    fun surfaceBrandIsCaseInsensitiveAndFallsBackToGeneric() {
        assertEquals(LiveSurfaceBrand.COLOROS, liveSurfaceBrand("oppo", "OPPO"))
        assertEquals(LiveSurfaceBrand.GENERIC, liveSurfaceBrand("Google", "google"))
    }
}
