// Prumo web — lógica pura (sem DOM). Espelha lib/formato.dart, lib/analise.dart
// e lib/relatorio.dart. Testada por web_app/teste_logica.mjs; montar.sh a põe
// inline na página.
(function (g) {
  'use strict';
  const ESPACO_FINO = ' ';
  const MESES = ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'];
  const ASSINATURA = 'Alex Freitas';
  const TIPOS = ['agua', 'gas'];

  /** 1316967 → "1 316 967" (espaço fino). */
  function fmtNum(v) {
    if (v === null || v === undefined || v === '') return '—';
    const s = String(v);
    const virg = s.indexOf(',');
    if (virg >= 0) return fmtNum(s.slice(0, virg)) + ',' + s.slice(virg + 1);
    const neg = s.startsWith('-');
    const d = neg ? s.slice(1) : s;
    if (!/^\d+$/.test(d)) return s;
    let b = '';
    for (let i = 0; i < d.length; i++) {
      if (i > 0 && (d.length - i) % 3 === 0) b += ESPACO_FINO;
      b += d[i];
    }
    return (neg ? '-' : '') + b;
  }
  const fmtConsumo = (c) => (c < 0 ? '−' : '+') + ESPACO_FINO + fmtNum(Math.abs(c)) + ESPACO_FINO + 'm³';
  const parteInteira = (v) => (v === null || v === undefined || v === '' ? null : (Number.isFinite(parseInt(String(v).split(',')[0], 10)) ? parseInt(String(v).split(',')[0], 10) : null));
  const nomeMes = (m) => MESES[m - 1];
  const tituloMes = (a, m) => `${nomeMes(m)} de ${a}`;
  const assuntoMes = (a, m) => `${nomeMes(m)}/${a}`;
  const chaveMes = (a, m) => `${a}-${String(m).padStart(2, '0')}`;
  const deChaveMes = (k) => { const [a, m] = k.split('-').map(Number); return { ano: a, mes: m }; };

  /** anteriores: leituras de meses anteriores, mais recente primeiro (até 4). */
  function analisar(valor, anteriores) {
    if (valor === null || valor === undefined || !anteriores.length) return { consumo: null, media: null, situacao: 'primeira' };
    const consumo = valor - anteriores[0];
    const difs = [];
    for (let i = 0; i + 1 < anteriores.length && difs.length < 3; i++) difs.push(anteriores[i] - anteriores[i + 1]);
    const media = difs.length ? Math.round(difs.reduce((a, b) => a + b, 0) / difs.length) : null;
    if (consumo < 0) return { consumo, media, situacao: 'negativo' };
    if (media !== null && media > 0 && consumo > 2 * media) return { consumo, media, situacao: 'acima' };
    return { consumo, media, situacao: 'naMedia' };
  }
  const TEXTO_SITUACAO = {
    primeira: 'Sem mês anterior para comparar',
    naMedia: 'Na média',
    acima: 'Mais que o dobro da média',
    negativo: 'Menor que o mês anterior',
  };
  const pedeConfirmacao = (a) => a.situacao === 'negativo' || a.situacao === 'acima';

  /** Leitura plausível: não menor que a anterior e sem salto absurdo. */
  function plausivel(v, anteriores) {
    if (!anteriores.length) return true;
    if (v < anteriores[0]) return false;
    const a = analisar(v, anteriores);
    const semMedia = Math.max(300, Math.floor(anteriores[0] / 5));
    const limite = (a.media || 0) > 0 ? Math.max(300, a.media * 8) : semMedia;
    return v - anteriores[0] <= limite;
  }

  // ---------- estado (um objeto JSON; a página guarda no navegador)
  function estadoVazio() {
    return { versao: 1, predio: null, aptos: [], meses: {}, leituras: {} };
  }
  const chaveLeitura = (mesK, aptoId, tipo) => `${mesK}|${aptoId}|${tipo}`;

  /** Gerador de andares: 201, 202… (andar × 100 + posição). */
  function gerarAptos(andarIni, andarFim, porAndar) {
    const out = [];
    let id = 1, ordem = 0;
    for (let a = andarIni; a <= andarFim; a++) {
      for (let p = 1; p <= porAndar; p++) {
        out.push({ id: id++, numero: String(a * 100 + p), andar: a, ordemApto: ordem, ordemLeitura: ordem, ativo: true });
        ordem++;
      }
    }
    return out;
  }
  const aptosAtivos = (e) => e.aptos.filter((a) => a.ativo).sort((x, y) => x.ordemApto - y.ordemApto);
  const naOrdemDeLeitura = (e) => aptosAtivos(e).sort((x, y) => x.ordemLeitura - y.ordemLeitura);

  /** Mês corrente pelo relógio; cria se não existir. */
  function mesAtual(e, agora = new Date()) {
    const k = chaveMes(agora.getFullYear(), agora.getMonth() + 1);
    if (!e.meses[k]) e.meses[k] = { criadoEm: agora.toISOString(), enviadoEm: null };
    return k;
  }
  const leiturasDoMes = (e, mesK) => {
    const out = {};
    for (const [k, l] of Object.entries(e.leituras)) {
      if (k.startsWith(mesK + '|')) {
        const [, aptoId, tipo] = k.split('|');
        out[`${aptoId}|${tipo}`] = l;
      }
    }
    return out;
  };
  /** Leituras de meses anteriores ao [mesK], mais recente primeiro, inteiras. */
  function anteriores(e, aptoId, tipo, mesK, limite = 4) {
    const meses = Object.keys(e.meses).filter((k) => k < mesK).sort().reverse();
    const out = [];
    for (const k of meses) {
      const l = e.leituras[chaveLeitura(k, aptoId, tipo)];
      const n = l ? parteInteira(l.valor) : null;
      if (n !== null) out.push(n);
      if (out.length >= limite) break;
    }
    return out;
  }
  function historicoAnterior(e, mesK) {
    const out = {};
    for (const a of e.aptos) for (const t of TIPOS) out[`${a.id}|${t}`] = anteriores(e, a.id, t, mesK);
    return out;
  }

  // ---------- relatório
  function montarLinhas(aptos, lei, ant) {
    return [...aptos].sort((a, b) => a.ordemApto - b.ordemApto).map((a) => {
      const v = (t) => (lei[`${a.id}|${t}`] ? lei[`${a.id}|${t}`].valor : null);
      const cons = (t) => {
        const x = parteInteira(v(t)), p = ant[`${a.id}|${t}`];
        return x !== null && p && p.length ? x - p[0] : null;
      };
      return { numero: a.numero, agua: v('agua'), aguaCons: cons('agua'), gas: v('gas'), gasCons: cons('gas') };
    });
  }
  const pendencias = (aptos, lei) => {
    const out = [];
    for (const a of aptos) for (const t of TIPOS) if (!lei[`${a.id}|${t}`]) out.push({ apto: a, tipo: t });
    return out;
  };
  const textoPendencia = (p) => `Apto ${p.apto.numero} · ${p.tipo === 'agua' ? 'Água' : 'Gás'}`;
  const assunto = (predio, ano, mes) => `Leituras de água e gás – ${assuntoMes(ano, mes)} – ${predio.nome}`;
  const corpoEmail = () => `Segue em anexo a leitura.\n\nAtenciosamente,\n${ASSINATURA}\n`;
  const nomeArquivoPdf = (ano, mes) => `leituras-${ano}-${String(mes).padStart(2, '0')}.pdf`;
  const dataBR = (d) => `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}/${d.getFullYear()}`;
  // fontes padrão do PDF (só Latin-1): sem espaço fino, "−" nem "—"
  const numPdf = (v) => (v === null || v === undefined ? '-' : fmtNum(v).split(ESPACO_FINO).join(' '));

  /** PDF A4 igual ao do app (lib/relatorio.dart), SEM consumo. [jsPDF] = window.jspdf.jsPDF. */
  function gerarPdf(jsPDF, predio, ano, mes, linhas, agora = new Date()) {
    const doc = new jsPDF({ unit: 'pt', format: 'a4' });
    doc.setProperties({ title: assunto(predio, ano, mes), author: predio.nome, creator: 'Prumo' });
    const W = 595.28, H = 841.89, mx = 56, top = 52, bottom = 48;
    const tinta = [17, 17, 17], cinza = [110, 110, 115], fio = [217, 217, 213], listra = [246, 246, 244];
    const acao = [31, 70, 71], agua = [43, 123, 214], gas = [221, 107, 43];
    const total = linhas.length * 2;
    const lidos = linhas.reduce((s, l) => s + (l.agua !== null ? 1 : 0) + (l.gas !== null ? 1 : 0), 0);
    const faltam = total - lidos;
    const larg = W - 2 * mx;
    const cols = [larg * 1 / 3.8, larg * 1.4 / 3.8, larg * 1.4 / 3.8];
    const x0 = mx, x1 = mx + cols[0], x2 = x1 + cols[1], x3 = x2 + cols[2];
    const alturaLinha = 25;
    const cor = (c) => doc.setTextColor(c[0], c[1], c[2]);
    let y;

    function cabecalho(primeira) {
      y = top;
      if (primeira) {
        doc.setFont('helvetica', 'bold'); doc.setFontSize(9); cor(acao);
        doc.setCharSpace(1.2); doc.text('LEITURA DE ÁGUA E GÁS', mx, y + 7); doc.setCharSpace(0);
        y += 7 + 6;
        doc.setFontSize(24); cor(tinta); doc.text(predio.nome, mx, y + 20); y += 24 + 4;
        doc.setFont('helvetica', 'normal'); doc.setFontSize(14); doc.text(tituloMes(ano, mes), mx, y + 12); y += 14 + 14;
        doc.setFillColor(acao[0], acao[1], acao[2]); doc.rect(mx, y, larg, 1.2, 'F'); y += 1.2 + 8;
        doc.setFontSize(9); cor(cinza);
        doc.text(`${linhas.length} apartamentos  ·  ${lidos} de ${total} medidores lidos`, mx, y + 7);
        doc.text(`Emitido em ${dataBR(agora)}`, W - mx, y + 7, { align: 'right' });
        y += 9 + 18;
      } else {
        doc.setFont('helvetica', 'normal'); doc.setFontSize(9); cor(cinza);
        doc.text(`${predio.nome}  ·  ${tituloMes(ano, mes)}`, mx, y + 7); y += 9 + 12;
      }
      // cabeçalho da tabela
      doc.setFont('helvetica', 'bold'); doc.setFontSize(9); cor(cinza);
      doc.text('APTO', x0 + 8, y + 15);
      const titulo = (t, c, xd) => {
        const tw = doc.getTextWidth(t);
        doc.text(t, xd - 8, y + 15, { align: 'right' });
        doc.setFillColor(c[0], c[1], c[2]); doc.circle(xd - 8 - tw - 5 - 3, y + 12, 3, 'F');
      };
      titulo('ÁGUA', agua, x2); titulo('GÁS', gas, x3);
      y += 22;
      doc.setDrawColor(tinta[0], tinta[1], tinta[2]); doc.setLineWidth(0.8); doc.line(x0, y, x3, y);
    }

    cabecalho(true);
    linhas.forEach((l, i) => {
      if (y + alturaLinha > H - bottom - 24) { doc.addPage(); cabecalho(false); }
      if (i % 2 === 1) { doc.setFillColor(listra[0], listra[1], listra[2]); doc.rect(x0, y, larg, alturaLinha, 'F'); }
      doc.setFontSize(11);
      doc.setFont('helvetica', 'bold'); cor(tinta); doc.text(l.numero, x0 + 8, y + 16.5);
      doc.setFont('helvetica', 'normal');
      cor(l.agua === null ? cinza : tinta); doc.text(numPdf(l.agua), x2 - 8, y + 16.5, { align: 'right' });
      cor(l.gas === null ? cinza : tinta); doc.text(numPdf(l.gas), x3 - 8, y + 16.5, { align: 'right' });
      y += alturaLinha;
      doc.setDrawColor(fio[0], fio[1], fio[2]); doc.setLineWidth(0.4); doc.line(x0, y, x3, y);
    });
    if (faltam > 0) {
      if (y + 24 > H - bottom - 24) { doc.addPage(); cabecalho(false); }
      doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5); cor(cinza);
      doc.text(`"-" = medidor sem leitura neste mês (${faltam}).`, x0, y + 18);
    }
    const n = doc.getNumberOfPages();
    for (let p = 1; p <= n; p++) {
      doc.setPage(p);
      doc.setDrawColor(fio[0], fio[1], fio[2]); doc.setLineWidth(0.4); doc.line(mx, H - bottom - 14, W - mx, H - bottom - 14);
      doc.setFont('helvetica', 'normal'); doc.setFontSize(8); cor(cinza);
      doc.text(`Responsável: ${ASSINATURA}`, mx, H - bottom);
      doc.text(`Página ${p} de ${n}`, W - mx, H - bottom, { align: 'right' });
    }
    return doc;
  }

  /** Resumo por mês (histórico): consumo total de água e gás vs. mês anterior. */
  function resumos(e) {
    const meses = Object.keys(e.meses).sort().reverse();
    const ativos = aptosAtivos(e).length * 2;
    return meses.map((k, i) => {
      const atual = leiturasDoMes(e, k), prev = i + 1 < meses.length ? leiturasDoMes(e, meses[i + 1]) : {};
      let agua = 0, gas = 0;
      for (const [kk, l] of Object.entries(atual)) {
        const a = prev[kk] ? parteInteira(prev[kk].valor) : null, b = parteInteira(l.valor);
        if (a !== null && b !== null && b >= a) { if (kk.endsWith('|agua')) agua += b - a; else gas += b - a; }
      }
      const { ano, mes } = deChaveMes(k);
      return { chave: k, ano, mes, lidos: Object.keys(atual).length, total: ativos, agua, gas, enviadoEm: e.meses[k].enviadoEm, temAnterior: i + 1 < meses.length };
    });
  }

  const TROCA = { O: '0', o: '0', D: '0', Q: '0', U: '0', u: '0', I: '1', l: '1', i: '1', '|': '1', '!': '1', L: '1', j: '1', J: '1', T: '7', Z: '2', z: '2', S: '5', s: '5', G: '6', b: '6', B: '8', g: '9', q: '9', A: '4' };
  /** Texto do OCR → dígitos, só se forem exatamente [n] (igual a digitosDaLinha em lib/ocr.dart). */
  function digitosDaLinha(texto, n) {
    let b = '';
    for (const c of texto) {
      if (/\d/.test(c)) b += c;
      else if (TROCA[c]) b += TROCA[c];
      else if (/[\s.,:;'`´\-_~]/.test(c)) continue;
      else return null;
    }
    return b.length === n ? b : null;
  }

  /** Faixas (retângulos [x, y, w, h] na foto W×H) onde procurar os dígitos,
   *  com o formato da moldura do app (≈ 2:1). Sem toque: faixas da largura toda,
   *  do meio para fora. Com toque [tx, ty] (0..1): faixas de vários tamanhos
   *  centradas nele (medidor pequeno na foto). */
  function faixasDaFoto(W, H, toque) {
    const out = [];
    const add = (cx, cy, w) => {
      w = Math.min(Math.round(w), W);
      const h = Math.min(Math.round(w / 2.05), H);
      const x = Math.max(0, Math.min(W - w, Math.round(cx - w / 2)));
      const y = Math.max(0, Math.min(H - h, Math.round(cy - h / 2)));
      if (!out.some((o) => Math.abs(o[0] - x) < 0.03 * W && Math.abs(o[1] - y) < 0.03 * H && o[2] === w)) out.push([x, y, w, h]);
    };
    if (toque) {
      for (const f of [0.6, 0.4, 0.9, 0.28]) add(toque[0] * W, toque[1] * H, f * W);
    } else {
      for (const cy of [0.5, 0.42, 0.58, 0.34, 0.66, 0.26, 0.74]) add(W / 2, cy * H, 0.92 * W);
      for (const cy of [0.5, 0.38, 0.62]) add(W / 2, cy * H, 0.6 * W);
    }
    return out;
  }

  /** Colunas com tinta (pixel < 128) na linha recomposta: um trecho por dígito. */
  function colunasDeTinta(img, w, h) {
    const seg = [];
    let ini = -1;
    for (let x = 0; x <= w; x++) {
      let tinta = false;
      if (x < w) for (let y = 0; y < h; y++) if (img[y * w + x] < 128) { tinta = true; break; }
      if (tinta) { if (ini < 0) ini = x; } else if (ini >= 0) { seg.push([ini, x]); ini = -1; }
    }
    return seg;
  }

  /** Vários palpites ("01?6185") → dígito por posição. Cada posição precisa de
   *  ≥ 2 votos iguais e maioria; senão null (melhor não ler do que ler errado). */
  function consensoPosicional(palpites, n) {
    let s = '';
    for (let i = 0; i < n; i++) {
      const c = {};
      let tot = 0;
      for (const p of palpites) if (p[i] && p[i] !== '?') { c[p[i]] = (c[p[i]] || 0) + 1; tot++; }
      let melhor = null;
      for (const [d, k] of Object.entries(c)) if (!melhor || k > melhor[1]) melhor = [d, k];
      if (!melhor || melhor[1] < 2 || melhor[1] * 2 <= tot) return null;
      s += melhor[0];
    }
    return s;
  }

  // ---------- dígitos aprendidos (modelos por comparação de forma)
  // Cada dígito confirmado vira um modelo 16×24 (tinta, média 0, norma 1).
  // Um dígito novo é comparado com todos; com semelhança alta e folga sobre o
  // 2º colocado, vale como 2 votos. Assim o app aprende os medidores do prédio
  // a cada leitura confirmada (e a cada correção feita no teclado).
  const GW = 16, GH = 24;
  function glifo(img, w, h, a, b) {
    let y0 = h, y1 = -1;
    for (let y = 0; y < h; y++) for (let x = a; x < b; x++) if (img[y * w + x] < 128) { if (y < y0) y0 = y; if (y > y1) y1 = y; }
    if (y1 < 0) return null;
    const v = new Float32Array(GW * GH), bw = b - a, bh = y1 - y0 + 1;
    for (let gy = 0; gy < GH; gy++) {
      const ys = y0 + (gy * bh) / GH, ye = y0 + ((gy + 1) * bh) / GH;
      for (let gx = 0; gx < GW; gx++) {
        const xs = a + (gx * bw) / GW, xe = a + ((gx + 1) * bw) / GW;
        let s = 0, n = 0;
        for (let y = Math.floor(ys); y < Math.max(Math.floor(ys) + 1, Math.ceil(ye)); y++) {
          for (let x = Math.floor(xs); x < Math.max(Math.floor(xs) + 1, Math.ceil(xe)); x++) { s += 255 - img[y * w + x]; n++; }
        }
        v[gy * GW + gx] = s / n / 255;
      }
    }
    let m = 0;
    for (const x of v) m += x;
    m /= v.length;
    let q = 0;
    for (let i = 0; i < v.length; i++) { v[i] -= m; q += v[i] * v[i]; }
    q = Math.sqrt(q) || 1;
    const out = new Int8Array(v.length);
    for (let i = 0; i < v.length; i++) out[i] = Math.max(-127, Math.min(127, Math.round((v[i] / q) * 127 * 4)));
    return out;
  }
  const semelhanca = (x, y) => { let s = 0, qx = 0, qy = 0; for (let i = 0; i < x.length; i++) { s += x[i] * y[i]; qx += x[i] * x[i]; qy += y[i] * y[i]; } return s / (Math.sqrt(qx * qy) || 1); };
  const paraTexto = (g) => { let b = ''; for (const x of g) b += String.fromCharCode(x + 128); return typeof btoa === 'function' ? btoa(b) : Buffer.from(b, 'latin1').toString('base64'); };
  const deTexto = (t) => { const b = typeof atob === 'function' ? atob(t) : Buffer.from(t, 'base64').toString('latin1'); const g = new Int8Array(b.length); for (let i = 0; i < b.length; i++) g[i] = b.charCodeAt(i) - 128; return g; };

  /** modelos: [{d: "7", g: "base64"}]. Devolve o dígito, ou null se não tiver certeza. */
  function classificarGlifo(g, modelos) {
    const melhorPor = {};
    for (const m of modelos) {
      m._g = m._g || deTexto(m.g);
      const s = semelhanca(g, m._g);
      if (!(m.d in melhorPor) || s > melhorPor[m.d]) melhorPor[m.d] = s;
    }
    const r = Object.entries(melhorPor).sort((x, y) => y[1] - x[1]);
    if (!r.length) return null;
    const folga = r.length > 1 ? r[0][1] - r[1][1] : 1;
    return r[0][1] >= 0.82 && folga >= 0.15 ? r[0][0] : null;
  }
  /** Palpite da linha pelos modelos ("07?3"), ou null se a tinta não separa n dígitos. */
  function palpiteModelos(l, modelos) {
    if (!modelos || !modelos.length) return null;
    const sg = colunasDeTinta(l.img, l.w, l.h);
    if (sg.length !== l.n) return null;
    let s = '';
    for (const [a, b] of sg) { const g = glifo(l.img, l.w, l.h, a, b); s += (g && classificarGlifo(g, modelos)) || '?'; }
    return s;
  }
  /** Guarda os dígitos da linha com os rótulos do valor confirmado (até 8 por dígito). */
  function aprender(modelos, l, valor) {
    if (!l || valor.length !== l.n) return modelos;
    const sg = colunasDeTinta(l.img, l.w, l.h);
    if (sg.length !== l.n) return modelos;
    const novos = [...modelos];
    sg.forEach(([a, b], i) => {
      const g = glifo(l.img, l.w, l.h, a, b);
      if (!g) return;
      // forma quase igual a um modelo do mesmo dígito: não acrescenta nada
      if (novos.some((m) => m.d === valor[i] && semelhanca(g, m._g || (m._g = deTexto(m.g))) > 0.97)) return;
      novos.push({ d: valor[i], g: paraTexto(g) });
      const doDigito = novos.filter((m) => m.d === valor[i]);
      if (doDigito.length > 8) novos.splice(novos.indexOf(doDigito[0]), 1);
    });
    return novos;
  }

  /** Palpites de uma linha recomposta: a linha inteira (dois modos do OCR) e,
   *  se a tinta separa exatamente n dígitos, grupos de 2, 3 e 4 dígitos. */
  async function palpitesDaLinha(l, ocr, bastam, modelos) {
    const n = l.n, out = [];
    const pm = palpiteModelos(l, modelos);
    if (pm && !pm.includes('?')) { out.push(pm, pm); return out; } // forma conhecida: 2 votos
    if (pm) out.push(pm);
    for (const psm of ['13', '7']) {
      const d = digitosDaLinha(await ocr(l, 0, l.w, psm), n);
      if (d) out.push(d);
    }
    if (out.length === 2 && out[0] === out[1] && bastam(out)) return out;
    const sg = colunasDeTinta(l.img, l.w, l.h);
    if (sg.length !== n) return out;
    for (const [g, psm] of [[3, '7'], [4, '13'], [2, '7']]) {
      let s = '';
      for (let i = 0; i < n; i += g) {
        const p = sg.slice(i, i + g);
        const t = (await ocr(l, Math.max(0, p[0][0] - 4), Math.min(l.w, p[p.length - 1][1] + 4), psm)).replace(/\s/g, '');
        s += /^\d+$/.test(t) && t.length === p.length ? t : '?'.repeat(p.length);
      }
      out.push(s);
      if (bastam(out)) break;
    }
    return out;
  }

  /** Lê a foto: em cada faixa, isola os dígitos (pipeline do app) e junta os
   *  palpites do OCR de todas as variantes da mesma linha; aceita quando cada
   *  dígito tem consenso. dep.acharLinhas(faixa) → linhas (box na foto);
   *  dep.ocr(linha, x0, x1, psm) → texto. */
  async function lerImagem(W, H, dep, opc = {}) {
    const esperado = opc.esperado || null;
    const ant = opc.anteriores || [];
    const faixas = faixasDaFoto(W, H, opc.toque);
    let reserva = null;
    for (let i = 0; i < faixas.length; i++) {
      if (opc.progresso) opc.progresso(i, faixas.length);
      if (opc.cancelado && opc.cancelado()) return null;
      const linhas = (await dep.acharLinhas(faixas[i])).filter((l) => l.n >= 3);
      const porPol = {};
      for (const l of linhas) (porPol[l.variante[0]] = porPol[l.variante[0]] || []).push(l);
      for (const ls of Object.values(porPol)) {
        const n = ls[0].n;
        const palpites = [];
        let valor = null;
        for (const l of ls.filter((x) => x.n === n).slice(0, 4)) {
          const bastam = (p) => consensoPosicional([...palpites, ...p], n) !== null;
          palpites.push(...(await palpitesDaLinha(l, dep.ocr, bastam, opc.modelos)));
          valor = consensoPosicional(palpites, n);
          if (valor) break;
        }
        if (!valor) continue;
        if (ant.length && !plausivel(parseInt(valor, 10), ant)) continue;
        const r = { valor, box: ls[0].box, faixa: faixas[i], linha: ls.find((x) => x.variante.endsWith('mascara')) || ls[0] };
        if (!esperado || valor.length === esperado) return r;
        reserva = reserva || r;
      }
    }
    return reserva;
  }

  g.Prumo = {
    faixasDaFoto, lerImagem, digitosDaLinha, colunasDeTinta, consensoPosicional, glifo, classificarGlifo, palpiteModelos, aprender,
    ESPACO_FINO, ASSINATURA, TIPOS, TEXTO_SITUACAO,
    fmtNum, fmtConsumo, parteInteira, nomeMes, tituloMes, assuntoMes, chaveMes, deChaveMes,
    analisar, pedeConfirmacao, plausivel,
    estadoVazio, chaveLeitura, gerarAptos, aptosAtivos, naOrdemDeLeitura, mesAtual, leiturasDoMes, anteriores, historicoAnterior,
    montarLinhas, pendencias, textoPendencia, assunto, corpoEmail, nomeArquivoPdf, gerarPdf, resumos, numPdf,
  };
})(typeof globalThis !== 'undefined' ? globalThis : this);
