const espacoFino = ' ';

/// Parte inteira (m³) de uma leitura guardada como "2689,58" ou "2689".
int? parteInteira(String? valor) => valor == null ? null : int.tryParse(valor.split(',').first);

/// Agrupa dígitos de 3 em 3 com espaço fino: 1316967 → 1 316 967.
/// Leitura com casas decimais mantém a vírgula: 268958 lido como "2689,58" → 2 689,58.
String fmtNum(Object? v) {
  if (v == null) return '—';
  final s0 = v.toString();
  final virg = s0.indexOf(',');
  if (virg >= 0) return '${fmtNum(s0.substring(0, virg))},${s0.substring(virg + 1)}';
  final s = s0;
  final neg = s.startsWith('-');
  final d = neg ? s.substring(1) : s;
  if (!RegExp(r'^\d+$').hasMatch(d)) return s;
  final b = StringBuffer();
  for (var i = 0; i < d.length; i++) {
    if (i > 0 && (d.length - i) % 3 == 0) b.write(espacoFino);
    b.write(d[i]);
  }
  return '${neg ? '-' : ''}$b';
}

/// "+ 1 247 m³" (negativo: "− 12 m³").
String fmtConsumo(int c) =>
    '${c < 0 ? '−' : '+'}$espacoFino${fmtNum(c.abs())}$espacoFino' 'm³';

const _meses = [
  'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
  'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
];

String nomeMes(int mes) => _meses[mes - 1];
String tituloMes(int ano, int mes) => '${nomeMes(mes)} de $ano';
String assuntoMes(int ano, int mes) => '${nomeMes(mes)}/$ano';
