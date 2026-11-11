// Ponte do isolamento de dígitos (lib/digitos.dart, o MESMO do app) para o
// navegador. Compilado com `dart compile js` por web_app/montar.sh; roda dentro
// do web worker (web_app/ocr_worker.js). Não editar o .js gerado.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:leituras_predio/digitos.dart';

@JS('prumoLinhas')
external set _prumoLinhas(JSFunction f);

void main() {
  _prumoLinhas = _linhas.toJS;
}

/// Recorta a faixa [bx0, by0, bw, bh] da imagem RGBA [w]×[h] e devolve as
/// linhas de dígitos achadas, cada uma já recomposta (cinza, fundo branco).
JSArray<JSObject> _linhas(JSUint8Array rgbaJs, JSNumber wJs, JSNumber hJs, JSNumber bx0Js, JSNumber by0Js, JSNumber bwJs, JSNumber bhJs) {
  final rgba = rgbaJs.toDart;
  final w = wJs.toDartInt, h = hJs.toDartInt;
  final bx0 = bx0Js.toDartInt.clamp(0, w - 1), by0 = by0Js.toDartInt.clamp(0, h - 1);
  final bw = bwJs.toDartInt.clamp(1, w - bx0), bh = bhJs.toDartInt.clamp(1, h - by0);
  final g = Uint8List(bw * bh), red = Uint8List(bw * bh);
  for (var y = 0; y < bh; y++) {
    for (var x = 0; x < bw; x++) {
      final i = ((by0 + y) * w + bx0 + x) * 4, o = y * bw + x;
      final r = rgba[i], gg = rgba[i + 1], b = rgba[i + 2];
      g[o] = (r * 299 + gg * 587 + b * 114) ~/ 1000;
      if (ehVermelho(r, gg, b)) red[o] = 1;
    }
  }
  final saida = <JSObject>[];
  for (final l in acharLinhas(Faixa(g, red, bw, bh))) {
    final c = l.caixa;
    final o = JSObject()
      ..setProperty('img'.toJS, l.imagem.toJS)
      ..setProperty('w'.toJS, l.largura.toJS)
      ..setProperty('h'.toJS, l.altura.toJS)
      ..setProperty('n'.toJS, l.n.toJS)
      ..setProperty('variante'.toJS, l.variante.toJS)
      ..setProperty('decimais'.toJS, l.decimais.toJS)
      ..setProperty('alturaDigito'.toJS, l.alturaDigito.toJS)
      ..setProperty('box'.toJS, [bx0 + c.x0, by0 + c.y0, bx0 + c.x1, by0 + c.y1].map((v) => v.toJS).toList().toJS);
    saida.add(o);
  }
  return saida.toJS;
}
