import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:leituras_predio/digitos.dart';
import 'package:leituras_predio/ocr.dart';

/// Simula a faixa do quadro da câmera (1080×1920) a partir de um print da tela
/// do iPhone (1179×2556, prévia em "cover"), na [escala] do quadro.
Faixa faixaDoPrint(String arquivo, {double escala = 1 / 1.331, double brilho = 1}) {
  final p = img.decodePng(File(arquivo).readAsBytesSync())!;
  var band = img.copyCrop(p, x: 15, y: (0.36 * p.height).round(), width: 1150, height: (0.22 * p.height).round());
  band = img.copyResize(band, width: (band.width * escala).round(), interpolation: img.Interpolation.linear);
  if (brilho != 1) band = img.adjustColor(band, brightness: brilho);
  final rgba = band.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
  return faixaDeRgba(rgba, band.width, band.height);
}

/// Quadro BGRA do sensor (paisagem 1920×1080, rotação 90°) a partir do print,
/// como chega da câmera. [escala] > 1 = dígitos menores (celular mais longe).
Uint8List quadroDoPrint(img.Image print, double escala) {
  final r = img.copyResize(print, width: (print.width / (escala * 1.331)).round(), interpolation: img.Interpolation.linear);
  // o usuário encaixa os dígitos na moldura: centro dos dígitos (45,5% do print) no centro dela (47%)
  final dx = (1080 - r.width) ~/ 2, dy = (0.47 * 1920 - 0.455 * r.height).round();
  final out = Uint8List(1920 * 1080 * 4);
  for (var sy = 0; sy < 1080; sy++) {
    for (var sx = 0; sx < 1920; sx++) {
      final px = 1079 - sy - dx, py = sx - dy; // pixel do quadro em pé → pixel do print reduzido
      final o = (sy * 1920 + sx) * 4;
      if (px < 0 || py < 0 || px >= r.width || py >= r.height) {
        out[o] = out[o + 1] = out[o + 2] = 128;
      } else {
        final p = r.getPixel(px, py);
        out[o] = p.b.toInt();
        out[o + 1] = p.g.toInt();
        out[o + 2] = p.r.toInt();
      }
      out[o + 3] = 255;
    }
  }
  return out;
}

/// Quadro como o iPhone entrega de verdade (medido no aparelho em 2026-10-20):
/// BGRA JÁ EM PÉ, 1080×1920, com 4352 bytes por linha (1088 px, 8 de enchimento).
Uint8List quadroIphoneDoPrint(img.Image print, double escala) {
  const w = 1080, h = 1920, bpr = 4352;
  final r = img.copyResize(print, width: (print.width / (escala * 1.331)).round(), interpolation: img.Interpolation.linear);
  final dx = (w - r.width) ~/ 2, dy = (0.47 * h - 0.455 * r.height).round();
  final out = Uint8List(bpr * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final px = x - dx, py = y - dy;
      final o = y * bpr + x * 4;
      if (px < 0 || py < 0 || px >= r.width || py >= r.height) {
        out[o] = out[o + 1] = out[o + 2] = 128;
      } else {
        final p = r.getPixel(px, py);
        out[o] = p.b.toInt();
        out[o + 1] = p.g.toInt();
        out[o + 2] = p.r.toInt();
      }
      out[o + 3] = 255;
    }
  }
  return out;
}

/// Quadro BGRA do iPhone (em pé, 1080×1920, 4352 bytes/linha) com [foto] posta de
/// modo que o ponto ([cx], [cy]) (frações da foto) caia no centro da moldura,
/// ampliada [zoom]× em relação ao tamanho original da foto em pixels.
Uint8List quadroIphoneDeFoto(img.Image foto, {required double cx, required double cy, required double zoom}) {
  const w = 1080, h = 1920, bpr = 4352;
  final r = img.copyResize(foto, width: (foto.width * zoom).round(), interpolation: img.Interpolation.linear);
  final dx = (w / 2 - cx * r.width).round(), dy = (0.47 * h - cy * r.height).round();
  final out = Uint8List(bpr * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final px = x - dx, py = y - dy;
      final o = y * bpr + x * 4;
      if (px < 0 || py < 0 || px >= r.width || py >= r.height) {
        out[o] = out[o + 1] = out[o + 2] = 30;
      } else {
        final p = r.getPixel(px, py);
        out[o] = p.b.toInt();
        out[o + 1] = p.g.toInt();
        out[o + 2] = p.r.toInt();
      }
      out[o + 3] = 255;
    }
  }
  return out;
}

void main() {
  test('rotação: buffer em pé (iOS) não gira; deitado (Android) gira pelo sensor', () {
    expect(rotacaoDoQuadro(1080, 1920, 90), 0);
    expect(rotacaoDoQuadro(1920, 1080, 90), 90);
    expect(rotacaoDoQuadro(1920, 1080, 270), 270);
  });

  test('gás, 2º print do app (inclinado, 01464044): acha os 8 roletes', () {
    final tela = img.decodePng(File('test/fixtures/medidor_gas_camera2.png').readAsBytesSync())!;
    final q = quadroIphoneDeFoto(tela, cx: 0.45, cy: 0.347, zoom: 1.2);
    final fq = faixaDoQuadro(bytes: q, width: 1080, height: 1920, bytesPerRow: 4352, bgra: true, rot: 0)!;
    final linhas = acharLinhas(fq.faixa);
    expect(linhas.first.claro, isTrue);
    expect(linhas.first.n, 8, reason: 'a primeira linha (a que o OCR lê primeiro) tem de ter os 8');
  });

  test('busca com dica (polaridade/kernel/limiar do quadro anterior) acha a mesma fileira e é bem mais rápida', () {
    final casos = [
      faixaDoQuadro(bytes: quadroIphoneDoPrint(img.decodePng(File('test/fixtures/medidor_agua_claro.png').readAsBytesSync())!, 1.0), width: 1080, height: 1920, bytesPerRow: 4352, bgra: true, rot: 0)!.faixa,
      faixaDoQuadro(bytes: quadroIphoneDeFoto(img.decodePng(File('test/fixtures/medidor_gas_camera2.png').readAsBytesSync())!, cx: 0.45, cy: 0.347, zoom: 1.2), width: 1080, height: 1920, bytesPerRow: 4352, bgra: true, rot: 0)!.faixa,
    ];
    for (final f in casos) {
      final t1 = Stopwatch()..start();
      final completa = acharLinhas(f);
      t1.stop();
      final d = completa.first.dica;
      expect(d, isNotNull);
      final t2 = Stopwatch()..start();
      final rapida = acharLinhas(f, alturaPrevista: completa.first.alturaDigito, dica: d);
      t2.stop();
      expect(rapida.first.n, completa.first.n);
      expect(rapida.first.claro, completa.first.claro);
      expect(t2.elapsedMicroseconds * 3, lessThan(t1.elapsedMicroseconds), reason: 'com dica: ${t2.elapsedMilliseconds} ms; completa: ${t1.elapsedMilliseconds} ms');
    }
  });

  group('medidor de gás LAO na câmera (print do app, 2026-10-22): 8 roletes', () {
    final tela = img.decodePng(File('test/fixtures/medidor_gas_camera.png').readAsBytesSync())!;
    final variantes = {
      'base': tela,
      'escuro': img.adjustColor(tela.clone(), brightness: 0.6),
      'desfoque': img.gaussianBlur(tela.clone(), radius: 1),
      'giro2': img.copyRotate(tela.clone(), angle: 2, interpolation: img.Interpolation.linear),
    };
    for (final v in variantes.entries) {
      // o print do app é o caso real; as variantes pioradas (luz, desfoque, giro)
      // são teste de esforço: aí basta não perder a fileira
      final minimo = v.key == 'base' ? 8 : 6;
      test('${v.key}: fileira com ao menos $minimo dos 8 roletes', () {
        final q = quadroIphoneDoPrint(v.value, 1.0);
        final fq = faixaDoQuadro(bytes: q, width: 1080, height: 1920, bytesPerRow: 4352, bgra: true, rot: 0)!;
        final linhas = acharLinhas(fq.faixa);
        final ns = linhas.where((l) => l.claro).map((l) => l.n).toSet();
        expect(ns.any((n) => n >= minimo), isTrue, reason: 'linhas claras: $ns');
      });
    }
  });

  group('medidor de gás LAO (foto real do usuário, pouca resolução: dígitos de ~25 px)', () {
    final foto = img.decodeJpg(File('test/fixtures/medidor_gas_lao.jpg').readAsBytesSync())!;
    // acima de ~1,3× a foto só ficaria ampliada e borrada: não representa a câmera
    for (final z in [1.3]) {
      test('$z×: acha a fileira (≥ 7 de 8 roletes) com dígitos claros', () {
        final q = quadroIphoneDeFoto(foto, cx: 0.475, cy: 0.327, zoom: z);
        final fq = faixaDoQuadro(bytes: q, width: 1080, height: 1920, bytesPerRow: 4352, bgra: true, rot: 0)!;
        final linhas = acharLinhas(fq.faixa);
        expect(linhas, isNotEmpty);
        // alguma das linhas claras tem a fileira completa (8) ou quase
        final ns = linhas.where((l) => l.claro).map((l) => l.n).toSet();
        expect(ns.any((n) => n >= 7 && n <= 9), isTrue, reason: 'linhas: $ns');
      });
    }
  });

  group('medidor do apto 701: 268958 (o último rolete girando entra)', () {
    final base = img.decodePng(File('test/fixtures/medidor_agua_701.png').readAsBytesSync())!;
    for (final esc in [1.6, 1.33, 1.0]) {
      test('${esc}x', () {
        final q = quadroIphoneDoPrint(base, esc);
        final fq = faixaDoQuadro(bytes: q, width: 1080, height: 1920, bytesPerRow: 4352, bgra: true, rot: 0)!;
        final linhas = acharLinhas(fq.faixa);
        expect([linhas.first.claro, linhas.first.n, linhas.first.decimais], [false, 6, 2]);
      });
    }
  });

  group('quadro real do iPhone (em pé, linha com enchimento)', () {
    for (final nome in ['medidor_agua_claro', 'medidor_agua_escuro']) {
      final base = img.decodePng(File('test/fixtures/$nome.png').readAsBytesSync())!;
      for (final esc in [1.6, 1.33, 1.0, 0.8]) {
        test('$nome ${esc}x', () {
          final q = quadroIphoneDoPrint(base, esc);
          final rot = rotacaoDoQuadro(1080, 1920, 90);
          final fq = faixaDoQuadro(bytes: q, width: 1080, height: 1920, bytesPerRow: 4352, bgra: true, rot: rot)!;
          expect(fq.faixa.w, greaterThan(fq.faixa.h * 2), reason: 'faixa larga e baixa, como a moldura');
          final linhas = acharLinhas(fq.faixa);
          expect(linhas, isNotEmpty);
          expect(linhas.first.claro, isFalse);
          // leitura completa: 4 pretos + 2 vermelhos, um número só (076360)
          expect([linhas.first.n, linhas.first.decimais], [6, 2]);
          expect(linhas.where((l) => !l.claro && l.decimais == 0), isEmpty, reason: 'só os pretos seria outro número');
        });
      }
    }
  });

  group('caminho ao vivo (quadro do sensor girado)', () {
    for (final nome in ['medidor_agua_claro', 'medidor_agua_escuro']) {
      final base = img.decodePng(File('test/fixtures/$nome.png').readAsBytesSync())!;
      final variantes = {
        'base': base.clone(),
        'escuro': img.adjustColor(base.clone(), brightness: 0.5),
        'blur': img.gaussianBlur(base.clone(), radius: 2),
        'giro3': img.copyRotate(base.clone(), angle: 3, interpolation: img.Interpolation.linear),
      };
      for (final v in variantes.entries) {
        for (final esc in [1.6, 1.33, 1.0, 0.8]) {
          test('$nome ${v.key} ${esc}x', () {
            final q = quadroDoPrint(v.value, esc);
            final fq = faixaDoQuadro(bytes: q, width: 1920, height: 1080, bytesPerRow: 1920 * 4, bgra: true, rot: 90)!;
            final linhas = acharLinhas(fq.faixa);
            expect(linhas, isNotEmpty);
            expect(linhas.first.claro, isFalse, reason: 'dígitos escuros vêm primeiro');
            expect([linhas.first.n, linhas.first.decimais], [6, 2]);
          });
        }
      }
    }
  });

  final saida = Platform.environment['DIGITOS_SAIDA'];
  for (final nome in ['medidor_agua_claro', 'medidor_agua_escuro']) {
    for (final esc in [0.55, 1 / 1.331, 1.0]) {
      test('$nome em escala ${esc.toStringAsFixed(2)}: acha 4 dígitos pretos (0763)', () {
        final f = faixaDoPrint('test/fixtures/$nome.png', escala: esc);
        final t = Stopwatch()..start();
        final linhas = acharLinhas(f);
        t.stop();
        final escura = linhas.firstWhere((l) => !l.claro);
        expect([escura.n, escura.decimais], [6, 2]);
        // dígitos em ordem, mesma altura, sem sobrepor
        for (var i = 1; i < escura.n; i++) {
          expect(escura.caixas[i].x0, greaterThan(escura.caixas[i - 1].x1 - 2));
        }
        if (saida != null) {
          for (final l in linhas) {
            final im = img.Image.fromBytes(width: l.largura, height: l.altura, bytes: l.imagem.buffer, numChannels: 1);
            File('$saida/${nome}_${(esc * 100).round()}_${l.claro ? 'claro' : 'escuro'}.png').writeAsBytesSync(img.encodePng(im));
          }
        }
        // ignore: avoid_print
        print('$nome ${(esc * 100).round()}%: ${linhas.map((l) => '${l.claro ? 'claro' : 'escuro'} n=${l.n} h=${l.alturaDigito}').join(' · ')} · ${t.elapsedMilliseconds} ms');
      });
    }
  }

  test('linha recomposta: só aceita dígitos e na quantidade certa', () {
    expect(digitosDaLinha('0763', 4), '0763');
    expect(digitosDaLinha('O7 6S', 4), '0765');
    expect(digitosDaLinha('0763', 5), isNull);
    expect(digitosDaLinha('(44', 3), isNull);
  });
}
