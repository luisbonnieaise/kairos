package com.example.kairo

import com.example.kairo.widget.data.KairoStore
import com.example.kairo.widget.providers.KairoWidgetRefresh
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private val canal = "kairo.widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Lado Android do MethodChannel('kairo.widget'): grava no DataStore e
        // atualiza os widgets na tela.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canal)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateWidgetData" -> {
                        val phrase = call.argument<String>("phrase_today")
                        val title = call.argument<String>("next_practice_title")
                        val time = call.argument<String>("next_practice_time")
                        val streak = call.argument<Int>("streak_count")
                        CoroutineScope(Dispatchers.IO).launch {
                            KairoStore.gravar(applicationContext, phrase, title, time, streak)
                            KairoWidgetRefresh.atualizarTodos(applicationContext)
                        }
                        result.success(true)
                    }
                    "reloadWidgets" -> {
                        KairoWidgetRefresh.atualizarTodos(applicationContext)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
