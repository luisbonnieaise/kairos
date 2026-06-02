import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class KairoAudio {
  static final _orin = AudioPlayer();
  static final _ambiente = AudioPlayer();
  static final _dormir = AudioPlayer();
  static bool _configurado = false;
  static bool _dormirConfigurado = false;

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

  // ── RELAXA E DURMA ──────────────────────────────────────────────────────────
  // Player dedicado que continua tocando com a tela desligada / app em segundo
  // plano. Usa categoria `playback` no iOS e mantém a CPU acordada no Android.

  static Future<void> _configurarDormir() async {
    if (_dormirConfigurado) return;
    try {
      final ctx = AudioContext(
        android: AudioContextAndroid(
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
          stayAwake: true, // segura wake lock para tocar com a tela apagada
        ),
        iOS: AudioContextIOS(
          // `playback` permite áudio em segundo plano e com o aparelho bloqueado
          category: AVAudioSessionCategory.playback,
          options: const {},
        ),
      );
      await _dormir.setReleaseMode(ReleaseMode.loop);
      await _dormir.setAudioContext(ctx);
      _dormirConfigurado = true;
    } catch (e) {
      debugPrint('Erro ao configurar áudio de sono: $e');
    }
  }

  /// Toca um som em loop contínuo para dormir (chuva, selva, frequência…).
  static Future<void> tocarDormir(String arquivo, {double volume = 0.7}) async {
    try {
      await _configurarDormir();
      await _dormir.stop();
      await _dormir.play(AssetSource('sounds/$arquivo'), volume: volume);
    } catch (e) {
      debugPrint('Erro ao tocar som de sono: $e');
    }
  }

  /// Ajusta o volume do som de sono (usado no fade-out do timer).
  static Future<void> definirVolumeDormir(double volume) async {
    try {
      await _dormir.setVolume(volume.clamp(0.0, 1.0));
    } catch (e) {
      debugPrint('Erro ao ajustar volume de sono: $e');
    }
  }

  static Future<void> pararDormir() async {
    try {
      await _dormir.stop();
    } catch (e) {
      debugPrint('Erro ao parar som de sono: $e');
    }
  }
}
