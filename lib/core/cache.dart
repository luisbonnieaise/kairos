import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

/// Cache local de leitura/escrita para o padrão "stale-while-revalidate":
/// as abas pintam os dados do cache INSTANTANEAMENTE no boot e revalidam do
/// Supabase em segundo plano. Reduz a sensação de "carregando" a quase zero.
///
/// • Pré-carregado no boot ([init] em main) → leitura SÍNCRONA (sem await na UI).
/// • Namespaced por `user.id` → uma conta nunca vê o cache de outra.
/// • Só conveniência de display: a verdade continua sendo o Supabase (RLS).
class CacheLocal {
  static SharedPreferences? _p;

  static Future<void> init() async {
    _p ??= await SharedPreferences.getInstance();
  }

  static String _k(String nome) {
    final uid = supabase.auth.currentUser?.id ?? 'anon';
    return 'cache.$uid.$nome';
  }

  static dynamic _lerJson(String nome) {
    final s = _p?.getString(_k(nome));
    if (s == null) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  /// Lê uma lista de mapas cacheada (ex.: linhas de uma tabela). `null` se vazio.
  static List<Map<String, dynamic>>? lerLista(String nome) {
    final j = _lerJson(nome);
    if (j is! List) return null;
    return j
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Lê um mapa cacheado. `null` se ausente/corrompido.
  static Map<String, dynamic>? lerMapa(String nome) {
    final j = _lerJson(nome);
    if (j is! Map) return null;
    return Map<String, dynamic>.from(j);
  }

  /// Grava qualquer estrutura JSON-serializável. Falha silenciosa (cache é
  /// best-effort — nunca deve quebrar o fluxo principal).
  static Future<void> gravar(String nome, Object? dados) async {
    try {
      if (dados == null) {
        await _p?.remove(_k(nome));
        return;
      }
      await _p?.setString(_k(nome), jsonEncode(dados));
    } catch (_) {
      /* ignora — cache é descartável */
    }
  }

  /// Apaga todo o cache do usuário atual (chamar no logout, antes do signOut).
  static Future<void> limparUsuario() async {
    final p = _p;
    if (p == null) return;
    final uid = supabase.auth.currentUser?.id ?? 'anon';
    final prefixo = 'cache.$uid.';
    for (final k in p.getKeys().where((k) => k.startsWith(prefixo)).toList()) {
      await p.remove(k);
    }
  }
}
