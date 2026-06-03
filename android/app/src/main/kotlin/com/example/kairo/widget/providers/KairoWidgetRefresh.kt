package com.example.kairo.widget.providers

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

// Atualização e agendamento dos widgets Android.
object KairoWidgetRefresh {
    private const val WORK_NAME = "kairo_widget_refresh"

    /// Envia ACTION_APPWIDGET_UPDATE a todos os widgets vivos de ambos os tamanhos.
    /// Chamado pela bridge (MainActivity) e pelo worker horário.
    fun atualizarTodos(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        for (cls in listOf(KairoSmallWidgetProvider::class.java, KairoLargeWidgetProvider::class.java)) {
            val cn = ComponentName(context, cls)
            val ids = mgr.getAppWidgetIds(cn)
            if (ids.isNotEmpty()) {
                val intent = Intent(context, cls).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(intent)
            }
        }
    }

    /// Agenda refresh periódico de 1h (rede de segurança; o app força updates).
    fun agendar(context: Context) {
        val req = PeriodicWorkRequestBuilder<KairoWidgetWorker>(1, TimeUnit.HOURS).build()
        WorkManager.getInstance(context)
            .enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, req)
    }

    /// Cancela o trabalho se NENHUM widget de qualquer tamanho restar na tela
    /// (edge case 8 — limpeza ao remover o último widget).
    fun cancelarSeNenhum(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        val total = listOf(KairoSmallWidgetProvider::class.java, KairoLargeWidgetProvider::class.java)
            .sumOf { mgr.getAppWidgetIds(ComponentName(context, it)).size }
        if (total == 0) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }
    }
}

class KairoWidgetWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        KairoWidgetRefresh.atualizarTodos(applicationContext)
        return Result.success()
    }
}
