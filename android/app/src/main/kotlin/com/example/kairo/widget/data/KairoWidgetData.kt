package com.example.kairo.widget.data

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking

// DataStore (Preferences) "kairo_widget" — fonte de dados dos widgets, escrita
// pelo app principal (ver MainActivity MethodChannel) e lida pelos providers.
val Context.kairoWidgetStore by preferencesDataStore(name = "kairo_widget")

object KairoKeys {
    val phrase = stringPreferencesKey("phrase_today")
    val practiceTitle = stringPreferencesKey("next_practice_title")
    val practiceTime = stringPreferencesKey("next_practice_time") // ISO8601, opcional
    val streak = intPreferencesKey("streak_count")
    val lastUpdated = longPreferencesKey("last_updated") // epoch ms
}

data class KairoWidgetData(
    val phrase: String = "",
    val practiceTitle: String = "",
    val practiceTime: String? = null,
    val streak: Int = 0,
    val lastUpdated: Long = 0L,
) {
    val isEmpty: Boolean get() = phrase.trim().isEmpty()
    val isStale: Boolean
        get() = lastUpdated > 0 && System.currentTimeMillis() - lastUpdated > 24L * 60 * 60 * 1000
}

object KairoStore {
    /// Leitura síncrona (via runBlocking) — chamada de dentro do onUpdate do
    /// AppWidgetProvider, que já roda fora da main thread no broadcast.
    fun ler(context: Context): KairoWidgetData = runBlocking {
        val p: Preferences = context.kairoWidgetStore.data.first()
        KairoWidgetData(
            phrase = p[KairoKeys.phrase] ?: "",
            practiceTitle = p[KairoKeys.practiceTitle] ?: "",
            practiceTime = p[KairoKeys.practiceTime]?.takeIf { it.isNotEmpty() },
            streak = p[KairoKeys.streak] ?: 0,
            lastUpdated = p[KairoKeys.lastUpdated] ?: 0L,
        )
    }

    suspend fun gravar(
        context: Context,
        phrase: String?,
        practiceTitle: String?,
        practiceTime: String?,
        streak: Int?,
    ) {
        context.kairoWidgetStore.edit { p ->
            phrase?.let { p[KairoKeys.phrase] = it }
            practiceTitle?.let { p[KairoKeys.practiceTitle] = it }
            // practiceTime: string vazia/null remove a chave.
            if (practiceTime.isNullOrEmpty()) p.remove(KairoKeys.practiceTime)
            else p[KairoKeys.practiceTime] = practiceTime
            streak?.let { p[KairoKeys.streak] = it }
            p[KairoKeys.lastUpdated] = System.currentTimeMillis()
        }
    }
}

// ── Lógica pura (espelhada em Swift/Dart e coberta por testes) ───────────────
object KairoFormat {
    const val MAX_STONES = 7

    /// Trunca com EM-DASH (nunca "..."). Recua à borda de palavra quando possível.
    fun truncar(texto: String, max: Int): String {
        val limpo = texto.trim()
        if (limpo.length <= max || max <= 1) return limpo
        val corte = limpo.substring(0, max - 1)
        val ultimoEspaco = corte.lastIndexOf(' ')
        if (ultimoEspaco >= max / 2) {
            return corte.substring(0, ultimoEspaco).trimEnd(' ', ',', ';', ':') + "—"
        }
        return corte.trimEnd() + "—"
    }

    /// (stones cheios, overflow?) — > 7 vira 6 stones + "·".
    fun stones(streak: Int): Pair<Int, Boolean> = when {
        streak <= 0 -> 0 to false
        streak <= MAX_STONES -> streak to false
        else -> (MAX_STONES - 1) to true
    }
}
