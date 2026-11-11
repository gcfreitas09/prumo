import 'package:flutter_test/flutter_test.dart';
import 'package:leituras_predio/analise.dart';
import 'package:leituras_predio/formato.dart';
import 'package:leituras_predio/ocr.dart';
import 'dart:typed_data';
import 'package:leituras_predio/db.dart';
import 'package:leituras_predio/relatorio.dart';

void main() {
  test('agrupa números com espaço fino', () {
    expect(fmtNum(1316967), '1 316 967');
    expect(fmtNum('45'), '45');
    expect(fmtConsumo(1247), '+ 1 247 m³');
  });

  test('meses em pt-BR', () {
    expect(tituloMes(2026, 10), 'Outubro de 2026');
    expect(assuntoMes(2026, 10), 'Outubro/2026');
  });

  test('análise de consumo', () {
    expect(analisar(90, [100, 80, 60, 40]).situacao, Situacao.negativo);
    expect(analisar(130, [100, 80, 60, 40]).situacao, Situacao.naMedia);
    expect(analisar(200, [100, 80, 60, 40]).situacao, Situacao.acima);
    expect(analisar(10, []).situacao, Situacao.primeira);
  });

  test('votação corrige um dígito errado em quadro isolado', () {
    final v = Votacao();
    for (final x in ['1316967', '1316967', '1316867', '1316967']) {
      v.add(x);
    }
    expect(v.consenso(), '1316967');
    final w = Votacao()..add('1316967')..add('1316867');
    expect(w.consenso(), isNull);
    // último rolete girando: oscila entre vizinhos, mas os outros dígitos travam
    final g = Votacao();
    for (final x in ['01464044', '01464045', '01464043', '01464044']) {
      g.add(x);
    }
    expect(g.consenso(), '01464044');
    // dígito do MEIO oscilando continua sem consenso
    final m = Votacao();
    for (final x in ['01464044', '01564045', '01364043', '01264046']) {
      m.add(x);
    }
    expect(m.consenso(), isNull);
    // 3 quadros já bastam quando cada dígito tem maioria (antes precisava de 4)
    final r = Votacao();
    for (final x in ['01464044', '01484044', '01464044']) {
      r.add(x);
    }
    expect(r.consenso(), '01464044');
  });

  test('plausibilidade descarta dígito perdido e salto absurdo', () {
    expect(plausivel(131967, [1316967, 1316800]), isFalse);
    expect(plausivel(1317000, [1316967, 1316800]), isTrue);
    expect(plausivel(1999999, [1316967, 1316800]), isFalse);
    expect(plausivel(5, []), isTrue);
  });

  test('relatório: linhas, PDF e e-mail', () async {
    final a = [const Apto(id: 1, numero: '101', andar: 1, ordemApto: 0, ordemLeitura: 0)];
    final lei = {chave(1, 'agua'): const Leitura(1, 'agua', '1500', null, false)};
    final ant = {chave(1, 'agua'): [1250]};
    final l = montarLinhas(a, lei, ant);
    expect(l.first.aguaCons, 250);
    expect(pendencias(a, lei).single.tipo, 'gas');
    const pr = Predio('Aurora', 'a@b.com', true);
    final mes = Mes(1, 2026, 10, null);
    expect(assunto(pr, mes), 'Leituras de água e gás – Outubro/2026 – Aurora');
    expect(corpoEmail(), 'Segue em anexo a leitura.\n\nAtenciosamente,\nAlex Freitas\n');
    expect(corpoEmail().contains('m³'), isFalse, reason: 'sem tabela de consumos no texto');
    final pdf = await gerarPdf(pr, mes, l);
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
  });

  test('faixa do quadro: em pé, com máscara do vermelho', () {
    // quadro BGRA 160x120 (paisagem, sensor 90°): metade esquerda vermelha
    const w = 160, h = 120;
    final b = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        final vermelho = x < w ~/ 2;
        b[i] = vermelho ? 30 : 200; b[i + 1] = vermelho ? 30 : 200; b[i + 2] = vermelho ? 200 : 200; b[i + 3] = 255;
      }
    }
    final fq = faixaDoQuadro(bytes: b, width: w, height: h, bytesPerRow: w * 4, bgra: true, rot: 90)!;
    expect(fq.faixa.w, greaterThan(fq.faixa.h)); // faixa larga e baixa
    expect(fq.faixa.cinza.length, fq.faixa.w * fq.faixa.h);
    expect(fq.faixa.vermelho.contains(1), isTrue);
    expect(fq.faixa.vermelho.contains(0), isTrue);
    expect(faixaDoQuadro(bytes: b, width: w, height: h, bytesPerRow: w * 4, bgra: true, rot: 45), isNull);
  });

  test('leitura com casas decimais (roletes vermelhos)', () {
    expect(fmtNum('2689,58'), '2${espacoFino}689,58');
    expect(parteInteira('2689,58'), 2689);
    expect(parteInteira('0763'), 763);
    expect(const Leitura(1, 'agua', '2689,58', null, false).numero, 2689);
  });
}
