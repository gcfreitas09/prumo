enum Situacao { primeira, naMedia, acima, negativo }

class Analise {
  final int? consumo;
  final int? media;
  final Situacao situacao;
  const Analise(this.consumo, this.media, this.situacao);

  /// Consumo negativo ou > 2× a média pede um toque extra.
  bool get pedeConfirmacao => situacao == Situacao.negativo || situacao == Situacao.acima;

  String get texto {
    switch (situacao) {
      case Situacao.primeira:
        return 'Sem mês anterior para comparar';
      case Situacao.naMedia:
        return 'Na média';
      case Situacao.acima:
        return 'Mais que o dobro da média';
      case Situacao.negativo:
        return 'Menor que o mês anterior';
    }
  }
}

/// [anteriores]: leituras de meses anteriores, mais recente primeiro (até 4).
Analise analisar(int? valor, List<int> anteriores) {
  if (valor == null || anteriores.isEmpty) return const Analise(null, null, Situacao.primeira);
  final consumo = valor - anteriores.first;
  final difs = <int>[];
  for (var i = 0; i + 1 < anteriores.length && difs.length < 3; i++) {
    difs.add(anteriores[i] - anteriores[i + 1]);
  }
  final media = difs.isEmpty ? null : (difs.reduce((a, b) => a + b) / difs.length).round();
  if (consumo < 0) return Analise(consumo, media, Situacao.negativo);
  if (media != null && media > 0 && consumo > 2 * media) return Analise(consumo, media, Situacao.acima);
  return Analise(consumo, media, Situacao.naMedia);
}

/// Leitura plausível para captura automática: não menor que a anterior e
/// sem salto absurdo (descarta dígito perdido ou casas decimais lidas junto).
bool plausivel(int v, List<int> anteriores) {
  if (anteriores.isEmpty) return true;
  if (v < anteriores.first) return false;
  // com histórico, até 8× a média; sem média, até 20% da leitura anterior
  // (a escala depende de quantos roletes o medidor tem)
  final a = analisar(v, anteriores);
  final semMedia = anteriores.first ~/ 5 < 300 ? 300 : anteriores.first ~/ 5;
  final limite = (a.media ?? 0) > 0 ? (a.media! * 8 < 300 ? 300 : a.media! * 8) : semMedia;
  return v - anteriores.first <= limite;
}
