// Worker do isolamento de dígitos: roda o pipeline do app (prumo_ocr.js, gerado
// por dart2js a partir de lib/digitos.dart) fora da thread da tela.
self.self = self;
importScripts('prumo_ocr.js');

self.onmessage = (e) => {
  const { id, rgba, w, h, faixa } = e.data;
  try {
    const linhas = prumoLinhas(new Uint8Array(rgba), w, h, faixa[0], faixa[1], faixa[2], faixa[3]);
    const out = [];
    const transf = [];
    for (let i = 0; i < linhas.length; i++) {
      const l = linhas[i];
      const img = new Uint8Array(l.img); // cópia própria, transferível
      out.push({ img, w: l.w, h: l.h, n: l.n, variante: l.variante, decimais: l.decimais, box: Array.from(l.box) });
      transf.push(img.buffer);
    }
    self.postMessage({ id, linhas: out }, transf);
  } catch (err) {
    self.postMessage({ id, erro: String(err && err.message || err) });
  }
};
