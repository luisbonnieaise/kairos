import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class KairoAudio {
  static final _orin = AudioPlayer();
  static final _ambiente = AudioPlayer();
  static bool _configurado = false;

  static Future<void> precarregar() async {
    if (_configurado) return;
    try {
      final ctx = AudioContext(
        android: AudioContextAndroid(
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.ambient,
          options: const {
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
      );

      await _orin.setReleaseMode(ReleaseMode.stop);
      await _orin.setAudioContext(ctx);

      await _ambiente.setReleaseMode(ReleaseMode.loop);
      await _ambiente.setAudioContext(ctx);

      _configurado = true;
    } catch (e) {
      debugPrint('Erro ao configurar áudio: $e');
    }
  }

  static Future<void> tocarOrin() async {
    try {
      await precarregar();
      await _orin.stop();
      await _orin.play(AssetSource('sounds/orin.mp3'), volume: 0.45);
    } catch (e) {
      debugPrint('Erro ao tocar orin: $e');
    }
  }

  /// Toca som ambiente em loop (chuva, vento, etc.)
  /// Passe null para silêncio.
  static Future<void> tocarAmbiente(String? arquivo, {double volume = 0.85}) async {
    try {
      await precarregar();
      await _ambiente.stop();
      if (arquivo == null) return;
      await _ambiente.play(AssetSource('sounds/$arquivo'), volume: volume);
    } catch (e) {
      debugPrint('Erro ao tocar ambiente: $e');
    }
  }

  static Future<void> pararAmbiente() async {
    try {
      await _ambiente.stop();
    } catch (e) {
      debugPrint('Erro ao parar ambiente: $e');
    }
  }
}
