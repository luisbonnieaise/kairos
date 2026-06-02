/// Funções puras de data usadas em todo o app. Vivem aqui (separadas do
/// `banco.dart` e das telas) para serem testáveis sem mockar Supabase.
///
/// Mantemos comportamento BIT-PERFEITO ao que estava antes da extração —
/// qualquer mudança de semântica deve ser deliberada e ter teste correspondente.
library;

/// Formata `d` como "YYYY-MM-DD" em tempo LOCAL (não UTC). É a representação
/// usada pelas colunas `data date` no banco (pratica_completadas.data).
String formatarDataYMD(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// `semana_inicio` (segunda-feira) no formato "YYYY-MM-DD", em tempo LOCAL.
/// Mesma convenção do servidor (Edge Function relatorio-semanal):
/// `semana_fim` = domingo mais recente; `semana_inicio` = domingo - 6 dias.
/// Se `agora` é domingo → semana_fim = hoje; senão → último domingo já passado.
String semanaInicioISO(DateTime agora) {
  final int diasParaVoltar = (agora.weekday == DateTime.sunday)
      ? 0
      : agora.weekday; // segunda=1 ... sábado=6
  final fim = DateTime(agora.year, agora.month, agora.day)
      .subtract(Duration(days: diasParaVoltar));
  final inicio = fim.subtract(const Duration(days: 6));
  return formatarDataYMD(inicio);
}

/// Retorna 7 flags representando os últimos 7 dias em ordem CRONOLÓGICA
/// ASCENDENTE: posição 0 = 6 dias atrás, posição 6 = hoje.
///
/// `datasFeitas` é um set de strings "YYYY-MM-DD" das datas em que a prática
/// foi marcada como feita (vem do banco já filtrada).
///
/// (Esta era a forma do código antes da extração; só corrigimos o comentário
/// herdado em banco.dart que estava invertido.)
List<bool> ultimos7DiasFlags({
  required DateTime agora,
  required Set<String> datasFeitas,
}) {
  final base = DateTime(agora.year, agora.month, agora.day);
  final resultado = <bool>[];
  for (int i = 6; i >= 0; i--) {
    final d = base.subtract(Duration(days: i));
    resultado.add(datasFeitas.contains(formatarDataYMD(d)));
  }
  return resultado;
}

/// Data de início da janela inclusiva dos últimos 7 dias (hoje - 6 dias) em
/// "YYYY-MM-DD" — útil pra montar `gte('data', ...)` em queries.
String inicioJanela7Dias(DateTime agora) {
  final base = DateTime(agora.year, agora.month, agora.day);
  return formatarDataYMD(base.subtract(const Duration(days: 6)));
}
