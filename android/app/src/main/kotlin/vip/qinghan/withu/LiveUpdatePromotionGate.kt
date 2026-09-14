package vip.qinghan.withu

/**
 * API 36 提升通知的准入判据（Live Updates / OPPO 流体云 / 小米超级岛标准通道）。
 *
 * 系统侧的闸门是 `Notification.hasPromotableCharacteristics()`（AOSP android-36
 * `Notification.java:3297`）。对**非 Ongoing CallStyle** 的通知它只要求两件事：
 *
 * ```java
 * return isColorizedRequested() && hasPromotableStyle();
 * ```
 *
 * - `isColorizedRequested()` 读的就是 `extras.getBoolean(EXTRA_COLORIZED)`
 *   （同文件 `:8091`），即 `Notification.Builder.setColorized(...)` 的入参；
 * - `hasPromotableStyle()` 放行 null / BigTextStyle / CallStyle / ProgressStyle
 *   （同文件 `:3280`），本应用的 ProgressStyle 与 BigTextStyle 都在其中。
 *
 * 所以**唯一会失败的闸门就是 EXTRA_COLORIZED**。历史上这里恒为
 * `setColorized(false)`，于是 `hasPromotableCharacteristics()` 永远是 false，
 * 系统永远不会给通知打 `FLAG_PROMOTED_ONGOING`：OPPO 流体云、原生 Android 16
 * 实时活动这些**标准提升表面永远看不到卡片**，而自检页只会报一句
 * 「通知不具备可提升特征」，看不出真正原因。小米侧因为有 `miui.focus.param`
 * 私有通道兜底，症状被掩盖，问题才一直没暴露。
 *
 * ⚠️ 与官方文档的冲突（2026-09-11 已定论）：官方《Create live update notifications》
 * 的准入清单写的是 “Must NOT `setColorized` to `TRUE`”，与上面这段 AOSP 实现相反。
 * 实机回归证明以官方文档为准——放行 `true` 会让通知彻底失去提升资格，
 * 详见下方 @return 的记录。
 *
 * @param shouldPromote 入参保留以固定调用点签名；回退后不再影响返回值。
 * @return 传给 `Notification.Builder.setColorized(...)` 的值，恒为 `false`。
 *
 * ⚠️ 实机回归（2026-09-11，OPPO PLA110 / ColorOS 16.1 / Android 16）：
 * 置 `true` 后流体云反而**不出卡片**，自检页报 `hasPromotableCharacteristics() == false`；
 * 而同机 v5.2.0.1（此处恒为 `false`）可正常上岛。可见 ColorOS 上官方文档
 * “Must NOT `setColorized` to `TRUE`” 才是实际生效的判据，AOSP 源码那套
 * `isColorizedRequested()` 推导在本机不成立。故回退为 `false`，不再按帧置 true。
 */
internal fun liveShouldRequestColorizedForPromotion(
    @Suppress("UNUSED_PARAMETER") shouldPromote: Boolean,
): Boolean = false
