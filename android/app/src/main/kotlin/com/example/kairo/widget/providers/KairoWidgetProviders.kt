package com.example.kairo.widget.providers

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import com.thekairo.app.R
import com.example.kairo.widget.data.KairoFormat
import com.example.kairo.widget.data.KairoStore
import com.example.kairo.widget.data.KairoWidgetData

// Deep links (já registrados no AndroidManifest: scheme kairo://).
private const val LINK_TODAY = "kairo://today"
private const val LINK_MENTOR = "kairo://mentor"
private const val LINK_PRACTICES = "kairo://practices"
private const val LINK_PROGRESS = "kairo://progress"

private fun deepLink(context: Context, uri: String, requestCode: Int): PendingIntent {
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri)).apply {
        setPackage(context.packageName)
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
    }
    val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    return PendingIntent.getActivity(context, requestCode, intent, flags)
}

// "2025-06-03T18:30:00Z" -> "18:30" (sem depender de java.time / desugaring).
private fun horaDe(iso: String?): String? {
    if (iso.isNullOrEmpty()) return null
    val t = iso.indexOf('T')
    if (t < 0 || iso.length < t + 6) return null
    return iso.substring(t + 1, t + 6)
}

// ── Small (2x2) ──────────────────────────────────────────────────────────────
class KairoSmallWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) {
        val data = KairoStore.ler(context)
        for (id in ids) mgr.updateAppWidget(id, render(context, data))
    }

    override fun onEnabled(context: Context) = KairoWidgetRefresh.agendar(context)
    override fun onDisabled(context: Context) = KairoWidgetRefresh.cancelarSeNenhum(context)

    private fun render(context: Context, data: KairoWidgetData): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.kairo_widget_small)
        if (data.isEmpty) {
            v.setViewVisibility(R.id.content, View.GONE)
            v.setViewVisibility(R.id.empty, View.VISIBLE)
        } else {
            v.setViewVisibility(R.id.content, View.VISIBLE)
            v.setViewVisibility(R.id.empty, View.GONE)
            v.setTextViewText(R.id.phrase, KairoFormat.truncar(data.phrase, 160))
            v.setViewVisibility(R.id.staleness, if (data.isStale) View.VISIBLE else View.GONE)
        }
        v.setOnClickPendingIntent(R.id.kairo_root, deepLink(context, LINK_TODAY, 10))
        return v
    }
}

// ── Large (4x4) ────────────────────────────────────────────────────────────--
class KairoLargeWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) {
        val data = KairoStore.ler(context)
        for (id in ids) mgr.updateAppWidget(id, render(context, data))
    }

    override fun onEnabled(context: Context) = KairoWidgetRefresh.agendar(context)
    override fun onDisabled(context: Context) = KairoWidgetRefresh.cancelarSeNenhum(context)

    private val stoneIds = intArrayOf(
        R.id.stone1, R.id.stone2, R.id.stone3, R.id.stone4, R.id.stone5, R.id.stone6, R.id.stone7
    )

    private fun render(context: Context, data: KairoWidgetData): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.kairo_widget_large)
        if (data.isEmpty) {
            v.setViewVisibility(R.id.content, View.GONE)
            v.setViewVisibility(R.id.empty, View.VISIBLE)
            v.setOnClickPendingIntent(R.id.kairo_root, deepLink(context, LINK_TODAY, 20))
            return v
        }
        v.setViewVisibility(R.id.content, View.VISIBLE)
        v.setViewVisibility(R.id.empty, View.GONE)

        // Zona A
        v.setTextViewText(R.id.phrase, KairoFormat.truncar(data.phrase, 200))
        v.setViewVisibility(R.id.staleness, if (data.isStale) View.VISIBLE else View.GONE)

        // Zona B
        v.setTextViewText(R.id.practice_title, data.practiceTitle.ifEmpty { "—" })
        val hora = horaDe(data.practiceTime)
        if (hora != null) {
            v.setTextViewText(R.id.practice_time, hora)
            v.setViewVisibility(R.id.practice_time, View.VISIBLE)
        } else {
            v.setViewVisibility(R.id.practice_time, View.GONE)
        }

        // Zona C — stones
        val (cheios, overflow) = KairoFormat.stones(data.streak)
        if (data.streak <= 0) {
            v.setViewVisibility(R.id.streak_zero, View.VISIBLE)
            v.setViewVisibility(R.id.stones, View.GONE)
            v.setViewVisibility(R.id.streak_label, View.GONE)
        } else {
            v.setViewVisibility(R.id.streak_zero, View.GONE)
            v.setViewVisibility(R.id.stones, View.VISIBLE)
            v.setViewVisibility(R.id.streak_label, View.VISIBLE)
            for (i in stoneIds.indices) {
                v.setViewVisibility(stoneIds[i], if (i < cheios) View.VISIBLE else View.GONE)
            }
            v.setViewVisibility(R.id.stone_overflow, if (overflow) View.VISIBLE else View.GONE)
        }

        // Toques por zona
        v.setOnClickPendingIntent(R.id.zone_a, deepLink(context, LINK_MENTOR, 21))
        v.setOnClickPendingIntent(R.id.zone_b, deepLink(context, LINK_PRACTICES, 22))
        v.setOnClickPendingIntent(R.id.zone_c, deepLink(context, LINK_PROGRESS, 23))
        return v
    }
}
