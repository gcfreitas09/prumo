// Isola a linha de dígitos de um medidor de roletes antes do OCR.
//
// O ML Kit erra quando lê a faixa inteira: as sombras entre os roletes viram
// dígitos falsos ("047636" para 0763). Aqui a faixa passa por um top-hat
// morfológico (sobram só traços finos; divisórias largas somem), os traços
// viram componentes conexos e escolhemos a fileira de componentes com a mesma
// altura, alinhados e com passo regular — os dígitos. Esses dígitos são
// recompostos limpos, lado a lado, numa imagem pequena que vai para o OCR.
import 'dart:math' as math;
import 'dart:typed_data';

class Caixa {
  final int x0, y0, x1, y1;
  const Caixa(this.x0, this.y0, this.x1, this.y1);
  int get w => x1 - x0;
  int get h => y1 - y0;
  double get cx => (x0 + x1) / 2;
  double get cy => (y0 + y1) / 2;
  Caixa uniao(Caixa o) => Caixa(math.min(x0, o.x0), math.min(y0, o.y0), math.max(x1, o.x1), math.max(y1, o.y1));
}

/// Faixa em pé: cinza (0–255) e máscara de vermelho (1 = pixel vermelho).
class Faixa {
  final Uint8List cinza, vermelho;
  final int w, h;
  const Faixa(this.cinza, this.vermelho, this.w, this.h);
}

/// Linha de dígitos encontrada, já recomposta em preto sobre branco.
/// Polaridade, kernel do top-hat e limiar que acharam a fileira. A busca completa
/// testa 2 polaridades × 5 kernels × 2 limiares (~0,4 s); com a dica é 1 só passada.
class Dica {
  final bool claro, frouxo;
  final int k;
  const Dica(this.claro, this.k, this.frouxo);
}

class LinhaDigitos {
  final Uint8List imagem;
  final int largura, altura;
  final List<Caixa> caixas; // posição de cada dígito na faixa
  final bool claro; // dígitos claros sobre fundo escuro
  final int alturaDigito;
  final int decimais; // quantos dos últimos dígitos são casas decimais (vermelhos)
  /// Combinação de busca que achou esta linha: no próximo quadro dá para ir direto nela.
  final Dica? dica;
  /// Como a linha foi montada ("cinza", "mascara", "grossa1"…): a câmera tenta
  /// primeiro a variante que leu da última vez.
  final String variante;
  const LinhaDigitos(this.imagem, this.largura, this.altura, this.caixas, this.claro, this.alturaDigito, {this.decimais = 0, this.dica, this.variante = ''});
  LinhaDigitos marcada(Dica d, String v) => LinhaDigitos(imagem, largura, altura, caixas, claro, alturaDigito, decimais: decimais, dica: d, variante: v);
  int get n => caixas.length;
  Caixa get caixa => caixas.reduce((a, b) => a.uniao(b));
}

/// Vermelho das casas decimais (relativo, funciona com pouca luz).
bool ehVermelho(int r, int g, int b) {
  final mx = g > b ? g : b;
  return r > 25 && r - mx > math.max(10, r ~/ 4) && r * 10 > mx * 13;
}

// ignore: prefer_function_declarations_over_variables
void Function(String, Uint8List, int, int)? dbgImagem;

/// Vão máximo entre dígitos vizinhos, em alturas de dígito. Medidores de água
/// têm roletes colados (~0,2); os de gás costumam ser bem mais espaçados.
const _gapMax = 2.4;

/// Procura a linha de dígitos nas duas polaridades. [alturaPrevista]: altura
/// do dígito no quadro anterior (estreita a busca e economiza tempo).
List<LinhaDigitos> acharLinhas(Faixa f, {int? alturaPrevista, Dica? dica, void Function(String)? log}) {
  final w = f.w, h = f.h, n = w * h;
  final ks = dica != null
      ? [dica.k]
      : alturaPrevista != null
      ? [_impar((alturaPrevista * 0.2).round())]
      : {for (final kf in const [0.015, 0.022, 0.032, 0.045, 0.065]) _impar((h * kf).round())}.toList();

  // contraste esticado entre os percentis 2 e 98, sem contar o vermelho
  final hist = List<int>.filled(256, 0);
  var total = 0;
  for (var i = 0; i < n; i++) {
    if (f.vermelho[i] == 0) {
      hist[f.cinza[i]]++;
      total++;
    }
  }
  var lo = 0, hi = 255;
  if (total > 0) {
    // percentis 0,3 e 99,7: dígitos pequenos ocupam bem menos de 2% da faixa
    // e, com 2%, o traço escuro caía fora da escala e o contraste sumia
    var acc = 0;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= total * 0.003) { lo = v; break; }
    }
    acc = 0;
    for (var v = 255; v >= 0; v--) {
      acc += hist[v];
      if (acc >= total * 0.003) { hi = v; break; }
    }
  }
  final esc = math.max(hi - lo, 1);
  final cinza = Uint8List(n);
  for (var i = 0; i < n; i++) {
    cinza[i] = ((f.cinza[i] - lo) * 255 ~/ esc).clamp(0, 255);
  }
  // tira pontos vermelhos isolados (ruído de cor em pouca luz) antes de dilatar
  final verm = _filtro2d(f.vermelho, w, h, 3, true);
  final vermelho = _dilatarBin(verm, w, h, 3);
  final zonaVermelha = _dilatarBin(verm, w, h, math.max(2, h ~/ 60) + 3);

  final saida = <LinhaDigitos>[];
  for (final claro in dica != null ? [dica.claro] : const [false, true]) {
    final d = Uint8List(n);
    for (var i = 0; i < n; i++) {
      // dígitos escuros: o vermelho some (vira fundo). Dígitos claros: o vermelho é
      // fundo de rolete (gás) e os dígitos sobre ele aparecem na luminância — não apagar
      final g = (vermelho[i] == 1 && !claro) ? 255 : cinza[i];
      d[i] = claro ? g : 255 - g;
    }
    // Dois limiares por tamanho de traço: o rigoroso (traço forte; o comportamento
    // de sempre) e o frouxo (dígito claro de baixo contraste, como no gás). O
    // frouxo só ganha se achar bem mais dígitos (+2): evita trocar uma fileira boa
    // por outra com sujeira.
    _Linha? estrito, frouxo;
    for (final k in ks) {
      final top = _topHat(d, w, h, k);
      final p995 = _percentil(top, 0.995);
      final otsu = _otsu(top);
      for (final fator in dica != null ? [dica.frouxo ? 0.22 : 0.45] : const [0.45, 0.22]) {
        // rigoroso: o limiar de sempre (Otsu limitado a 45% do traço mais forte);
        // frouxo: 22% do traço mais forte
        final t = fator == 0.45 ? math.max(20, math.min(otsu, (p995 * 0.45).round())) : math.max(12, (p995 * 0.22).round());
        var bin = Uint8List(n);
        for (var i = 0; i < n; i++) {
          if (top[i] > t) bin[i] = 1;
        }
        // abertura binária 3×3: corta pontes finas entre o dígito e as molduras
        if (k >= 9) bin = _filtro2d(_filtro2d(bin, w, h, 3, true), w, h, 3, false);
        // retas longas (molduras, códigos de barras) ligavam vários dígitos num bloco só
        _cortarRetas(bin, w, h, 9 * k, 12 * k);
        dbgImagem?.call('${claro ? 'c' : 'e'}_k${k}_t$t', bin, w, h);
        final r = _melhorLinha(bin, claro ? Uint8List(n) : zonaVermelha, w, h, k, log: log, estender: claro);
        log?.call('${claro ? 'claro' : 'escuro'} k=$k t=$t → ${r == null ? '-' : 'n=${r.membros.length} h=${r.alturaMedia} ${r.membros.map((c) => '${c.x0}:${c.h}x${c.w}e${c.esp}').join(' ')}'}');
        if (r == null) continue;
        r
          ..k = k
          ..frouxo = fator != 0.45;
        if (fator == 0.45) {
          if (_melhorQue(r, estrito)) estrito = r;
        } else if (_melhorQue(r, frouxo)) {
          frouxo = r;
        }
      }
    }
    final _Linha? melhor = (frouxo != null && (estrito == null || frouxo.membros.length > estrito.membros.length)) ? frouxo : estrito;
    if (melhor == null) continue;
    final dicaAchada = Dica(claro, melhor.k, melhor.frouxo);
    void add(LinhaDigitos l, String v) => saida.add(l.marcada(dicaAchada, '${claro ? 'c' : 'e'}-$v'));
    {
      // casas decimais vermelhas à direita (qualquer polaridade: gás costuma ter rolete preto com dígito claro): primeiro a leitura completa, depois só os pretos
      final dec = _decimais(melhor.membros, melhor.alturaMedia, _dilatarBin(verm, w, h, 1), w, h);
      log?.call('decimais: ${dec.map((c) => '${c.x0}:${c.h}x${c.w}').join(' ')}');
      if (dec.isNotEmpty) {
        // com roletes vermelhos, só vale a leitura completa (só os pretos seria outro número)
        final membros = [...melhor.membros, ...dec];
        final completa = _compor(membros, w, melhor.alturaMedia, claro, decimais: dec.length);
        add(completa, 'mascara');
        add(_comporCinza(membros, cinza, w, h, melhor.alturaMedia, claro, decimais: dec.length), 'cinza');
        add(_engrossar(completa, 1), 'grossa1');
        continue;
      }
    }
    // 1º: os dígitos em tons de cinza (forma real do traço); depois as máscaras
    if (claro) add(_comporCinza(melhor.membros, cinza, w, h, melhor.alturaMedia, claro), 'cinza');
    final base = _compor(melhor.membros, w, melhor.alturaMedia, claro);
    add(base, 'mascara');
    if (!claro) add(_comporCinza(melhor.membros, cinza, w, h, melhor.alturaMedia, claro), 'cinza');
    final alt = melhor.alternativa;
    if (alt != null) add(_compor(alt, w, _mediana(alt.map((e) => e.h.toDouble()).toList()), claro), 'alternativa');
    // traço fino (gás: dígitos de LCD/rolete claro) vira letra no OCR; uma cópia
    // com o traço engrossado e outra maior dão mais uma chance de ler certo
    add(_engrossar(base, 1), 'grossa1');
    add(_engrossar(base, 2), 'grossa2');
  }
  return saida;
}

/// Apaga sequências de pixels ligados mais longas que [maxH] (linhas) ou [maxV]
/// (colunas): nenhum traço de dígito chega nesse comprimento.
void _cortarRetas(Uint8List b, int w, int h, int maxH, int maxV) {
  for (var y = 0; y < h; y++) {
    var ini = -1;
    for (var x = 0; x <= w; x++) {
      final on = x < w && b[y * w + x] == 1;
      if (on && ini < 0) ini = x;
      if (!on && ini >= 0) {
        if (x - ini > maxH) b.fillRange(y * w + ini, y * w + x, 0);
        ini = -1;
      }
    }
  }
  for (var x = 0; x < w; x++) {
    var ini = -1;
    for (var y = 0; y <= h; y++) {
      final on = y < h && b[y * w + x] == 1;
      if (on && ini < 0) ini = y;
      if (!on && ini >= 0) {
        if (y - ini > maxV) {
          for (var yy = ini; yy < y; yy++) {
            b[yy * w + x] = 0;
          }
        }
        ini = -1;
      }
    }
  }
}

int _impar(int k) => math.max(3, k | 1);

// ---------------------------------------------------------------- morfologia

/// Mínimo/máximo deslizante (janela k, centrada) em O(n) — van Herk/Gil-Werman.
void _filtro1d(Uint8List src, Uint8List dst, int inicio, int passo, int n, int k, bool minimo, Uint8List g, Uint8List s) {
  for (var i = 0; i < n; i++) {
    final v = src[inicio + i * passo];
    if (i % k == 0) {
      g[i] = v;
    } else {
      final p = g[i - 1];
      g[i] = minimo ? (v < p ? v : p) : (v > p ? v : p);
    }
  }
  for (var i = n - 1; i >= 0; i--) {
    final v = src[inicio + i * passo];
    if (i == n - 1 || (i + 1) % k == 0) {
      s[i] = v;
    } else {
      final p = s[i + 1];
      s[i] = minimo ? (v < p ? v : p) : (v > p ? v : p);
    }
  }
  final r = k ~/ 2;
  for (var i = 0; i < n; i++) {
    final l = i - r < 0 ? 0 : i - r;
    final rr = i + r >= n ? n - 1 : i + r;
    int v;
    if (l ~/ k == rr ~/ k) {
      v = l % k == 0 ? g[rr] : s[l];
    } else {
      final a = s[l], b = g[rr];
      v = minimo ? (a < b ? a : b) : (a > b ? a : b);
    }
    dst[inicio + i * passo] = v;
  }
}

Uint8List _filtro2d(Uint8List a, int w, int h, int k, bool minimo) {
  final m = math.max(w, h);
  final g = Uint8List(m), s = Uint8List(m);
  final tmp = Uint8List(w * h), out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    _filtro1d(a, tmp, y * w, 1, w, k, minimo, g, s);
  }
  for (var x = 0; x < w; x++) {
    _filtro1d(tmp, out, x, w, h, k, minimo, g, s);
  }
  return out;
}

/// Top-hat: mantém o que é mais estreito que k (traços), apaga o que é largo.
Uint8List _topHat(Uint8List d, int w, int h, int k) {
  final ab = _filtro2d(_filtro2d(d, w, h, k, true), w, h, k, false);
  final out = Uint8List(w * h);
  for (var i = 0; i < out.length; i++) {
    out[i] = d[i] - ab[i];
  }
  return out;
}

Uint8List _dilatarBin(Uint8List m, int w, int h, int raio) => _filtro2d(m, w, h, raio * 2 + 1, false);

int _percentil(Uint8List v, double q) {
  final hist = List<int>.filled(256, 0);
  for (final x in v) {
    hist[x]++;
  }
  final alvo = v.length * q;
  var acc = 0;
  for (var i = 0; i < 256; i++) {
    acc += hist[i];
    if (acc >= alvo) return i;
  }
  return 255;
}

int _otsu(Uint8List v) {
  final hist = List<int>.filled(256, 0);
  for (final x in v) {
    hist[x]++;
  }
  var soma = 0;
  for (var i = 0; i < 256; i++) {
    soma += i * hist[i];
  }
  var wB = 0, somaB = 0, t = 127;
  var melhor = -1.0;
  for (var i = 0; i < 256; i++) {
    wB += hist[i];
    if (wB == 0) continue;
    final wF = v.length - wB;
    if (wF == 0) break;
    somaB += i * hist[i];
    final mB = somaB / wB, mF = (soma - somaB) / wF;
    final vr = wB * wF * (mB - mF) * (mB - mF);
    if (vr > melhor) {
      melhor = vr;
      t = i;
    }
  }
  return t;
}

// ---------------------------------------------------------- componentes

class _Comp {
  int x0, y0, x1, y1, n, esp, verm;
  final List<int> ids;
  final Int32List rot; // mapa de rótulos de onde o componente saiu
  /// Dígito "por janela" (colado em sujeira): pinta os pixels ligados da janela.
  final Uint8List? mascara;
  _Comp(this.x0, this.y0, this.x1, this.y1, this.n, this.esp, this.verm, this.ids, this.rot, {this.mascara});
  int get w => x1 - x0;
  int get h => y1 - y0;
  Caixa get caixa => Caixa(x0, y0, x1, y1);
}

/// Duas fileiras na mesma altura da faixa são a MESMA fileira de roletes vista
/// por limiares diferentes: vale a que achou mais dígitos (a outra perdeu algum,
/// normalmente o da ponta colado na moldura). Em alturas diferentes, a pontuação.
bool _melhorQue(_Linha nova, _Linha? atual) {
  if (atual == null) return true;
  double cy(_Linha l) => l.membros.map((e) => (e.y0 + e.y1) / 2).reduce((a, b) => a + b) / l.membros.length;
  final mesmaFaixa = (cy(nova) - cy(atual)).abs() < 0.5 * math.max(nova.alturaMedia, atual.alturaMedia);
  final alturasParecidas = nova.alturaMedia > 0.75 * atual.alturaMedia && atual.alturaMedia > 0.75 * nova.alturaMedia;
  if (mesmaFaixa && alturasParecidas && nova.membros.length != atual.membros.length) {
    return nova.membros.length > atual.membros.length;
  }
  return nova.pontos > atual.pontos;
}

class _Linha {
  final List<_Comp> membros;
  /// Fileira sem os dígitos completados por janela: se a completa não ler, o OCR
  /// ainda tenta esta.
  final List<_Comp>? alternativa;
  final int w, h;
  final double alturaMedia;
  final double pontos;
  int k = 0;
  bool frouxo = false;
  _Linha(this.membros, this.w, this.h, this.alturaMedia, this.pontos, {this.alternativa});
}

/// Componentes conexos (vizinhança 8) com espessura do traço. Com [zonaVermelha],
/// descarta o que cai nela (contorno das casas decimais).
List<_Comp> _rotular(Uint8List bin, Uint8List? zonaVermelha, int w, int h) {
  final n = w * h;
  // distância (xadrez) até o fundo: metade da espessura do traço
  final dt = Uint8List(n);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (bin[i] == 0) continue;
      var m = 255;
      m = x > 0 ? math.min(m, dt[i - 1]) : 0;
      if (y > 0) {
        m = math.min(m, dt[i - w]);
        m = math.min(m, x > 0 ? dt[i - w - 1] : 0);
        m = math.min(m, x < w - 1 ? dt[i - w + 1] : 0);
      } else {
        m = 0;
      }
      dt[i] = math.min(m + 1, 255);
    }
  }
  for (var y = h - 1; y >= 0; y--) {
    for (var x = w - 1; x >= 0; x--) {
      final i = y * w + x;
      if (bin[i] == 0) continue;
      var m = 255;
      m = x < w - 1 ? math.min(m, dt[i + 1]) : 0;
      if (y < h - 1) {
        m = math.min(m, dt[i + w]);
        m = math.min(m, x < w - 1 ? dt[i + w + 1] : 0);
        m = math.min(m, x > 0 ? dt[i + w - 1] : 0);
      } else {
        m = 0;
      }
      dt[i] = math.min(dt[i], m + 1);
    }
  }

  // rótulos (vizinhança 8)
  final rot = Int32List(n);
  final pilha = Int32List(n);
  final comps = <_Comp>[];
  var prox = 0;
  for (var i0 = 0; i0 < n; i0++) {
    if (bin[i0] == 0 || rot[i0] != 0) continue;
    prox++;
    var topo = 0;
    pilha[topo++] = i0;
    rot[i0] = prox;
    var x0 = w, y0 = h, x1 = 0, y1 = 0, cont = 0, esp = 0, verm = 0;
    while (topo > 0) {
      final i = pilha[--topo];
      final x = i % w, y = i ~/ w;
      if (x < x0) x0 = x;
      if (x >= x1) x1 = x + 1;
      if (y < y0) y0 = y;
      if (y >= y1) y1 = y + 1;
      cont++;
      if (dt[i] > esp) esp = dt[i];
      if (zonaVermelha != null && zonaVermelha[i] == 1) verm++;
      for (var dy = -1; dy <= 1; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= w) continue;
          final j = yy * w + xx;
          if (bin[j] == 1 && rot[j] == 0) {
            rot[j] = prox;
            pilha[topo++] = j;
          }
        }
      }
    }
    // descarta ruído miúdo e o que está na zona das casas decimais vermelhas
    if (cont < 6 || y1 - y0 < 4) continue;
    if (verm > cont * 0.3) continue;
    comps.add(_Comp(x0, y0, x1, y1, cont, esp, verm, [prox], rot));
  }
  _juntarPartes(comps);
  return comps;
}

_Linha? _melhorLinha(Uint8List bin, Uint8List zonaVermelha, int w, int h, int k, {void Function(String)? log, bool estender = false}) {
  final comps = _rotular(bin, zonaVermelha, w, h);
  final rot0 = comps.isEmpty ? Int32List(w * h) : comps.first.rot;

  // candidatos a dígito
  final cand = <_Comp>[];
  for (final c in comps) {
    final cw = c.w, ch = c.h;
    final fill = c.n / (cw * ch);
    final motivo = ch < 12 || ch > 0.95 * h
        ? 'altura'
        : cw > 1.2 * ch || cw < 0.08 * ch
            ? 'largura'
            : fill < 0.08 || fill > 0.9
                ? 'preenchimento'
                : c.esp > 0.14 * ch
                    ? 'espessura' // mancha sólida (divisória), não traço
                    : null;
    if (log != null && ch >= 20) log('   comp ${c.x0},${c.y0} ${ch}x$cw e${c.esp} f${fill.toStringAsFixed(2)} ${motivo ?? 'ok'}');
    if (motivo == null) cand.add(c);
  }

  _Linha? melhor;
  for (final s in cand) {
    final hs = s.h.toDouble();
    // dígito com sujeira grudada em cima ou embaixo (sombra do rolete): corta na
    // altura da fileira, se o topo ou a base estiverem alinhados
    _Comp? naFileira(_Comp m, _Comp ref) {
      if ((m.h - hs).abs() <= 0.25 * hs) return m;
      if (m.h > hs && m.h <= 1.7 * hs) {
        if ((m.y0 - ref.y0).abs() <= 0.2 * hs) return _Comp(m.x0, m.y0, m.x1, m.y0 + ref.h, m.n, m.esp, m.verm, m.ids, m.rot);
        if ((m.y1 - ref.y1).abs() <= 0.2 * hs) return _Comp(m.x0, m.y1 - ref.h, m.x1, m.y1, m.n, m.esp, m.verm, m.ids, m.rot);
      }
      return null;
    }

    // fileira a partir da semente, vizinho a vizinho (aceita celular inclinado)
    final cadeia = [s];
    final usados = {s};
    for (final dir in const [1, -1]) {
      var cur = s;
      while (true) {
        _Comp? prox, original;
        for (final m0 in cand) {
          if (usados.contains(m0)) continue;
          final m = naFileira(m0, cur);
          if (m == null) continue;
          final gap = dir == 1 ? m.x0 - cur.x1 : cur.x0 - m.x1;
          if (gap < -0.2 * hs || gap > _gapMax * hs) continue;
          if (((m.y0 + m.y1) - (cur.y0 + cur.y1)).abs() / 2 > 0.3 * hs) continue;
          if (prox == null || gap < (dir == 1 ? prox.x0 - cur.x1 : cur.x0 - prox.x1)) {
            prox = m;
            original = m0;
          }
        }
        if (prox == null) break;
        cadeia.add(prox);
        usados.add(original!);
        cur = prox;
      }
    }
    cadeia.sort((a, b) => a.x0.compareTo(b.x0));
    final base = _podar(cadeia);
    if (base.length < 4) continue; // nenhum visor tem menos de 4 dígitos
    // tenta a fileira completada (dígitos colados na moldura); se ela não passar
    // nas conferências, fica a fileira original
    final tentativas = <List<_Comp>>[];
    if (estender) {
      final completa = List.of(base);
      _completarFileira(completa, bin, w, h, rot0);
      // o que foi completado passa pelas mesmas conferências de passo
      final limpa = _podar(completa);
      if (limpa.length > base.length) tentativas.add(limpa);
    }
    tentativas.add(base);
    for (final c in tentativas) {
      final pts = _pontos(c, w, h, k);
      if (pts == null) continue;
      final hm = _mediana(c.map((e) => e.h.toDouble()).toList());
      final alt = c.length != base.length ? base : null;
      final nova = _Linha(c, w, h, hm, pts, alternativa: alt);
      if (_melhorQue(nova, melhor)) melhor = nova;
      break;
    }
  }
  return melhor;
}

/// Junta pedaços do mesmo dígito (um "7" partido em dois, por exemplo).
void _juntarPartes(List<_Comp> cs) {
  var mudou = true;
  while (mudou) {
    mudou = false;
    for (var i = 0; i < cs.length && !mudou; i++) {
      for (var j = i + 1; j < cs.length; j++) {
        final a = cs[i], b = cs[j];
        final ov = math.min(a.x1, b.x1) - math.max(a.x0, b.x0);
        final nw = math.min(a.w, b.w);
        final gap = math.max(a.y0, b.y0) - math.min(a.y1, b.y1);
        // partes do mesmo dígito ficam uma sobre a outra, com pequeno vão; um dígito
        // DENTRO de um componente grande (moldura) não é parte dele
        if (nw > 0 && ov >= 0.6 * nw && gap < 0.35 * math.max(a.h, b.h) && gap >= -0.2 * math.min(a.h, b.h)) {
          a
            ..x0 = math.min(a.x0, b.x0)
            ..x1 = math.max(a.x1, b.x1)
            ..y0 = math.min(a.y0, b.y0)
            ..y1 = math.max(a.y1, b.y1)
            ..n = a.n + b.n
            ..esp = math.max(a.esp, b.esp)
            ..verm = a.verm + b.verm
            ..ids.addAll(b.ids);
          cs.removeAt(j);
          mudou = true;
          break;
        }
      }
    }
  }
}

bool _temBuraco(List<_Comp> c) {
  if (c.length < 3) return false;
  final d = [for (var i = 0; i + 1 < c.length; i++) (c[i + 1].x0 + c[i + 1].x1 - c[i].x0 - c[i].x1) / 2];
  final menor = d.reduce(math.min);
  return d.any((x) => x > 1.35 * menor);
}

/// Mesma altura (±15%) e passo regular: tira o que não é dígito da fileira.
bool _noPasso(List<_Comp> c) {
  final ult = c.last, ant = c[c.length - 2];
  final d = [for (var i = 0; i + 1 < c.length - 1; i++) (c[i + 1].x0 + c[i + 1].x1) / 2 - (c[i].x0 + c[i].x1) / 2];
  final pm = _mediana(List.of(d));
  final dist = (ult.x0 + ult.x1) / 2 - (ant.x0 + ant.x1) / 2;
  final hm = _mediana(c.sublist(0, c.length - 1).map((e) => e.h.toDouble()).toList());
  final cy = c.sublist(0, c.length - 1).map((e) => (e.y0 + e.y1) / 2).reduce((a, b) => a + b) / (c.length - 1);
  return dist > 0.7 * pm && dist < 1.4 * pm && ((ult.y0 + ult.y1) / 2 - cy).abs() < 0.3 * hm;
}

List<_Comp> _podar(List<_Comp> c0) {
  final c = List.of(c0);
  // 1) sujeira grudada entra pelas PONTAS da fileira: só elas saem por altura.
  // Dígito do meio com altura medida diferente (traço fino, rolete girando) fica:
  // quem garante que é dígito é o passo regular, conferido no fim.
  while (c.length >= 4) {
    final hm = _mediana(c.map((e) => e.h.toDouble()).toList());
    final dPrim = (c.first.h - hm).abs() / hm, dUlt = (c.last.h - hm).abs() / hm;
    if (dPrim > 0.3 && dPrim >= dUlt) {
      c.removeAt(0);
      continue;
    }
    if (dUlt > 0.3) {
      // último rolete girando: aceita bem menor se estiver no passo dos outros
      if (dUlt <= 0.45 && _noPasso(c)) break;
      c.removeLast();
      continue;
    }
    break;
  }
  // 2) dois componentes colados demais: um deles é pedaço, não dígito
  while (c.length >= 3) {
    final d = [for (var i = 0; i + 1 < c.length; i++) _cx(c[i + 1]) - _cx(c[i])];
    final pm = _mediana(List.of(d));
    var j = 0;
    for (var i = 1; i < d.length; i++) {
      if (d[i] < d[j]) j = i;
    }
    if (d[j] >= 0.6 * pm) break;
    final hm = _mediana(c.map((e) => e.h.toDouble()).toList());
    final a = c[j], b = c[j + 1];
    final da = (a.h - hm).abs() - a.n * 1e-6, db = (b.h - hm).abs() - b.n * 1e-6;
    c.removeAt(da > db ? j : j + 1);
  }
  return _maiorTrecho(c);
}

List<_Comp> _maiorTrecho(List<_Comp> c) {
  if (c.length < 3) return c;
  final d = [for (var i = 0; i + 1 < c.length; i++) (c[i + 1].x0 + c[i + 1].x1) / 2 - (c[i].x0 + c[i].x1) / 2];
  // roletes têm passo constante. Passos irregulares espalhados = sujeira, não fileira;
  // um único vão grande = dígito ausente (o trecho mais longo fica)
  final mediana = _mediana(List.of(d));
  // passo menor que ~0,75 da altura = peças de um mesmo dígito/arco, não dígitos vizinhos
  if (mediana < 0.75 * _mediana(c.map((e) => e.h.toDouble()).toList())) return const [];
  if (d.where((x) => (x - mediana).abs() > 0.25 * mediana && x < 1.35 * mediana).length >= 2) return const [];
  final menor = d.reduce(math.min);
  var melhor = <_Comp>[], atual = <_Comp>[c.first];
  for (var i = 0; i < d.length; i++) {
    if (d[i] > 1.35 * menor) {
      if (atual.length > melhor.length) melhor = atual;
      atual = [];
    }
    atual.add(c[i + 1]);
  }
  if (atual.length > melhor.length) melhor = atual;
  return melhor;
}

double _mediana(List<double> v) {
  v.sort();
  final m = v.length ~/ 2;
  return v.length.isOdd ? v[m] : (v[m - 1] + v[m]) / 2;
}

// -------------------------------------------------------------- recomposição

/// Dígitos lado a lado, em preto sobre branco, com altura ~56 px.
LinhaDigitos _compor(List<_Comp> membros, int largFaixa, double alturaMedia, bool claro, {int decimais = 0}) {
  const alvo = 56;
  final s = alvo / alturaMedia;
  final topo = membros.map((c) => c.y0).reduce(math.min);
  final base = membros.map((c) => c.y1).reduce(math.max);
  final altFonte = base - topo;
  final altOut = math.max(1, (altFonte * s).round());
  final larguras = [for (final c in membros) math.max(1, (c.w * s).round())];
  const gap = alvo * 3 ~/ 10, margem = alvo ~/ 2;
  var largura = larguras.reduce((a, b) => a + b) + gap * (larguras.length - 1) + 2 * margem;
  var altura = altOut + 2 * margem;
  largura += largura % 2;
  altura += altura % 2;
  final img = Uint8List(largura * altura)..fillRange(0, largura * altura, 255);
  var xo = margem;
  for (var m = 0; m < membros.length; m++) {
    final c = membros[m];
    final ids = c.ids.toSet();
    final lw = larguras[m];
    for (var oy = 0; oy < altOut; oy++) {
      final fy = (oy + 0.5) / s - 0.5;
      final y0 = fy.floor().clamp(0, altFonte - 1), y1 = (y0 + 1).clamp(0, altFonte - 1);
      final ty = (fy - fy.floor()).clamp(0.0, 1.0);
      for (var ox = 0; ox < lw; ox++) {
        final fx = (ox + 0.5) / s - 0.5;
        final x0 = fx.floor().clamp(0, c.w - 1), x1 = (x0 + 1).clamp(0, c.w - 1);
        final tx = (fx - fx.floor()).clamp(0.0, 1.0);
        double px(int xx, int yy) {
          final i = (topo + yy) * largFaixa + c.x0 + xx;
          return (c.mascara != null ? c.mascara![i] == 1 : ids.contains(c.rot[i])) ? 0 : 255;
        }
        final v = (px(x0, y0) * (1 - tx) + px(x1, y0) * tx) * (1 - ty) + (px(x0, y1) * (1 - tx) + px(x1, y1) * tx) * ty;
        img[(margem + oy) * largura + xo + ox] = v.round();
      }
    }
    xo += lw + gap;
  }
  return LinhaDigitos(img, largura, altura, [for (final c in membros) c.caixa], claro, alturaMedia.round(), decimais: decimais);
}

/// Recompõe a linha com o RECORTE EM CINZA de cada dígito (não a máscara): a
/// máscara do top-hat engorda e deforma o traço fino do gás e o OCR oscila
/// entre 2/3/5/8. Cada recorte tem o contraste esticado; dígito claro é
/// invertido para ficar preto no branco.
LinhaDigitos _comporCinza(List<_Comp> membros, Uint8List cinza, int w, int h, double alturaMedia, bool claro, {int decimais = 0}) {
  const alvo = 56;
  final s = alvo / alturaMedia;
  final pad = math.max(2, (alturaMedia * 0.08).round());
  final topo = (membros.map((c) => c.y0).reduce(math.min) - pad).clamp(0, h - 1);
  final base = (membros.map((c) => c.y1).reduce(math.max) + pad).clamp(1, h);
  final altFonte = base - topo;
  final altOut = math.max(1, (altFonte * s).round());
  final caixas = [for (final c in membros) ((c.x0 - pad).clamp(0, w - 1), (c.x1 + pad).clamp(1, w))];
  final larguras = [for (final b in caixas) math.max(1, ((b.$2 - b.$1) * s).round())];
  const gap = alvo * 3 ~/ 10, margem = alvo ~/ 2;
  var largura = larguras.reduce((a, b) => a + b) + gap * (larguras.length - 1) + 2 * margem;
  var altura = altOut + 2 * margem;
  largura += largura % 2;
  altura += altura % 2;
  final img = Uint8List(largura * altura)..fillRange(0, largura * altura, 255);
  var xo = margem;
  for (var m = 0; m < membros.length; m++) {
    final (xa, xb) = caixas[m];
    // contraste do recorte (percentis 5/95, robusto a reflexo)
    final hist = List<int>.filled(256, 0);
    final ya = math.max(topo, membros[m].y0 - pad), yb = math.min(base, membros[m].y1 + pad);
    for (var y = ya; y < yb; y++) {
      for (var x = xa; x < xb; x++) {
        hist[cinza[y * w + x]]++;
      }
    }
    final total = math.max(1, (yb - ya) * (xb - xa));
    var lo = 0, hi = 255, acc = 0;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= total * 0.05) { lo = v; break; }
    }
    acc = 0;
    for (var v = 255; v >= 0; v--) {
      acc += hist[v];
      if (acc >= total * 0.05) { hi = v; break; }
    }
    final esc = math.max(hi - lo, 1);
    final lw = larguras[m];
    for (var oy = 0; oy < altOut; oy++) {
      final sy = (topo + (oy + 0.5) / s).floor().clamp(topo, base - 1);
      for (var ox = 0; ox < lw; ox++) {
        final sx = (xa + (ox + 0.5) / s).floor().clamp(xa, xb - 1);
        // fora da altura do próprio dígito é borda de rolete/moldura: branco
        final c = membros[m];
        if (sy < c.y0 - pad || sy >= c.y1 + pad) {
          img[(margem + oy) * largura + xo + ox] = 255;
          continue;
        }
        var v = ((cinza[sy * w + sx] - lo) * 255 ~/ esc).clamp(0, 255);
        if (claro) v = 255 - v;
        img[(margem + oy) * largura + xo + ox] = v;
      }
    }
    xo += lw + gap;
  }
  return LinhaDigitos(img, largura, altura, [for (final c in membros) c.caixa], claro, alturaMedia.round(), decimais: decimais);
}

/// Cópia da linha com o traço preto engrossado em [raio] px.
LinhaDigitos _engrossar(LinhaDigitos l, int raio) => LinhaDigitos(
      _filtro2d(l.imagem, l.largura, l.altura, raio * 2 + 1, true),
      l.largura, l.altura, l.caixas, l.claro, l.alturaDigito, decimais: l.decimais,
    );

/// Dígitos vermelhos (casas decimais) logo à direita da fileira preta, na
/// mesma altura. Até 3. O último rolete pode estar girando (dígito cortado),
/// então a altura aceita vai de 50% a 130% da dos pretos.
/// Completa a fileira pelos PIXELS, não por componentes: um dígito colado na
/// moldura (ou fraco demais) não vira componente próprio e quebrava a fileira.
/// Procura no passo dos roletes, à esquerda, à direita e nos vãos internos, e
/// monta o dígito com os pixels ligados dentro da janela.
void _completarFileira(List<_Comp> c, Uint8List bin, int w, int h, Int32List rot) {
  _separarColados(c, bin, w, h, rot);
  for (var volta = 0; volta < 8; volta++) {
    final firmes = c.where((e) => e.mascara == null).toList();
    if (firmes.length < 3) return;
    final hm = _mediana(firmes.map((e) => e.h.toDouble()).toList());
    final wm = _mediana(firmes.map((e) => e.w.toDouble()).toList());
    final pm = _mediana([for (var i = 0; i + 1 < c.length; i++) _cx(c[i + 1]) - _cx(c[i])]);
    if (pm <= 0) return;
    final topo = c.map((e) => e.y0).reduce(math.min), base = c.map((e) => e.y1).reduce(math.max);

    // posição a tentar: vão interno primeiro, depois direita, depois esquerda
    double? alvo;
    var ondeInserir = c.length;
    for (var i = 0; i + 1 < c.length; i++) {
      if (_cx(c[i + 1]) - _cx(c[i]) > 1.6 * pm) {
        alvo = _cx(c[i]) + pm;
        ondeInserir = i + 1;
        break;
      }
    }
    alvo ??= _cx(c.last) + pm;
    var achou = _tentarJanela(c, bin, w, h, rot, alvo, pm, hm, wm, topo, base, ondeInserir);
    if (!achou && c.length < 12) {
      achou = _tentarJanela(c, bin, w, h, rot, _cx(c.first) - pm, pm, hm, wm, topo, base, 0);
    }
    if (!achou) return;
  }
}

/// Conferências da fileira; devolve a pontuação ou null se não serve.
double? _pontos(List<_Comp> c, int w, int h, int k) {
  final hm = _mediana(c.map((e) => e.h.toDouble()).toList());
  // roletes têm passo constante: um vão de dois passos é dígito que sumiu
  if (_temBuraco(c)) return null;
  // dígitos da mesma fonte têm proporção de dígito (arcos e molduras não)
  final wm = _mediana(c.map((e) => e.w.toDouble()).toList());
  if (wm / hm < 0.25 || wm / hm > 0.85) return null;
  if (c.where((e) => e.w > 1.5 * wm).length > c.length ~/ 3) return null;
  // k fora da faixa do traço: pequeno demais vira contorno oco, grande demais deixa divisória
  if (k < 0.13 * hm || k > 0.4 * hm) return null;
  // a fileira de dígitos é a de letras maiores; quantidade pesa menos; e o
  // usuário a encaixa no meio da moldura (texto da marca fica nas bordas)
  final cy = c.map((e) => (e.y0 + e.y1) / 2).reduce((a, b) => a + b) / c.length;
  final centro = 1 - 0.6 * ((cy - h / 2).abs() / (h / 2)).clamp(0.0, 1.0);
  return hm * math.sqrt(math.min(c.length, 12)) * centro;
}

double _cx(_Comp c) => (c.x0 + c.x1) / 2;

/// Dois dígitos vizinhos podem sair como um componente só (pouca luz, traço
/// ligado). Um componente bem mais largo que os outros é cortado em partes
/// iguais, nas colunas de menos tinta perto das divisas.
void _separarColados(List<_Comp> c, Uint8List bin, int w, int h, Int32List rot) {
  if (c.length < 3) return;
  final larguras = c.map((e) => e.w.toDouble()).toList();
  final wm = _mediana(List.of(larguras));
  final hm = _mediana(c.map((e) => e.h.toDouble()).toList());
  for (var i = c.length - 1; i >= 0; i--) {
    final m = c[i];
    final partes = (m.w / wm).round();
    if (m.w <= 1.45 * wm || partes < 2 || partes > 4) continue;
    final largura = m.w / partes;
    final cortes = <int>[];
    for (var p = 1; p < partes; p++) {
      final alvo = m.x0 + largura * p;
      final a = (alvo - 0.3 * largura).round().clamp(m.x0 + 1, m.x1 - 1);
      final b = (alvo + 0.3 * largura).round().clamp(m.x0 + 1, m.x1 - 1);
      var melhorX = a, melhorTinta = 1 << 30;
      for (var x = a; x <= b; x++) {
        var tinta = 0;
        for (var y = m.y0; y < m.y1; y++) {
          tinta += bin[y * w + x];
        }
        if (tinta < melhorTinta) {
          melhorTinta = tinta;
          melhorX = x;
        }
      }
      cortes.add(melhorX);
    }
    final limites = [m.x0, ...cortes, m.x1];
    final novos = <_Comp>[];
    for (var p = 0; p < partes; p++) {
      final mascara = Uint8List(w * h);
      var x0 = w, x1 = 0, y0 = h, y1 = 0, n = 0;
      for (var y = m.y0; y < m.y1; y++) {
        for (var x = limites[p]; x < limites[p + 1]; x++) {
          if (bin[y * w + x] == 0) continue;
          mascara[y * w + x] = 1;
          n++;
          if (x < x0) x0 = x;
          if (x >= x1) x1 = x + 1;
          if (y < y0) y0 = y;
          if (y >= y1) y1 = y + 1;
        }
      }
      if (n == 0 || y1 - y0 < 0.6 * hm) return; // corte ruim: desiste deste componente
      novos.add(_Comp(x0, y0, x1, y1, n, 3, 0, const [], rot, mascara: mascara));
    }
    c.replaceRange(i, i + 1, novos);
  }
}

/// Monta um dígito com os pixels ligados numa janela centrada em [alvo].
bool _tentarJanela(List<_Comp> c, Uint8List bin, int w, int h, Int32List rot, double alvo,
    double pm, double hm, double wm, int topo, int base, int ondeInserir) {
  if (alvo < 0 || alvo >= w) return false;
  final xa = (alvo - 0.5 * pm).round().clamp(0, w - 1), xb0 = (alvo + 0.5 * pm).round().clamp(0, w);
  final ya = (topo - 0.12 * hm).round().clamp(0, h - 1), yb = (base + 0.12 * hm).round().clamp(0, h);
  if (xb0 - xa < 3 || yb - ya < 3) return false;

  final mascara = Uint8List(w * h);
  var x0 = w, x1 = 0, y0 = h, y1 = 0, n = 0, xb = xb0;
  for (var passada = 0; passada < 2; passada++) {
    mascara.fillRange(0, w * h, 0);
    x0 = w; x1 = 0; y0 = h; y1 = 0; n = 0;
    for (var y = ya; y < yb; y++) {
      for (var x = xa; x < xb; x++) {
        if (bin[y * w + x] == 0) continue;
        mascara[y * w + x] = 1;
        n++;
        if (x < x0) x0 = x;
        if (x >= x1) x1 = x + 1;
        if (y < y0) y0 = y;
        if (y >= y1) y1 = y + 1;
      }
    }
    if (n == 0) return false;
    // 2ª passada: largura de um dígito a partir de onde a tinta começa
    if (passada == 0) xb = math.min(xb0, x0 + (1.3 * wm).round());
  }
  final cw = x1 - x0, ch = y1 - y0;
  if (ch < 0.6 * hm || ch > 1.3 * hm) return false;
  if (cw > 1.3 * wm || cw < 0.12 * hm) return false;
  if (n < 0.1 * cw * ch) return false;
  // tem de ficar no passo e alinhado com a fileira (base ou topo)
  if (((x0 + x1) / 2 - alvo).abs() > 0.3 * pm) return false;
  if ((y1 - base).abs() > 0.25 * hm && (y0 - topo).abs() > 0.25 * hm) return false;
  c.insert(ondeInserir, _Comp(x0, y0, x1, y1, n, 3, 0, const [], rot, mascara: mascara));
  return true;
}

List<_Comp> _decimais(List<_Comp> pretos, double hm, Uint8List vermBin, int w, int h) {
  final comps = _rotular(vermBin, null, w, h);
  final passo = pretos.length >= 2
      ? _mediana([for (var i = 0; i + 1 < pretos.length; i++) (pretos[i + 1].x0 + pretos[i + 1].x1 - pretos[i].x0 - pretos[i].x1) / 2])
      : hm * 0.8;
  final out = <_Comp>[];
  var cur = pretos.last;
  while (out.length < 4) {
    // o vizinho vermelho mais próximo à direita, no passo dos roletes
    _Comp? prox;
    for (final c in comps) {
      if (out.contains(c) || c.h < 0.4 * hm || c.w > 1.2 * hm) continue;
      final dist = (c.x0 + c.x1 - cur.x0 - cur.x1) / 2;
      if (dist < 0.6 * passo || dist > 1.6 * passo) continue;
      if (math.min(c.y1, cur.y1) - math.max(c.y0, cur.y0) < 0.3 * c.h) continue;
      if (prox == null || c.x0 < prox.x0) prox = c;
    }
    if (prox == null) break;
    // rolete girando pode estar cortado/deslocado: entra assim mesmo — a leitura é
    // um número só e sem ele perderia uma casa (o OCR dá o dígito vizinho)
    final desvio = ((prox.y0 + prox.y1) - (cur.y0 + cur.y1)).abs() / 2;
    if (prox.h < 0.5 * hm || prox.h > 1.3 * hm || desvio > 0.6 * hm) break;
    out.add(prox);
    cur = prox;
  }
  return out;
}
