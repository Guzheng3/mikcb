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
