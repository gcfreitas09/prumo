// Gate W2: o OCR do webapp (pipeline do app compilado para JS + Tesseract local)
// lê os prints reais do medidor. Usa as ferramentas de QA compartilhadas
// (~/.claude/tools/qa: jimp, pngjs, tesseract.js) — nada disso vai para o site.
import { createRequire } from 'module';
import path from 'path';
import { fileURLToPath } from 'url';
const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const req = createRequire(process.env.HOME + '/.claude/tools/qa/');
const J = req('jimp'), { PNG } = req('pngjs'), T = req('tesseract.js');
globalThis.self = globalThis;
await import(path.join(raiz, 'web_app/dist/prumo_ocr.js'));
await import(path.join(raiz, 'web_app/logica.js'));
const P = globalThis.Prumo;

const w = await T.createWorker('eng', 1, { langPath: path.join(raiz, 'web_app/dist'), gzip: false, cacheMethod: 'none' });
await w.setParameters({ tessedit_char_whitelist: '0123456789' });
let psmAtual = null;
const MAXW = 864;
var depDe = function (im) {
  return {
    // recorta a faixa da foto, reduz a ≤ 864 px de largura (como o Capturar do app) e isola
    acharLinhas: async (f) => {
      const b = im.clone().crop(f[0], f[1], f[2], f[3]);
      const esc = f[2] > MAXW ? MAXW / f[2] : 1;
      if (esc < 1) b.resize(MAXW, J.AUTO);
      const { width: bw, height: bh, data } = b.bitmap;
      const ls = prumoLinhas(new Uint8Array(data.buffer, data.byteOffset, data.length), bw, bh, 0, 0, bw, bh);
      return ls.map((l) => ({ ...l, img: l.img, box: Array.from(l.box).map((v, i) => Math.round(v / esc) + (i % 2 ? f[1] : f[0])) }));
    },
    ocr: async (l, x0, x1, psm) => {
      if (psm !== psmAtual) { await w.setParameters({ tessedit_pageseg_mode: psm }); psmAtual = psm; }
      const m = 16, ww = x1 - x0, o = new PNG({ width: ww + 2 * m, height: l.h + 2 * m });
      o.data.fill(255);
      for (let y = 0; y < l.h; y++) for (let x = 0; x < ww; x++) {
        const v = l.img[y * l.w + x0 + x], d = ((y + m) * o.width + x + m) * 4;
        o.data[d] = o.data[d + 1] = o.data[d + 2] = v;
      }
      return (await w.recognize(PNG.sync.write(o))).data.text;
    },
  };
}
async function ler(arq, opc) {
  const im = await J.read(path.join(raiz, 'test/fixtures', arq));
  const { width: W, height: H } = im.bitmap;
  const t0 = Date.now();
  const r = await P.lerImagem(W, H, depDe(im), opc);
  console.log(arq.padEnd(26), JSON.stringify({ ...opc, modelos: opc.modelos ? opc.modelos.length : undefined }), '→', r ? r.valor : 'nada', `${Date.now() - t0} ms`);
  ultima = r;
  return r ? r.valor : null;
}
let ultima = null;
let ok = true;
const exige = (v, esperado) => { if (v !== esperado) { ok = false; console.log('   ✗ esperado', esperado); } };
const comeca = (v, p) => { if (!v || !v.startsWith(p)) { ok = false; console.log('   ✗ esperado começar com', p); } };
// prints da câmera do app: dígitos no centro da moldura (47% da altura)
// prints da câmera do app, sem toque (varre do meio para fora)
exige(await ler('medidor_agua_escuro.png', {}), '076360');
exige(await ler('medidor_agua_claro.png', {}), '076360');
comeca(await ler('medidor_gas_camera.png', {}), '01461');
// toque em cima dos números
exige(await ler('medidor_agua_escuro.png', { toque: [0.5, 0.47] }), '076360');
// foto de longe do gás (1125 px, dígitos com ~35 px): só informativo — o
// Tesseract não lê dígito tão pequeno; com foto de perto ou com modelos aprendidos, lê
await ler('medidor_gas_lao.jpg', { toque: [0.47, 0.325] });
await ler('medidor_agua_701.png', {});
// aprende com a leitura confirmada de um print e lê o outro só pelos modelos (sem OCR)
await ler('medidor_agua_escuro.png', {});
const modelos = P.aprender([], ultima.linha, '076360');
let chamadas = 0;
const _ocr = depDe; depDe = (im) => { const d = _ocr(im); const o = d.ocr; d.ocr = async (...a) => { chamadas++; return o(...a); }; return d; };
exige(await ler('medidor_agua_claro.png', { modelos }), '076360');
console.log('   modelos:', modelos.length, 'chamadas ao OCR:', chamadas);
if (chamadas > 0) { ok = false; console.log('   ✗ devia ler só pelos modelos'); }
await w.terminate();
console.log(ok ? 'OCR WEB OK' : 'OCR WEB FALHOU');
process.exit(ok ? 0 : 1);
