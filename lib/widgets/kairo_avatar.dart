import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../core/kairo_tema.dart';
import '../core/banco.dart';
import '../core/i18n.dart';

/// Avatar circular do usuário.
///
/// - Exibe a foto do perfil se [url] for fornecida, com fallback para inicial.
/// - [editavel] = true exibe badge de câmera e permite trocar/remover a foto.
/// - [aoAtualizar] é chamado com a nova URL (ou string vazia ao remover).
class KairoAvatar extends StatefulWidget {
  final double tamanho;
  final String? url;
  final String nome;
  final bool editavel;
  final void Function(String novaUrl)? aoAtualizar;

  const KairoAvatar({
    super.key,
    required this.tamanho,
    this.url,
    this.nome = '',
    this.editavel = false,
    this.aoAtualizar,
  });

  @override
  State<KairoAvatar> createState() => _KairoAvatarState();
}

class _KairoAvatarState extends State<KairoAvatar> {
  bool _carregando = false;

  String get _inicial {
    final nome = widget.nome.trim();
    if (nome.isEmpty) return '?';
    return nome[0].toUpperCase();
  }

  // ── Upload ──────────────────────────────────────────────────────────────────

  Future<void> _selecionarFoto(ImageSource fonte) async {
    try {
      final picker = ImagePicker();
      final arquivo = await picker.pickImage(
        source: fonte,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 88,
      );
      if (arquivo == null) return;

      if (!mounted) return;
      setState(() => _carregando = true);

      final bytes = await arquivo.readAsBytes();
      final ext   = arquivo.path.split('.').last.isNotEmpty
          ? arquivo.path.split('.').last
          : 'jpg';

      final novaUrl = await BancoAvatar.enviar(bytes, ext);

      if (!mounted) return;
      setState(() => _carregando = false);
      widget.aoAtualizar?.call(novaUrl);
    } catch (e) {
      debugPrint('[KairoAvatar] erro ao selecionar/enviar foto: $e');
      if (!mounted) return;
      setState(() => _carregando = false);
      _mostrarErro();
    }
  }

  Future<void> _removerFoto() async {
    try {
      setState(() => _carregando = true);
      await BancoAvatar.remover();
      if (!mounted) return;
      setState(() => _carregando = false);
      widget.aoAtualizar?.call('');
    } catch (e) {
      debugPrint('[KairoAvatar] erro ao remover foto: $e');
      if (!mounted) return;
      setState(() => _carregando = false);
      _mostrarErro();
    }
  }

  void _mostrarErro() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: KC.card,
        behavior: SnackBarBehavior.floating,
        content: Text(T.erroGenerico, style: KT.caption(cor: KC.texto)),
      ),
    );
  }

  // ── Bottom sheet de opções ──────────────────────────────────────────────────

  void _mostrarOpcoes() {
    HapticFeedback.lightImpact();

    showModalBottomSheet(
      context: context,
      backgroundColor: KC.sumi,
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
              // Alça do sheet
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

              Text(
                widget.url != null ? T.trocarFoto : T.adicionarFoto,
                style: KT.titulo(),
              ),

              const SizedBox(height: 24),

              _OpcaoSheet(
                icone: Icons.photo_library_outlined,
                rotulo: T.galeria,
                onTap: () {
                  Navigator.pop(ctx);
                  _selecionarFoto(ImageSource.gallery);
                },
              ),

              _OpcaoSheet(
                icone: Icons.camera_alt_outlined,
                rotulo: T.camera,
                onTap: () {
                  Navigator.pop(ctx);
                  _selecionarFoto(ImageSource.camera);
                },
              ),

              if (widget.url != null) ...[
                const SizedBox(height: 8),
                Divider(color: KC.grafite, height: 1, thickness: 1),
                const SizedBox(height: 8),
                _OpcaoSheet(
                  icone: Icons.delete_outline,
                  rotulo: T.removerFoto,
                  cor: KC.aka,
                  onTap: () {
                    Navigator.pop(ctx);
                    _removerFoto();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final temFoto  = widget.url != null && widget.url!.isNotEmpty;
    final badgeR   = widget.tamanho * 0.185;  // raio do badge de câmera
    final fontSize = widget.tamanho * 0.38;   // tamanho da inicial

    return GestureDetector(
      onTap: widget.editavel ? _mostrarOpcoes : null,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: widget.tamanho,
        height: widget.tamanho,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Círculo principal ───────────────────────────────────────────
            Container(
              width: widget.tamanho,
              height: widget.tamanho,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KC.card,
                border: Border.all(
                  color: temFoto ? KC.acento.withValues(alpha: 0.35) : KC.linha,
                  width: 1.5,
                ),
              ),
              child: ClipOval(
                child: _carregando
                    ? _Shimmer(tamanho: widget.tamanho)
                    : temFoto
                        ? Image.network(
                            widget.url!,
                            width: widget.tamanho,
                            height: widget.tamanho,
                            fit: BoxFit.cover,
                            loadingBuilder: (_, child, progress) {
                              if (progress == null) return child;
                              return _Shimmer(tamanho: widget.tamanho);
                            },
                            errorBuilder: (_, _, _) => _Inicial(
                              inicial: _inicial,
                              tamanho: widget.tamanho,
                              fontSize: fontSize,
                            ),
                          )
                        : _Inicial(
                            inicial: _inicial,
                            tamanho: widget.tamanho,
                            fontSize: fontSize,
                          ),
              ),
            ),

            // ── Badge de câmera (só no modo editável) ───────────────────────
            if (widget.editavel)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: badgeR * 2,
                  height: badgeR * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KC.acento,
                    border: Border.all(color: KC.fundo, width: 1.5),
                  ),
                  child: Icon(
                    Icons.camera_alt,
                    size: badgeR * 0.9,
                    color: KC.fundo,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets internos ──────────────────────────────────────────────────────

class _Inicial extends StatelessWidget {
  final String inicial;
  final double tamanho;
  final double fontSize;

  const _Inicial({
    required this.inicial,
    required this.tamanho,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: tamanho,
      height: tamanho,
      child: Center(
        child: Text(
          inicial,
          style: KT.titulo(cor: KC.textoSuave).copyWith(fontSize: fontSize),
        ),
      ),
    );
  }
}

// Placeholder animado enquanto carrega a imagem
class _Shimmer extends StatefulWidget {
  final double tamanho;
  const _Shimmer({required this.tamanho});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 0.85).animate(_anim),
      child: Container(
        width: widget.tamanho,
        height: widget.tamanho,
        color: KC.linha,
      ),
    );
  }
}

// Linha de opção no bottom sheet
class _OpcaoSheet extends StatelessWidget {
  final IconData icone;
  final String rotulo;
  final Color? cor;
  final VoidCallback onTap;

  const _OpcaoSheet({
    required this.icone,
    required this.rotulo,
    required this.onTap,
    this.cor,
  });

  @override
  Widget build(BuildContext context) {
    final corEfetiva = cor ?? KC.texto;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icone, size: 20, color: corEfetiva),
            const SizedBox(width: 16),
            Text(rotulo, style: KT.body(cor: corEfetiva)),
          ],
        ),
      ),
    );
  }
}
