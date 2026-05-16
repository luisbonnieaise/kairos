import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'banco.dart';
import 'kairo_tema.dart';
import 'i18n.dart';

/// Mostra um tutorial uma única vez por USUÁRIO. Estado salvo na coluna
/// `tutoriais_vistos` (JSONB) da tabela `profiles`.
class Tutorial {
  /// Mostra o tutorial se ainda não foi visto pelo usuário atual.
  /// Chame de dentro de initState após o frame ser renderizado.
  static Future<void> mostrar({
    required BuildContext context,
    required String chave,
    required String titulo,
    required String texto,
  }) async {
    final visto = await BancoTutoriais.jaVisto(chave);
    if (visto) return;
    if (!context.mounted) return;

    await _exibirModal(
      context: context,
      titulo: titulo,
      texto: texto,
    );

    await BancoTutoriais.marcarVisto(chave);
  }

  /// Força a exibição do tutorial (usado no Perfil para rever).
  /// Não marca como visto novamente — apenas mostra.
  static Future<void> mostrarForcado({
    required BuildContext context,
    required String titulo,
    required String texto,
  }) async {
    await _exibirModal(context: context, titulo: titulo, texto: texto);
  }

  static Future<void> _exibirModal({
    required BuildContext context,
    required String titulo,
    required String texto,
  }) async {
    // Pequena espera pro layout estabilizar (somente em primeira exibição automática)
    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: KC.sumi,
      barrierColor: KC.sumi.withValues(alpha: 0.85),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 3,
                  decoration: BoxDecoration(
                    color: KC.grafite,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(T.mentorLabel, style: KT.micro(cor: KC.kin)),
              const SizedBox(height: 8),
              Text(titulo, style: KT.titulo()),
              const SizedBox(height: 16),
              Text(texto, style: KT.bodySerif(cor: KC.cinza)),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KC.washi,
                    foregroundColor: KC.sumi,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(T.entendi, style: KT.body(cor: KC.sumi)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
