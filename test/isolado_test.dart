import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:leituras_predio/digitos.dart';
import 'package:leituras_predio/ocr.dart';
import 'package:leituras_predio/telas/camera.dart';

import 'digitos_test.dart' show quadroDoPrint;

/// Imita o State da câmera: segura algo que não pode ir para outro isolate e
/// tem outro closure usando `this` no mesmo método (era o que quebrava a leitura).
class _TelaFalsa {
  final porta = ReceivePort();
  int? lido;
  Future<int?> quadro(Faixa f) async {
    final linhas = await acharLinhasIsolado(f, null);
    void guardar() => lido = linhas.where((l) => !l.claro).firstOrNull?.n;
    guardar();
    return lido;
  }
}

void main() {
  test('isolamento dos dígitos roda em outro isolate a partir do State', () async {
    final base = img.decodePng(File('test/fixtures/medidor_agua_claro.png').readAsBytesSync())!;
    final fq = faixaDoQuadro(bytes: quadroDoPrint(base, 1.0), width: 1920, height: 1080, bytesPerRow: 1920 * 4, bgra: true, rot: 90)!;
    final t = _TelaFalsa();
    expect(await t.quadro(fq.faixa), 6);
    t.porta.close();
  });

  test('camera.dart só chama Isolate.run em funções de topo', () {
    final src = File('lib/telas/camera.dart').readAsStringSync();
    final marco = src.indexOf('// Trabalho pesado em outro isolate.');
    expect(marco, greaterThan(0));
    expect(src.substring(0, marco).contains('Isolate.run('), isFalse);
  });
}
