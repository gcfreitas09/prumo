// Prumo web — telas e OCR no navegador. Lógica pura em logica.js (window.Prumo).
(function () {
  'use strict';
  const P = window.Prumo;
  const CHAVE = 'prumo.web.v1';
  const $app = document.getElementById('app');
  const $toast = document.getElementById('toast');

  // ---------------------------------------------------------------- dados
  function carregar() {
    try {
      const s = localStorage.getItem(CHAVE);
      if (s) { const e = JSON.parse(s); if (e && e.versao === 1) return e; }
    } catch (_) { /* navegador sem armazenamento: começa vazio */ }
    return P.estadoVazio();
  }
  let E = carregar();
  let salvoOk = true;
  function salvar() {
    try {
      localStorage.setItem(CHAVE, JSON.stringify(E, (k, v) => (k === '_g' ? undefined : v)));
      salvoOk = true;
    } catch (_) {
      salvoOk = false;
      toast('Este navegador não deixou guardar os dados. Salve uma cópia em Prédio.');
    }
  }
  try { navigator.storage && navigator.storage.persist && navigator.storage.persist(); } catch (_) { /* opcional */ }
  const modelos = () => (E.modelos && E.modelos.length ? E.modelos : (window.PRUMO_SEMENTES || []));

  // ---------------------------------------------------------------- utilidades
  const esc = (s) => String(s === null || s === undefined ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const nomeTipo = (t) => (t === 'agua' ? 'Água' : 'Gás');
  const corTipo = (t) => (t === 'agua' ? 'var(--agua)' : 'var(--gas)');
  const plural = (n, s, p) => `${n} ${n === 1 ? s : p}`;
  const emailOk = (s) => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(s);
  const ICONE = {
    voltar: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 5l-7 7 7 7"/></svg>',
    hist: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/></svg>',
    predio: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M5 20.5V4.5h9v16M14 9.5h5v11M3 20.5h18"/><path d="M8 8h1M10.5 8h1M8 11.5h1M10.5 11.5h1M8 15h1M10.5 15h1M16.5 13h.5M16.5 16h.5" stroke-linecap="round"/></svg>',
    enviar: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M21 3.5L10.5 13.5M21 3.5l-6.5 17-4-7-7-4z"/></svg>',
    cima: '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 14l6-6 6 6"/></svg>',
    baixo: '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 10l6 6 6-6"/></svg>',
    ant: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 5l-7 7 7 7"/></svg>',
    prox: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 5l7 7-7 7"/></svg>',
  };
  // o fio de prumo: linha + peso de latão
  const prumoSvg = (l, h) => `<svg viewBox="0 0 ${l} ${h}" aria-hidden="true"><g class="pendulo"><line x1="${l / 2}" y1="2" x2="${l / 2}" y2="${h - l * 0.62}" stroke="var(--texto2)" stroke-width="1"/><path d="M${l / 2} ${h - 2} L${l * 0.22} ${h - l * 0.42} Q${l * 0.22} ${h - l * 0.62} ${l / 2} ${h - l * 0.62} Q${l * 0.78} ${h - l * 0.62} ${l * 0.78} ${h - l * 0.42} Z" fill="var(--latao)"/></g><circle cx="${l / 2}" cy="2" r="2" fill="var(--texto2)"/></svg>`;
  const barra = (esquerda, direita = '') => `<div class="barra">${esquerda}<span class="esp"></span>${direita}</div>`;
  const btnVoltar = (acao, texto) => `<button class="voltar" data-a="${acao}">${ICONE.voltar}${esc(texto)}</button>`;

  let toastTimer = null;
  function toast(msg, acao) {
    clearTimeout(toastTimer);
    $toast.innerHTML = `<span>${esc(msg)}</span>${acao ? `<button data-toast="1">${esc(acao.texto)}</button>` : ''}`;
    $toast.hidden = false;
    $toast.onclick = (ev) => { if (ev.target.closest('[data-toast]') && acao) { acao.fazer(); $toast.hidden = true; } };
    toastTimer = setTimeout(() => { $toast.hidden = true; }, acao ? 4000 : 3200);
  }

  async function copiar(texto) {
    try { await navigator.clipboard.writeText(texto); toast('Copiado'); } catch (_) { toast('Não deu para copiar. Toque e segure o texto para copiar.'); }
  }

  // capacidade "downloads" do link (claude.ai); fora dele, download comum
  async function capacidade(nome) {
    if (!window.claude || typeof window.claude.use !== 'function') return null;
    try { return await Promise.race([window.claude.use(nome), new Promise((r) => setTimeout(() => r(null), 4000))]); } catch (_) { return null; }
  }
  async function salvarArquivo(nome, blob) {
    const dl = await capacidade('downloads');
    if (dl) {
      try { await dl.save({ filename: nome, data: blob }); return true; } catch (e) {
        if (e && e.code === 'declined') return false;
      }
    }
    try {
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob); a.download = nome; document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(a.href), 4000);
      return true;
    } catch (_) { return false; }
  }

  // ---------------------------------------------------------------- navegação
  let tela = E.predio ? { nome: 'mes' } : { nome: 'entrada' };
  let tipoAtual = 'agua';
  function ir(t) { tela = t; render(); window.scrollTo(0, 0); }
  function render() {
    const f = TELAS[tela.nome] || TELAS.mes;
    $app.innerHTML = f();
    if (tela.depois) { const d = tela.depois; tela.depois = null; d(); }
    if (tela.nome === 'leitura') posLeitura();
    if (tela.nome === 'entrada') animarEntrada(); else if (introMM) { introMM.revert(); introMM = null; }
  }

  // ---------------------------------------------------------------- mês
  const mesK = () => P.mesAtual(E);
  function contexto() {
    const k = mesK();
    const aptos = P.aptosAtivos(E);
    const lei = P.leiturasDoMes(E, k);
    return { k, aptos, lei, ant: P.historicoAnterior(E, k), ...P.deChaveMes(k) };
  }
  function proximoPendente(tipo, depoisDe) {
    const { lei } = contexto();
    const ordem = P.naOrdemDeLeitura(E);
    const i0 = depoisDe ? ordem.findIndex((a) => a.id === depoisDe) + 1 : 0;
    for (let j = 0; j < ordem.length; j++) {
      const a = ordem[(i0 + j) % ordem.length];
      if (!lei[`${a.id}|${tipo}`]) return a;
    }
    return null;
  }

  const TELAS = {};

  // prédio de exemplo da entrada: 6 andares × 4 aptos, lidos na ordem física (de baixo para cima)
  const INTRO_ANDARES = 6, INTRO_POR = 4, INTRO_PENDENTES = 2;
  TELAS.entrada = () => {
    const q = 16, g = 6, larg = INTRO_POR * (q + g) - g, x0 = 170 - larg / 2, y0 = 318;
    let quadros = '';
    for (let a = 0; a < INTRO_ANDARES; a++) {
      for (let c = 0; c < INTRO_POR; c++) {
        const ordem = (INTRO_ANDARES - 1 - a) * INTRO_POR + c; // andar de baixo primeiro
        const lido = ordem < INTRO_ANDARES * INTRO_POR - INTRO_PENDENTES;
        quadros += `<rect class="apto${lido ? ' lido aceso' : ''}" data-o="${ordem}" x="${x0 + c * (q + g)}" y="${y0 + a * (q + g)}" width="${q}" height="${q}" rx="3.5"/>`;
      }
    }
    const lidos = INTRO_ANDARES * INTRO_POR - INTRO_PENDENTES;
    return `
    <div class="intro">
      <svg class="cena" viewBox="0 0 340 452" role="img" aria-label="Fio de prumo parado sobre a marca, acima do mapa de um prédio com ${lidos} de ${INTRO_ANDARES * INTRO_POR} apartamentos lidos">
        <line x1="70" y1="300" x2="270" y2="300" stroke="var(--fio)" stroke-width="1"/>
        <circle class="eco" cx="170" cy="300" r="14" fill="none" stroke="var(--acao)" stroke-width="1.2"/>
        <g class="marca-chao" stroke="var(--acao)" stroke-width="1.6" stroke-linecap="round"><line x1="163" y1="300" x2="177" y2="300"/><line x1="170" y1="293" x2="170" y2="307"/></g>
        <g id="pendulo">
          <line x1="170" y1="-400" x2="170" y2="${292 - 70 * 1.35}" stroke="var(--texto2)" stroke-width="1"/>
          <g transform="translate(170 292) scale(1.35) translate(-170 -292)">
          <rect x="161" y="222" width="18" height="5" rx="1.5" fill="var(--latao)"/>
          <rect x="156" y="226" width="28" height="9" rx="2" fill="var(--latao)"/>
          <path d="M156 235 H170 V292 Z" fill="var(--latao)"/>
          <path d="M170 235 H184 L170 292 Z" fill="var(--latao)" style="filter:brightness(.72)"/>
          <path d="M184 226 v9 h-6 v-9 z" fill="#000" opacity=".16"/>
          </g>
        </g>
        <g id="predio">${quadros}</g>
      </svg>
      <div class="texto">
        <h1>Prumo</h1>
        <p class="sub">Água e gás do prédio, lidos pela foto do medidor.</p>
        <p class="legenda num intro-conta" style="margin:10px 0 0">${lidos} de ${INTRO_ANDARES * INTRO_POR} medidores lidos</p>
      </div>
      <div class="rodape">
        <button class="btn" data-a="comecar">Configurar o prédio</button>
        <label class="btn sec" style="margin-top:10px">Restaurar uma cópia<input class="arquivo" type="file" accept="application/json,.json" data-arq="restaurar"></label>
        <p class="legenda" style="text-align:center;margin:12px 0 0">Os dados ficam só neste celular.</p>
      </div>
    </div>`;
  };
  // a cena acima já é o estado final (vale sem JS e com movimento reduzido); o GSAP só a encena
  let introMM = null;
  function animarEntrada() {
    if (!window.gsap) return;
    const gsap = window.gsap;
    if (introMM) introMM.revert();
    introMM = gsap.matchMedia();
    introMM.add('(prefers-reduced-motion: no-preference)', () => {
      const pend = document.getElementById('pendulo');
      if (!pend) return;
      const lidos = gsap.utils.toArray('#predio .lido').sort((a, b) => a.dataset.o - b.dataset.o);
      const tl = gsap.timeline({ defaults: { ease: 'power2.out' } });
      lidos.forEach((r) => r.classList.remove('aceso'));
      // desce do teto já balançando; o balanço amortece (θ = A·e^(−kt)·cos ωt) e para no zero
      const onda = { t: 0 };
      const angulo = (t) => 7 * Math.exp(-3.1 * t) * Math.cos(2 * Math.PI * 2.15 * t) * (1 - t);
      tl.fromTo(pend, { y: -300 }, { y: 0, duration: 0.7, ease: 'power3.out' }, 0)
        .to(onda, { t: 1, duration: 2.6, ease: 'none', onUpdate: () => gsap.set(pend, { rotation: angulo(onda.t), svgOrigin: '170 -400' }) }, 0)
        .fromTo('.intro .marca-chao', { scale: 0.4, opacity: 0.3, svgOrigin: '170 300' }, { scale: 1, opacity: 1, duration: 0.3, ease: 'back.out(3)' }, 2.45)
        .fromTo('.intro .eco', { scale: 0.5, opacity: 0.9, svgOrigin: '170 300' }, { scale: 2.6, opacity: 0, duration: 0.9 }, 2.45);
      lidos.forEach((r, i) => tl.call(() => r.classList.add('aceso'), null, 2.6 + i * 0.04));
      tl
        .from('.intro .texto > *', { y: 10, opacity: 0, duration: 0.5, stagger: 0.08 }, 0.5)
        .from('.intro .rodape', { y: 14, opacity: 0, duration: 0.5 }, 0.75);
      return () => { tl.kill(); lidos.forEach((r) => r.classList.add('aceso')); };
    });
  }

  TELAS.mes = () => {
    const { k, aptos, lei, ant, ano, mes } = contexto();
    const total = aptos.length * 2, lidos = Object.keys(lei).filter((x) => aptos.some((a) => x.startsWith(a.id + '|'))).length;
    const cont = (t) => aptos.filter((a) => lei[`${a.id}|${t}`]).length;
    const andares = [...new Set(aptos.map((a) => a.andar))].sort((a, b) => b - a);
    const prox = proximoPendente(tipoAtual);
    const enviado = E.meses[k] && E.meses[k].enviadoEm;
    return `
    ${barra(`<span class="legenda">${esc(E.predio.nome)}</span>`,
      `<button class="icone" data-a="historico" aria-label="Histórico">${ICONE.hist}</button><button class="icone" data-a="predio" aria-label="Prédio">${ICONE.predio}</button><button class="icone" data-a="revisao" aria-label="Revisar e enviar">${ICONE.enviar}</button>`)}
    <h1>${esc(P.tituloMes(ano, mes))}</h1>
    <p class="sub num">${lidos} de ${total} medidores lidos${enviado ? ' · <span class="ok-txt">enviado</span>' : ''}</p>
    <div class="seg" role="group" aria-label="Medidor">
      ${P.TIPOS.map((t) => `<button data-a="tipo" data-t="${t}" aria-pressed="${t === tipoAtual}">${nomeTipo(t)}<span class="cont num">${cont(t)}/${aptos.length}</span></button>`).join('')}
    </div>
    <div class="mapa" aria-hidden="true">
      ${andares.map((n) => `<div class="andar"><span class="n num">${n}</span>${aptos.filter((a) => a.andar === n).map((a) => `<i style="${lei[`${a.id}|${tipoAtual}`] ? `background:${corTipo(tipoAtual)}` : ''}"></i>`).join('')}</div>`).join('')}
    </div>
    ${andares.map((n) => `
      <div class="andar-titulo">${n}º andar</div>
      ${aptos.filter((a) => a.andar === n).map((a) => {
        const l = lei[`${a.id}|${tipoAtual}`];
        let dir;
        if (l) {
          const an = P.analisar(P.parteInteira(l.valor), ant[`${a.id}|${tipoAtual}`] || []);
          dir = `<span class="v">${P.fmtNum(l.valor)}</span>${an.consumo !== null ? `<br><span class="c">${P.fmtConsumo(an.consumo)}</span>` : ''}`;
        } else dir = '<span class="link">Ler</span>';
        return `<button class="linha" data-a="ler" data-id="${a.id}"><span class="p">${esc(a.numero)}</span><span class="d">${dir}</span></button>`;
      }).join('')}`).join('')}
    <div class="rodape">
      ${prox ? `<button class="btn" data-a="ler" data-id="${prox.id}">Ler ${esc(prox.numero)}</button>`
        : `<button class="btn" data-a="revisao">${proximoPendente(tipoAtual === 'agua' ? 'gas' : 'agua') ? `Ler ${nomeTipo(tipoAtual === 'agua' ? 'gas' : 'agua').toLowerCase()}` : 'Revisar e enviar'}</button>`}
    </div>`;
  };

  // ---------------------------------------------------------------- leitura
  // estado da tela de leitura (fora do render)
  let L = null;
  function abrirLeitura(aptoId, tipo) {
    const { lei, ant } = contexto();
    const ex = lei[`${aptoId}|${tipo}`];
    if (L && L.url) URL.revokeObjectURL(L.url);
    L = { aptoId, tipo, ant: ant[`${aptoId}|${tipo}`] || [], valor: ex ? ex.valor : '', editando: false, insistir: false,
      url: null, W: 0, H: 0, img: null, lendo: false, progresso: '', box: null, linha: null, origem: ex ? 'salva' : null, gen: 0 };
    tipoAtual = tipo;
    ir({ nome: 'leitura' });
  }
  function esperadoDigitos() {
    // nº de dígitos do medidor: o mais comum entre as leituras deste mês do mesmo tipo; senão, o do mês anterior
    const { lei } = contexto();
    const c = {};
    for (const [k, l] of Object.entries(lei)) if (k.endsWith('|' + L.tipo) && /^\d+$/.test(l.valor)) c[l.valor.length] = (c[l.valor.length] || 0) + 1;
    const r = Object.entries(c).sort((a, b) => b[1] - a[1])[0];
    if (r && r[1] >= 2) return Number(r[0]);
    return null;
  }

  TELAS.leitura = () => {
    const apto = E.aptos.find((a) => a.id === L.aptoId);
    const ordem = P.naOrdemDeLeitura(E);
    const i = ordem.findIndex((a) => a.id === L.aptoId);
    const v = L.valor ? parseInt(L.valor, 10) : null;
    const an = P.analisar(v, L.ant);
    const cor = an.situacao === 'negativo' ? 'var(--erro)' : an.situacao === 'acima' ? 'var(--aviso)' : 'var(--ok)';
    const foto = L.url
      ? `<div class="foto" id="foto"><img id="fotoImg" src="${L.url}" alt="Foto do medidor de ${nomeTipo(L.tipo).toLowerCase()} do apto ${esc(apto.numero)}">
          ${L.box ? `<span class="caixa" style="left:${(L.box[0] / L.W) * 100}%;top:${(L.box[1] / L.H) * 100}%;width:${((L.box[2] - L.box[0]) / L.W) * 100}%;height:${((L.box[3] - L.box[1]) / L.H) * 100}%"></span>` : ''}
          ${L.lendo ? '' : '<span class="toque">Leitura errada? Toque em cima dos números na foto.</span>'}</div>`
      : `<div class="foto"><div class="vazia"><p>Fotografe o medidor de perto, com os números ocupando boa parte da foto.</p>
          <label class="btn" style="max-width:280px">Fotografar medidor<input class="arquivo" type="file" accept="image/*" capture="environment" data-arq="foto"></label></div></div>`;
    return `
    ${barra(btnVoltar('mes', 'Mês'), `<button class="icone" data-a="apto-ant" aria-label="Apartamento anterior" ${i <= 0 ? 'disabled' : ''}>${ICONE.ant}</button><button class="icone" data-a="apto-prox" aria-label="Próximo apartamento" ${i >= ordem.length - 1 ? 'disabled' : ''}>${ICONE.prox}</button>`)}
    <p class="legenda" style="margin:0">Apto ${esc(apto.numero)} · ${nomeTipo(L.tipo)}</p>
    <div id="arrasto">
    ${foto}
    ${L.lendo ? `<div class="prumo">${prumoSvg(28, 56)}<span>${esc(L.progresso || 'Lendo os números…')}</span></div>` : ''}
    ${L.editando
      ? `<input class="entrada valor num" id="campoValor" inputmode="numeric" pattern="[0-9]*" autocomplete="off" value="${esc(L.valor)}" aria-label="Leitura" style="font-size:40px;min-height:64px;color:${corTipo(L.tipo)}">`
      : `<p class="valor ${L.valor ? '' : 'vazio'}" style="${L.valor ? `color:${corTipo(L.tipo)}` : ''}">${L.valor ? P.fmtNum(L.valor) : '—'}</p>`}
    ${L.origem === 'ocr' && !L.lendo ? '<p class="legenda" style="margin:2px 0 0">Lido na foto. Confira com o medidor antes de confirmar.</p>' : ''}
    ${L.origem === 'nada' && !L.lendo ? '<p class="aviso-forte">Não achei os números. Toque em cima deles na foto, tire outra mais de perto ou digite.</p>' : ''}
    <div class="dados lista">
      <div class="linha"><span class="p">Mês anterior</span><span class="v" style="color:var(--texto2)">${L.ant.length ? P.fmtNum(L.ant[0]) : '—'}</span></div>
      <div class="linha"><span class="p">Consumo</span><span class="v" style="color:var(--texto2)">${an.consumo !== null ? P.fmtConsumo(an.consumo) : '—'}</span></div>
      ${v !== null ? `<div class="linha"><span class="p situacao" style="color:${cor}">${esc(P.TEXTO_SITUACAO[an.situacao])}</span>${an.media !== null ? `<span class="c">média ${P.fmtConsumo(an.media)}</span>` : ''}</div>` : ''}
    </div>
    ${L.insistir ? `<p class="aviso-forte">${an.situacao === 'negativo' ? 'A leitura é menor que a do mês anterior.' : 'O consumo passou do dobro da média.'} Confira o número. Se estiver certo, toque de novo em Confirmar.</p>` : ''}
    </div>
    <div class="rodape">
      ${L.url ? `<label class="btn-texto" style="display:inline-flex;align-items:center">Tirar outra foto<input class="arquivo" type="file" accept="image/*" capture="environment" data-arq="foto"></label>` : ''}
      <div class="dupla">
        <button class="btn sec" data-a="editar">${L.editando ? 'Pronto' : L.valor ? 'Editar' : 'Digitar'}</button>
        <button class="btn" data-a="confirmar" ${L.valor && /^\d+$/.test(L.valor) ? '' : 'disabled'}>${L.insistir ? 'Confirmar mesmo assim' : 'Confirmar'}</button>
      </div>
    </div>`;
  };
  function posLeitura() {
    const c = document.getElementById('campoValor');
    if (c) {
      c.focus();
      c.oninput = () => {
        const s = c.value.replace(/\D/g, '');
        if (s !== c.value) c.value = s;
        L.valor = s; L.insistir = false; L.origem = 'manual';
        const b = $app.querySelector('[data-a="confirmar"]');
        if (b) b.disabled = !s;
      };
      c.onkeydown = (e) => { if (e.key === 'Enter') { L.editando = false; render(); } };
    }
    const img = document.getElementById('fotoImg');
    if (img) img.onclick = (ev) => {
      if (L.lendo) return;
      const r = img.getBoundingClientRect();
      // a imagem tem object-fit: contain — converte o toque para a foto
      const esc0 = Math.min(r.width / L.W, r.height / L.H), dw = L.W * esc0, dh = L.H * esc0;
      const x = (ev.clientX - r.left - (r.width - dw) / 2) / dw, y = (ev.clientY - r.top - (r.height - dh) / 2) / dh;
      if (x < 0 || x > 1 || y < 0 || y > 1) return;
      lerFoto([x, y]);
    };
    // deslizar troca de apto
    const ar = document.getElementById('arrasto');
    if (ar) {
      let x0 = null, y0 = null;
      ar.ontouchstart = (e) => { if (e.target.closest('#foto')) return; x0 = e.touches[0].clientX; y0 = e.touches[0].clientY; };
      ar.ontouchend = (e) => {
        if (x0 === null) return;
        const dx = e.changedTouches[0].clientX - x0, dy = e.changedTouches[0].clientY - y0;
        x0 = null;
        if (Math.abs(dx) > 70 && Math.abs(dx) > 2 * Math.abs(dy)) acao(dx < 0 ? 'apto-prox' : 'apto-ant');
      };
    }
  }

  async function receberFoto(arquivo) {
    if (!arquivo) return;
    if (L.url) URL.revokeObjectURL(L.url);
    const url = URL.createObjectURL(arquivo);
    const img = new Image();
    img.src = url;
    try { await img.decode(); } catch (_) { toast('Não consegui abrir essa foto. Tente de novo.'); return; }
    // até 2000 px no lado maior (memória do celular); a orientação da câmera já vem aplicada
    const k = Math.min(1, 2000 / Math.max(img.naturalWidth, img.naturalHeight));
    const cv = document.createElement('canvas');
    cv.width = Math.round(img.naturalWidth * k); cv.height = Math.round(img.naturalHeight * k);
    cv.getContext('2d').drawImage(img, 0, 0, cv.width, cv.height);
    Object.assign(L, { url, W: cv.width, H: cv.height, img: cv, box: null, linha: null, valor: L.origem === 'salva' ? L.valor : '', editando: false, insistir: false });
    await lerFoto(null);
  }

  // ---------------------------------------------------------------- OCR
  let wPipeline = null, pedidos = new Map(), nPedido = 0;
  function pipeline() {
    if (!wPipeline) {
      wPipeline = new Worker(new URL('ocr_worker.js', location.href));
      wPipeline.onmessage = (e) => { const p = pedidos.get(e.data.id); if (p) { pedidos.delete(e.data.id); e.data.erro ? p.rej(new Error(e.data.erro)) : p.res(e.data.linhas); } };
      wPipeline.onerror = (e) => { for (const p of pedidos.values()) p.rej(new Error(e.message || 'worker')); pedidos.clear(); wPipeline = null; };
    }
    return wPipeline;
  }
  function acharLinhasNoWorker(rgba, w, h) {
    return new Promise((res, rej) => {
      const id = ++nPedido;
      pedidos.set(id, { res, rej });
      pipeline().postMessage({ id, rgba: rgba.buffer, w, h, faixa: [0, 0, w, h] }, [rgba.buffer]);
    });
  }
  let tess = null, psmAtual = null;
  function tesseract() {
    if (!tess) {
      const base = new URL('.', location.href).href.replace(/\/$/, '');
      tess = (async () => {
        if (!window.Tesseract) throw new Error('Tesseract não carregou');
        const w = await window.Tesseract.createWorker('eng', 1, {
          workerPath: new URL('tesseract-worker.min.js', location.href).href, workerBlobURL: false,
          corePath: base, langPath: base, gzip: false,
        });
        await w.setParameters({ tessedit_char_whitelist: '0123456789' });
        return w;
      })();
      tess.catch(() => { tess = null; });
    }
    return tess;
  }
  const MAXW = 864;
  function dependencias(fonte) {
    return {
      acharLinhas: async (f) => {
        const k = Math.min(1, MAXW / f[2]);
        const w = Math.max(1, Math.round(f[2] * k)), h = Math.max(1, Math.round(f[3] * k));
        const cv = document.createElement('canvas');
        cv.width = w; cv.height = h;
        const cx = cv.getContext('2d', { willReadFrequently: true });
        cx.drawImage(fonte, f[0], f[1], f[2], f[3], 0, 0, w, h);
        const d = cx.getImageData(0, 0, w, h).data;
        const ls = await acharLinhasNoWorker(new Uint8Array(d.buffer.slice(0)), w, h);
        return ls.map((l) => ({ ...l, box: l.box.map((v, i) => Math.round(v / k) + (i % 2 ? f[1] : f[0])) }));
      },
      ocr: async (l, x0, x1, psm) => {
        const w = await tesseract();
        if (psm !== psmAtual) { await w.setParameters({ tessedit_pageseg_mode: psm }); psmAtual = psm; }
        const m = 16, ww = x1 - x0;
        const cv = document.createElement('canvas');
        cv.width = ww + 2 * m; cv.height = l.h + 2 * m;
        const cx = cv.getContext('2d');
        const im = cx.createImageData(cv.width, cv.height);
        im.data.fill(255);
        for (let y = 0; y < l.h; y++) for (let x = 0; x < ww; x++) {
          const v = l.img[y * l.w + x0 + x], o = ((y + m) * cv.width + x + m) * 4;
          im.data[o] = im.data[o + 1] = im.data[o + 2] = v;
        }
        cx.putImageData(im, 0, 0);
        return (await w.recognize(cv)).data.text;
      },
    };
  }
  async function lerFoto(toque) {
    if (!L || !L.img) return;
    const gen = ++L.gen, alvo = L;
    Object.assign(L, { lendo: true, progresso: toque ? 'Lendo onde você tocou…' : 'Procurando os números…', box: null, insistir: false });
    render();
    tesseract().catch(() => {}); // começa a carregar o OCR em paralelo
    let r = null, falha = null;
    try {
      r = await P.lerImagem(L.W, L.H, dependencias(L.img), {
        toque, anteriores: L.ant, esperado: esperadoDigitos() || (L.ant.length ? String(L.ant[0]).length : null), modelos: modelos(),
        cancelado: () => alvo !== L || gen !== alvo.gen,
        progresso: (i, n) => { if (alvo === L && gen === L.gen && i > 0) { L.progresso = `Procurando os números… ${i + 1} de ${n}`; const s = $app.querySelector('.prumo span'); if (s) s.textContent = L.progresso; } },
      });
    } catch (e) { falha = e; }
    if (alvo !== L || gen !== L.gen) return;
    L.lendo = false;
    if (r) Object.assign(L, { valor: r.valor, box: r.box, linha: r.linha, origem: 'ocr' });
    else { L.origem = falha ? 'nada' : 'nada'; if (falha) toast('O leitor de números não abriu neste navegador. Digite a leitura.'); }
    render();
  }

  function confirmar() {
    const v = L.valor;
    if (!/^\d+$/.test(v)) return;
    const an = P.analisar(parseInt(v, 10), L.ant);
    if (P.pedeConfirmacao(an) && !L.insistir) { L.insistir = true; render(); return; }
    const k = mesK(), ch = P.chaveLeitura(k, L.aptoId, L.tipo);
    const antes = E.leituras[ch], modelosAntes = E.modelos;
    E.leituras[ch] = { valor: v, lidoEm: new Date().toISOString(), manual: L.origem !== 'ocr' };
    // os dígitos da foto, com o número confirmado (ou corrigido), viram modelos
    if (L.linha && L.linha.n === v.length) {
      try { E.modelos = P.aprender(modelos(), L.linha, v); } catch (_) { /* aprender é opcional */ }
    }
    salvar();
    const apto = E.aptos.find((a) => a.id === L.aptoId), tipo = L.tipo, aptoId = L.aptoId;
    toast(`Leitura salva · ${apto.numero}`, { texto: 'Desfazer', fazer: () => {
      if (antes) E.leituras[ch] = antes; else delete E.leituras[ch];
      E.modelos = modelosAntes; salvar(); abrirLeitura(aptoId, tipo);
    } });
    const prox = proximoPendente(tipo, aptoId);
    if (prox) abrirLeitura(prox.id, tipo); else { L = null; ir({ nome: 'mes' }); }
  }

  // ---------------------------------------------------------------- revisão e envio
  TELAS.revisao = () => {
    const { k, aptos, lei, ant, ano, mes } = contexto();
    const pend = P.pendencias(P.naOrdemDeLeitura(E), lei);
    const linhas = P.montarLinhas(aptos, lei, ant);
    const total = linhas.length * 2, lidos = total - pend.length;
    const emails = E.predio.emails || [];
    const enviado = E.meses[k].enviadoEm;
    const ass = P.assunto(E.predio, ano, mes);
    const ponto = (c) => `<span class="pt" style="background:${c}"></span>`;
    return `
    ${barra(btnVoltar('mes', 'Mês'))}
    <h1>Revisar e enviar</h1>
    <p class="sub">${esc(P.tituloMes(ano, mes))}${enviado ? ` · <span class="ok-txt">marcado como enviado em ${new Date(enviado).toLocaleDateString('pt-BR')}</span>` : ''}</p>
    ${pend.length ? `<div class="rotulo" style="color:var(--aviso)">Pendentes · ${pend.length}</div><div class="lista">
      ${pend.slice(0, tela.todas ? pend.length : 6).map((p) => `<button class="linha" data-a="ler-tipo" data-id="${p.apto.id}" data-t="${p.tipo}"><span class="p">${esc(P.textoPendencia(p))}</span><span class="link">Ler</span></button>`).join('')}
      ${pend.length > 6 && !tela.todas ? `<button class="linha" data-a="todas-pendentes"><span class="p link">Ver as outras ${pend.length - 6}</span></button>` : ''}</div>`
      : `<p class="ok-txt">Todos os ${total} medidores lidos.</p>`}
    <div class="rotulo">Prévia do PDF</div>
    <div class="previa"><div class="folha">
      <div class="eyebrow">LEITURA DE ÁGUA E GÁS</div>
      <div class="nome">${esc(E.predio.nome)}</div><div class="mes">${esc(P.tituloMes(ano, mes))}</div>
      <div class="regua"></div>
      <div class="meta"><span>${linhas.length} apartamentos · ${lidos} de ${total} medidores lidos</span><span>Emitido em ${new Date().toLocaleDateString('pt-BR')}</span></div>
      <table><thead><tr><th>APTO</th><th>${ponto('#2B7BD6')}ÁGUA</th><th>${ponto('#DD6B2B')}GÁS</th></tr></thead><tbody>
      ${linhas.map((l) => `<tr><td>${esc(l.numero)}</td><td class="${l.agua === null ? 'falta' : ''}">${l.agua === null ? '-' : P.fmtNum(l.agua)}</td><td class="${l.gas === null ? 'falta' : ''}">${l.gas === null ? '-' : P.fmtNum(l.gas)}</td></tr>`).join('')}
      </tbody></table>
      ${pend.length ? `<p class="falta" style="font-size:8px;margin:8px 0 0">"-" = medidor sem leitura neste mês (${pend.length}).</p>` : ''}
      <div class="rod"><span>Responsável: ${esc(P.ASSINATURA)}</span><span>Página 1</span></div>
    </div></div>
    <div class="rotulo">E-mail</div>
    <div class="copiar"><span class="p">${emails.length ? esc(emails.join(', ')) : '<span style="color:var(--aviso)">Nenhum e-mail de destino. Adicione em Prédio.</span>'}</span>${emails.length ? '<button class="btn-texto" data-a="copiar" data-c="para">Copiar</button>' : ''}</div>
    <div class="copiar"><span class="p">${esc(ass)}</span><button class="btn-texto" data-a="copiar" data-c="assunto">Copiar</button></div>
    <div class="copiar"><span class="p">${esc(P.corpoEmail().trim())}</span><button class="btn-texto" data-a="copiar" data-c="corpo">Copiar</button></div>
    <p class="legenda">Salve o PDF, abra o e-mail e anexe o arquivo salvo.</p>
    <div class="rodape">
      <button class="btn" data-a="pdf">${navigator.canShare ? 'Enviar PDF' : 'Salvar PDF'}${pend.length ? ` · ${plural(pend.length, 'pendente', 'pendentes')}` : ''}</button>
      <div class="dupla" style="margin-top:10px">
        <a class="btn sec" href="mailto:${encodeURIComponent(emails.join(','))}?subject=${encodeURIComponent(ass)}&body=${encodeURIComponent(P.corpoEmail())}" target="_blank" rel="noopener">Abrir e-mail</a>
        <button class="btn sec" data-a="marcar-enviado">${enviado ? 'Desmarcar' : 'Marcar enviado'}</button>
      </div>
    </div>`;
  };
  async function gerarEEnviarPdf() {
    const { aptos, lei, ant, ano, mes } = contexto();
    if (!window.jspdf) { toast('O gerador de PDF não carregou. Verifique a internet e abra de novo.'); return; }
    const doc = P.gerarPdf(window.jspdf.jsPDF, E.predio, ano, mes, P.montarLinhas(aptos, lei, ant));
    const nome = P.nomeArquivoPdf(ano, mes);
    const blob = doc.output('blob');
    // fora do link do Claude (site próprio): folha de compartilhar com Mail
    try {
      const arq = new File([blob], nome, { type: 'application/pdf' });
      if (navigator.canShare && navigator.canShare({ files: [arq] })) {
        await navigator.share({ files: [arq], title: P.assunto(E.predio, ano, mes), text: P.corpoEmail() });
        return;
      }
    } catch (e) { if (e && e.name === 'AbortError') return; }
    const ok = await salvarArquivo(nome, blob);
    toast(ok ? 'PDF salvo. Anexe no e-mail.' : 'O PDF não foi salvo.');
  }

  // ---------------------------------------------------------------- histórico
  TELAS.historico = () => {
    const rs = P.resumos(E);
    return `
    ${barra(btnVoltar('mes', 'Mês'))}
    <h1>Histórico</h1>
    <div class="lista" style="margin-top:12px">
    ${rs.map((r) => `<div class="linha"><span class="p">${esc(P.tituloMes(r.ano, r.mes))}<br><span class="legenda num">${r.lidos} de ${r.total} lidos${r.enviadoEm ? ' · enviado' : ''}</span></span>
      <span class="d c">${r.temAnterior ? `<span style="color:var(--agua)">Água ${P.fmtConsumo(r.agua)}</span><br><span style="color:var(--gas)">Gás ${P.fmtConsumo(r.gas)}</span>` : 'primeiro mês'}</span></div>`).join('')}
    </div>`;
  };

  // ---------------------------------------------------------------- prédio (configuração)
  // rascunho editado nas telas de configuração; só vira E ao concluir
  let C = null;
  function abrirConfig(primeira) {
    C = {
      primeira, passo: 0, erro: '', confirmarGerar: false, confirmarRestaurar: null,
      nome: E.predio ? E.predio.nome : '',
      ini: 1, fim: 6, por: 4,
      aptos: E.aptos.map((a) => ({ ...a })),
      emails: E.predio ? [...(E.predio.emails || []), '', ''].slice(0, 2) : ['', ''],
    };
    if (C.aptos.length) {
      const andares = C.aptos.map((a) => a.andar);
      C.ini = Math.min(...andares); C.fim = Math.max(...andares);
      C.por = Math.max(...andares.map((n) => C.aptos.filter((a) => a.andar === n).length));
    }
    ir({ nome: 'config' });
  }
  const temLeituras = () => Object.keys(E.leituras).length > 0;
  const PASSOS = ['Nome', 'Apartamentos', 'Ordem de leitura', 'E-mails'];
  TELAS.config = () => {
    const passo = C.primeira ? C.passo : -1;
    const sec = (i, html) => (passo === -1 || passo === i ? html : '');
    const ordem = [...C.aptos].filter((a) => a.ativo).sort((a, b) => a.ordemLeitura - b.ordemLeitura);
    const andares = [...new Set(C.aptos.map((a) => a.andar))].sort((a, b) => a - b);
    return `
    ${barra(C.primeira ? (C.passo > 0 ? btnVoltar('cfg-voltar', 'Voltar') : btnVoltar('entrada', 'Início')) : btnVoltar('mes', 'Mês'))}
    <h1>${C.primeira ? esc(PASSOS[C.passo]) : 'Prédio'}</h1>
    ${C.primeira ? `<div class="passos" aria-label="Passo ${C.passo + 1} de 4">${PASSOS.map((_, i) => `<i class="${i <= C.passo ? 'feito' : ''}"></i>`).join('')}</div>` : ''}
    ${sec(0, `<label class="campo"><span>Nome do prédio</span><input id="cNome" data-c="nome" value="${esc(C.nome)}" autocomplete="off" placeholder="Edifício Aurora"></label>`)}
    ${sec(1, `${C.primeira ? '' : '<div class="rotulo">Apartamentos</div>'}
      ${!C.aptos.length || !temLeituras() ? `<div class="tres">
        <label class="campo"><span>Andar inicial</span><input id="cIni" data-c="ini" inputmode="numeric" value="${C.ini}"></label>
        <label class="campo"><span>Andar final</span><input id="cFim" data-c="fim" inputmode="numeric" value="${C.fim}"></label>
        <label class="campo"><span>Aptos por andar</span><input id="cPor" data-c="por" inputmode="numeric" value="${C.por}"></label></div>
        <button class="btn sec" data-a="gerar">${C.aptos.length ? (C.confirmarGerar ? 'Toque de novo para refazer a lista' : 'Refazer a lista') : 'Gerar apartamentos'}</button>` : ''}
      ${C.aptos.length ? `<p class="legenda" style="margin:14px 0 4px">Toque no número para renomear. Desligue os que não têm medidor.</p>
        ${andares.map((n) => `<div class="andar-titulo">${n}º andar</div>${C.aptos.filter((a) => a.andar === n).map((a) => `
          <div class="linha"><input class="apto-num" id="apto${a.id}" data-apto="${a.id}" value="${esc(a.numero)}" aria-label="Número do apartamento"><span class="p legenda">${a.ativo ? '' : 'sem leitura'}</span>
          <button class="chave" role="switch" aria-checked="${a.ativo}" aria-label="Ler o apto ${esc(a.numero)}" data-a="ativo" data-id="${a.id}"></button></div>`).join('')}`).join('')}` : ''}`)}
    ${sec(2, `${C.primeira ? '<p class="legenda" style="margin:0 0 8px">Ordem em que você passa pelos medidores. O botão "Ler" segue esta ordem.</p>' : '<div class="rotulo">Ordem de leitura</div>'}
      <div class="lista">${ordem.map((a, i) => `<div class="linha"><span class="p num">${esc(a.numero)}</span><span class="setas">
        <button data-a="subir" data-id="${a.id}" aria-label="Subir ${esc(a.numero)}" ${i === 0 ? 'disabled' : ''}>${ICONE.cima}</button>
        <button data-a="descer" data-id="${a.id}" aria-label="Descer ${esc(a.numero)}" ${i === ordem.length - 1 ? 'disabled' : ''}>${ICONE.baixo}</button></span></div>`).join('')}</div>`)}
    ${sec(3, `${C.primeira ? '' : '<div class="rotulo">E-mails de destino</div>'}
      <label class="campo"><span>Para quem vai o PDF</span><input id="cE0" data-c="e0" type="email" inputmode="email" autocomplete="email" value="${esc(C.emails[0])}" placeholder="administradora@exemplo.com"></label>
      <label class="campo"><span>Segundo e-mail (opcional)</span><input id="cE1" data-c="e1" type="email" inputmode="email" value="${esc(C.emails[1])}"></label>`)}
    ${C.erro ? `<p class="erro-txt">${esc(C.erro)}</p>` : ''}
    ${C.primeira ? '' : `<div class="rotulo">Cópia de segurança</div>
      <p class="legenda" style="margin:0 0 10px">Os dados ficam só neste navegador. Salve uma cópia de vez em quando (e antes de trocar de celular).</p>
      <div class="dupla"><button class="btn sec" data-a="backup">Salvar cópia</button>
      <label class="btn sec">Restaurar<input class="arquivo" type="file" accept="application/json,.json" data-arq="restaurar"></label></div>`}
    <div class="rodape"><button class="btn" data-a="cfg-ok">${C.primeira ? (C.passo < 3 ? 'Continuar' : 'Começar a ler') : 'Salvar'}</button></div>`;
  };
  function validarPasso(p) {
    if (p === 0 && !C.nome.trim()) return 'Escreva o nome do prédio.';
    if (p === 1) {
      if (!C.aptos.length) return 'Gere os apartamentos.';
      if (!C.aptos.some((a) => a.ativo)) return 'Deixe pelo menos um apartamento ligado.';
      const nums = C.aptos.map((a) => a.numero.trim());
      if (nums.some((n) => !n)) return 'Todo apartamento precisa de número.';
      if (new Set(nums).size !== nums.length) return 'Há números de apartamento repetidos.';
    }
    if (p === 3) {
      const [a, b] = C.emails.map((x) => x.trim());
      if (!emailOk(a)) return 'Escreva um e-mail válido no primeiro campo.';
      if (b && !emailOk(b)) return 'O segundo e-mail não parece válido.';
      if (b && a.toLowerCase() === b.toLowerCase()) return 'Os dois e-mails são iguais.';
    }
    return '';
  }
  function concluirConfig() {
    for (const p of C.primeira ? [C.passo] : [0, 1, 3]) {
      const e = validarPasso(p);
      if (e) { C.erro = e; render(); return; }
    }
    C.erro = '';
    if (C.primeira && C.passo < 3) { C.passo++; render(); window.scrollTo(0, 0); return; }
    E.predio = { nome: C.nome.trim(), emails: C.emails.map((x) => x.trim()).filter(Boolean) };
    E.aptos = C.aptos.map((a) => ({ ...a, numero: a.numero.trim() }));
    P.mesAtual(E);
    salvar();
    const primeira = C.primeira;
    C = null;
    ir({ nome: 'mes' });
    if (!primeira) toast('Prédio salvo');
  }

  // ---------------------------------------------------------------- cópia
  async function salvarCopia() {
    const blob = new Blob([JSON.stringify(E, (k, v) => (k === '_g' ? undefined : v), 1)], { type: 'application/json' });
    const d = new Date();
    const ok = await salvarArquivo(`prumo-copia-${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}.json`, blob);
    toast(ok ? 'Cópia salva' : 'A cópia não foi salva.');
  }
  async function restaurar(arquivo) {
    try {
      const e = JSON.parse(await arquivo.text());
      if (!e || e.versao !== 1 || !e.predio || !Array.isArray(e.aptos)) throw new Error('formato');
      E = e; salvar(); C = null; L = null;
      toast('Cópia restaurada');
      ir({ nome: 'mes' });
    } catch (_) { toast('Este arquivo não é uma cópia do Prumo.'); }
  }

  // ---------------------------------------------------------------- eventos
  function acao(a, el) {
    const id = el && el.dataset.id ? Number(el.dataset.id) : null;
    switch (a) {
      case 'comecar': abrirConfig(true); break;
      case 'entrada': ir({ nome: 'entrada' }); break;
      case 'mes': L = null; ir({ nome: 'mes' }); break;
      case 'historico': ir({ nome: 'historico' }); break;
      case 'predio': abrirConfig(false); break;
      case 'revisao': ir({ nome: 'revisao' }); break;
      case 'tipo': tipoAtual = el.dataset.t; render(); break;
      case 'ler': abrirLeitura(id, tipoAtual); break;
      case 'ler-tipo': abrirLeitura(id, el.dataset.t); break;
      case 'apto-ant': case 'apto-prox': {
        if (!L || L.lendo) break;
        const o = P.naOrdemDeLeitura(E), i = o.findIndex((x) => x.id === L.aptoId) + (a === 'apto-prox' ? 1 : -1);
        if (o[i]) abrirLeitura(o[i].id, L.tipo);
        break;
      }
      case 'editar': L.editando = !L.editando; render(); break;
      case 'confirmar': confirmar(); break;
      case 'pdf': gerarEEnviarPdf(); break;
      case 'todas-pendentes': tela.todas = true; render(); break;
      case 'copiar': {
        const { ano, mes } = contexto();
        copiar({ para: (E.predio.emails || []).join(', '), assunto: P.assunto(E.predio, ano, mes), corpo: P.corpoEmail() }[el.dataset.c]);
        break;
      }
      case 'marcar-enviado': { const k = mesK(); E.meses[k].enviadoEm = E.meses[k].enviadoEm ? null : new Date().toISOString(); salvar(); render(); break; }
      case 'cfg-voltar': C.erro = ''; C.passo = Math.max(0, C.passo - 1); render(); break;
      case 'cfg-ok': concluirConfig(); break;
      case 'gerar': {
        const ini = parseInt(C.ini, 10), fim = parseInt(C.fim, 10), por = parseInt(C.por, 10);
        if (!(ini >= 0 && fim >= ini && fim - ini < 60 && por >= 1 && por <= 30)) { C.erro = 'Confira os andares e a quantidade de aptos por andar.'; render(); break; }
        if (C.aptos.length && !C.confirmarGerar) { C.confirmarGerar = true; render(); break; }
        C.aptos = P.gerarAptos(ini, fim, por); C.confirmarGerar = false; C.erro = ''; render();
        break;
      }
      case 'ativo': { const x = C.aptos.find((y) => y.id === id); x.ativo = !x.ativo; render(); break; }
      case 'subir': case 'descer': {
        const ordem = [...C.aptos].filter((x) => x.ativo).sort((x, y) => x.ordemLeitura - y.ordemLeitura);
        const i = ordem.findIndex((x) => x.id === id), j = a === 'subir' ? i - 1 : i + 1;
        if (j < 0 || j >= ordem.length) break;
        [ordem[i], ordem[j]] = [ordem[j], ordem[i]];
        ordem.forEach((x, k) => { x.ordemLeitura = k; });
        render();
        const b = $app.querySelector(`[data-a="${a}"][data-id="${id}"]`);
        if (b && !b.disabled) b.focus();
        break;
      }
      case 'backup': salvarCopia(); break;
      default: break;
    }
  }
  $app.addEventListener('click', (ev) => {
    const el = ev.target.closest('[data-a]');
    if (!el || el.disabled) return;
    acao(el.dataset.a, el);
  });
  $app.addEventListener('input', (ev) => {
    const el = ev.target;
    if (!C) return;
    if (el.dataset.c) {
      const c = el.dataset.c;
      if (c === 'nome') C.nome = el.value;
      else if (c === 'e0') C.emails[0] = el.value;
      else if (c === 'e1') C.emails[1] = el.value;
      else C[c] = el.value.replace(/\D/g, '');
    } else if (el.dataset.apto) {
      const x = C.aptos.find((y) => y.id === Number(el.dataset.apto));
      if (x) x.numero = el.value;
    }
  });
  $app.addEventListener('change', (ev) => {
    const el = ev.target;
    if (el.dataset.arq === 'foto') { receberFoto(el.files && el.files[0]); el.value = ''; }
    if (el.dataset.arq === 'restaurar' && el.files && el.files[0]) restaurar(el.files[0]);
  });

  render();
})();
