// Gera web_app/sementes.js: modelos dos dígitos tirados dos prints reais do
// medidor de água (test/fixtures), para o webapp já começar sabendo 0 2 3 5 6 7 8 9.
// Rodar só quando mudar o pipeline: node web_app/gerar_sementes.mjs
import { createRequire } from 'module';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const req = createRequire(process.env.HOME + '/.claude/tools/qa/');
const J = req('jimp');
globalThis.self = globalThis;
await import(path.join(raiz, 'web_app/dist/prumo_ocr.js'));
await import(path.join(raiz, 'web_app/logica.js'));
const P = globalThis.Prumo;
let modelos = [];
for (const [arq, valor] of [['medidor_agua_escuro.png', '076360'], ['medidor_agua_claro.png', '076360'], ['medidor_agua_701.png', '26895']]) {
  const im = await J.read(path.join(raiz, 'test/fixtures', arq));
  const { width: W, height: H } = im.bitmap;
  const f = P.faixasDaFoto(W, H, null)[0];
  const b = im.clone().crop(f[0], f[1], f[2], f[3]).resize(864, J.AUTO);
  const { width: bw, height: bh, data } = b.bitmap;
  const l = prumoLinhas(new Uint8Array(data.buffer, data.byteOffset, data.length), bw, bh, 0, 0, bw, bh).find((x) => x.variante === 'e-mascara');
  if (!l) throw new Error('sem linha em ' + arq);
  // 701: o último rolete está girando; só os 5 primeiros dígitos têm rótulo certo
  const sg = P.colunasDeTinta(l.img, l.w, l.h);
  const corte = { img: l.img, w: valor.length < l.n ? sg[valor.length - 1][1] + 2 : l.w, h: l.h, n: valor.length };
  const img = new Uint8Array(corte.w * l.h);
  for (let y = 0; y < l.h; y++) for (let x = 0; x < corte.w; x++) img[y * corte.w + x] = l.img[y * l.w + x];
  modelos = P.aprender(modelos, { ...corte, img }, valor);
}
const limpos = modelos.map(({ d, g }) => ({ d, g }));
fs.writeFileSync(path.join(raiz, 'web_app/sementes.js'), '// Gerado por web_app/gerar_sementes.mjs — não editar.\nglobalThis.PRUMO_SEMENTES = ' + JSON.stringify(limpos) + ';\n');
console.log('SEMENTES', limpos.length, [...new Set(limpos.map((m) => m.d))].sort().join(''));
