import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:leituras_predio/digitos.dart';

/// Faixa sintética de medidor de gás: [n] dígitos "0" (anéis) bem espaçados,
/// os últimos [vermelhos] em vermelho.
Faixa faixaGas({int n = 8, int vermelhos = 3, double vao = 1.7, int altura = 64, bool claro = false}) {
  const w = 864, h = 330;
  // a fileira inteira tem de caber na moldura: dígitos menores quando o vão é grande
  final cabe = 0.92 * w / (n * 0.58 + (n - 1) * vao);
  if (altura > cabe) altura = cabe.floor();
  final cinza = Uint8List(w * h)..fillRange(0, w * h, claro ? 25 : 235);
  final verm = Uint8List(w * h);
  final largura = (altura * 0.58).round();
  final passo = largura + (altura * vao).round();
  var x0 = ((w - (passo * (n - 1) + largura)) / 2).round();
  const y0 = 130;
  for (var d = 0; d < n; d++) {
    final vermelho = d >= n - vermelhos;
    for (var y = y0; y < y0 + altura; y++) {
      for (var x = x0; x < x0 + largura; x++) {
        final borda = x - x0 < 7 || x0 + largura - x <= 7 || y - y0 < 7 || y0 + altura - y <= 7;
        if (!borda) continue;
        cinza[y * w + x] = claro ? (vermelho ? 150 : 235) : (vermelho ? 110 : 30);
        if (vermelho) verm[y * w + x] = 1;
      }
    }
    x0 += passo;
  }
  return Faixa(cinza, verm, w, h);
}

void main() {
  for (final vao in [0.3, 1.0, 1.7, 2.2]) {
    test('gás: 8 dígitos (5 pretos + 3 vermelhos), vão de $vao× a altura', () {
      final linhas = acharLinhas(faixaGas(vao: vao));
      expect(linhas, isNotEmpty);
      expect([linhas.first.claro, linhas.first.n, linhas.first.decimais], [false, 8, 3]);
    });
  }

  test('gás: 6 dígitos sem vermelhos, bem espaçados', () {
    final linhas = acharLinhas(faixaGas(n: 6, vermelhos: 0, vao: 1.8));
    expect([linhas.first.n, linhas.first.decimais], [6, 0]);
  });

  test('gás: dígito pequeno (altura 40) e vão grande', () {
    final linhas = acharLinhas(faixaGas(altura: 40, vao: 2.0));
    expect([linhas.first.n, linhas.first.decimais], [8, 3]);
  });

  test('gás com rolete preto e dígitos claros (5 claros + 3 vermelhos)', () {
    final linhas = acharLinhas(faixaGas(claro: true, vao: 1.6));
    final l = linhas.firstWhere((l) => l.claro);
    // com rolete preto, os dígitos vermelhos aparecem na luminância e entram na fileira
    expect(l.n, 8);
  });
}
