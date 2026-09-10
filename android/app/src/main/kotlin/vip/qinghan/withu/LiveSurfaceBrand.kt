package vip.qinghan.withu

/**
 * 实时活动在不同厂商系统上的**用户可见名称**。
 *
 * - 小米 / Redmi / POCO（MIUI、HyperOS、澎湃OS）→「超级岛」
 * - OPPO / realme / 一加（ColorOS、OxygenOS）→「流体云」
 * - 其它（原生 Android 16 等）→「提升通知 / 实时活动」
 *
 * 自检页的失败原因若一律写「上岛」，OPPO 用户会以为该功能与自己无关；而
 * ColorOS 16 的流体云恰恰完整接入了 Android 16 的标准提升通知通道，属于
 * 最该被正确引导的一类用户。因此原因文案按本枚举分叉。
 */
internal enum class LiveSurfaceBrand {
    XIAOMI,
    COLOROS,
    GENERIC,
}

/**
 * 由 `Build.MANUFACTURER` / `Build.BRAND` 判定实时活动表面品牌。
 *
 * 只看厂商字符串，**不做系统能力探测**：能力探测（`canPostPromotedNotifications`
 * 等）是运行时闸门，品牌只决定文案措辞，两者刻意分开，避免把「文案分叉」
 * 和「功能门控」耦合成一处。
 *
 * 两个入参都转小写后做子串匹配，且**每个关键词都同时比对 manufacturer 与
 * brand**：历史上只有 brand 一侧查过 redmi/poco，机身 `MANUFACTURER=Redmi`
 * 而 `BRAND=Redmi` 之外的组合会漏判。
 */
internal fun liveSurfaceBrand(manufacturer: String, brand: String): LiveSurfaceBrand {
    val manufacturerLower = manufacturer.lowercase()
    val brandLower = brand.lowercase()

    fun matchesAny(vararg keywords: String): Boolean = keywords.any { keyword ->
        manufacturerLower.contains(keyword) || brandLower.contains(keyword)
    }

    return when {
        matchesAny("xiaomi", "redmi", "poco") -> LiveSurfaceBrand.XIAOMI
        matchesAny("oppo", "realme", "oneplus") -> LiveSurfaceBrand.COLOROS
        else -> LiveSurfaceBrand.GENERIC
    }
}
