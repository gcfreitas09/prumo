import 'dart:typed_data';
import 'dart:ui';

import 'digitos.dart';

/// Leitura achada num quadro e onde ela está (coordenadas do quadro em pé).
class Candidato {
  final String valor;
  final Rect box;
  const Candidato(this.valor, this.box);
}

/// Luminância média (0–255) amostrada do primeiro plano da imagem.
/// NV21 (Android): bytes iniciais são o canal Y. BGRA (iOS): 4 bytes por pixel.
double luminancia(Uint8List bytes, {required bool bgra}) {
  if (bytes.isEmpty) return 255;
  var soma = 0, n = 0;
  if (bgra) {
    for (var i = 0; i + 2 < bytes.length; i += 4 * 97) {
      soma += (bytes[i + 2] * 299 + bytes[i + 1] * 587 + bytes[i] * 114) ~/ 1000;
      n++;
    }
  } else {
    final soY = bytes.length * 2 ~/ 3; // o resto do NV21 é crominância
    for (var i = 0; i < soY; i += 97) {
      soma += bytes[i];
      n++;
    }
  }
  return n == 0 ? 255 : soma / n;
}


/// Votação entre quadros: junta as últimas leituras e decide dígito a dígito,
/// então um dígito errado em um quadro isolado não derruba a leitura.
class Votacao {
  final int janela;
  final int minimo;
  final List<String> _amostras = [];
  Votacao({this.janela = 8, this.minimo = 3});

  void limpar() => _amostras.clear();

  /// [valor] null = quadro sem leitura plausível (não zera, só não conta).
  void add(String? valor) {
    if (valor == null) return;
    _amostras.add(valor);
    if (_amostras.length > janela) _amostras.removeAt(0);
  }

  /// Leitura consensual ou null se ainda não há confiança.
  String? consenso() {
    if (_amostras.length < minimo) return null;
    // 1) mesmo número inteiro em ≥ minimo quadros da janela
    final cont = <String, int>{};
    for (final a in _amostras) {
      cont[a] = (cont[a] ?? 0) + 1;
    }
    final top = cont.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (top.value >= minimo) return top.key;
    // 2) mesmo comprimento: maioria por posição (≥ 60% em cada dígito)
    final porTam = <int, List<String>>{};
    for (final a in _amostras) {
      (porTam[a.length] ??= []).add(a);
    }
    final grupo = porTam.values.reduce((a, b) => a.length >= b.length ? a : b);
    if (grupo.length < minimo) return null;
    final out = StringBuffer();
    for (var i = 0; i < grupo.first.length; i++) {
      final d = <String, int>{};
      for (final a in grupo) {
        d[a[i]] = (d[a[i]] ?? 0) + 1;
      }
      final m = d.entries.reduce((a, b) => a.value >= b.value ? a : b);
      // o último rolete pode estar girando (entre dois dígitos): ali basta ser o
      // mais votado; nos outros, maioria de 60%
      final ultimo = i == grupo.first.length - 1;
      if (m.value / grupo.length < (ultimo ? 0.34 : 0.6)) return null;
      out.write(m.key);
    }
    return out.toString();
  }
}


// ---------------------------------------------------------------------------
// Faixa de leitura: recorte em pé da moldura central, em cinza, com a máscara
// do vermelho (casas decimais) para o isolamento dos dígitos (digitos.dart).

/// Moldura (frações do quadro em pé) onde o usuário encaixa os dígitos.
const faixaX0 = 0.10, faixaX1 = 0.90, faixaY0 = 0.36, faixaY1 = 0.58;

class FaixaQuadro {
  final Faixa faixa;
  final int x0, y0; // origem no quadro em pé
  const FaixaQuadro(this.faixa, this.x0, this.y0);
}

/// Faixa a partir do quadro da câmera. [rot]: quanto girar o buffer para ficar
/// em pé — 0 (iOS já entrega em pé), 90 ou 270 (Android entrega deitado).
/// Use [rotacaoDoQuadro] para decidir; não confie só no sensorOrientation.
FaixaQuadro? faixaDoQuadro({
  required Uint8List bytes,
  required int width,
  required int height,
  required int bytesPerRow,
  required bool bgra,
  required int rot,
}) {
  if (rot != 0 && rot != 90 && rot != 270) return null;
  final deitado = rot != 0;
  final uw = deitado ? height : width, uh = deitado ? width : height; // quadro em pé
  final x0 = (faixaX0 * uw).round() & ~1, y0 = (faixaY0 * uh).round() & ~1;
  final w = (((faixaX1 - faixaX0) * uw).round()) & ~1, h = (((faixaY1 - faixaY0) * uh).round()) & ~1;
  final g = Uint8List(w * h), red = Uint8List(w * h);
  final uvBase = bytesPerRow * height;
  for (var uy = 0; uy < h; uy++) {
    for (var ux = 0; ux < w; ux++) {
      final px = x0 + ux, py = y0 + uy;
      final sx = rot == 0 ? px : (rot == 90 ? py : width - 1 - py);
      final sy = rot == 0 ? py : (rot == 90 ? height - 1 - px : px);
      final o = uy * w + ux;
      if (bgra) {
        final i = sy * bytesPerRow + sx * 4;
        final b = bytes[i], gg = bytes[i + 1], r = bytes[i + 2];
        g[o] = (r * 299 + gg * 587 + b * 114) ~/ 1000;
        if (ehVermelho(r, gg, b)) red[o] = 1;
      } else {
        final y = bytes[sy * bytesPerRow + sx];
        g[o] = y;
        final j = uvBase + (sy >> 1) * bytesPerRow + ((sx >> 1) << 1);
        if (j + 1 < bytes.length) {
          final v = bytes[j] - 128, u = bytes[j + 1] - 128; // NV21: V antes de U
          final r = (y + 1.402 * v).round().clamp(0, 255);
          final gg = (y - 0.344 * u - 0.714 * v).round().clamp(0, 255);
          final b = (y + 1.772 * u).round().clamp(0, 255);
          if (ehVermelho(r, gg, b)) red[o] = 1;
        }
      }
    }
  }
  return FaixaQuadro(Faixa(g, red, w, h), x0, y0);
}

/// Rotação para pôr o buffer em pé: se ele já vem em pé (mais alto que largo,
/// caso do iOS), 0; senão, a orientação do sensor.
int rotacaoDoQuadro(int largura, int altura, int sensor) => largura < altura ? 0 : sensor;

/// Faixa a partir de pixels RGBA já em pé (foto do botão Capturar).
Faixa faixaDeRgba(Uint8List rgba, int w, int h) {
  final g = Uint8List(w * h), red = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    final r = rgba[i * 4], gg = rgba[i * 4 + 1], b = rgba[i * 4 + 2];
    g[i] = (r * 299 + gg * 587 + b * 114) ~/ 1000;
    if (ehVermelho(r, gg, b)) red[i] = 1;
  }
  return Faixa(g, red, w, h);
}

const _trocaLinha = {
  'O': '0', 'o': '0', 'D': '0', 'Q': '0', 'U': '0', 'u': '0',
  'I': '1', 'l': '1', 'i': '1', '|': '1', '!': '1', 'L': '1', 'j': '1', 'J': '1', 'T': '7',
  'Z': '2', 'z': '2', 'S': '5', 's': '5', 'G': '6', 'b': '6', 'B': '8', 'g': '9', 'q': '9', 'A': '4',
};

/// Texto que o OCR leu da linha recomposta → dígitos, só se forem exatamente
/// [n] (um por componente). A imagem só tem dígitos, então troca à vontade.
String? digitosDaLinha(String texto, int n) {
  final b = StringBuffer();
  for (final c in texto.split('')) {
    if (RegExp(r'\d').hasMatch(c)) {
      b.write(c);
    } else if (_trocaLinha.containsKey(c)) {
      b.write(_trocaLinha[c]);
    } else if (RegExp(r"[\s.,:;'`´\-_~]").hasMatch(c)) {
      continue;
    } else {
      return null;
    }
  }
  final s = b.toString();
  return s.length == n ? s : null;
}

/// Cinza → NV21 (Android): plano Y + crominância neutra.
Uint8List cinzaParaNv21(Uint8List g, int w, int h) {
  final out = Uint8List(w * h + w * h ~/ 2)..fillRange(w * h, w * h + w * h ~/ 2, 128);
  out.setRange(0, w * h, g);
  return out;
}

/// Cinza → BGRA (iOS).
Uint8List cinzaParaBgra(Uint8List g, int w, int h) {
  final out = Uint8List(w * h * 4);
  for (var i = 0; i < g.length; i++) {
    final j = i * 4;
    out[j] = g[i];
    out[j + 1] = g[i];
    out[j + 2] = g[i];
    out[j + 3] = 255;
  }
  return out;
}
