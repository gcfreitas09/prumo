// Gate W3: a lógica do webapp bate com o app (lib/formato.dart, analise.dart, relatorio.dart).
import path from 'path';
import { fileURLToPath } from 'url';
import { createRequire } from 'module';
const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
await import(path.join(raiz, 'web_app/logica.js'));
const P = globalThis.Prumo;
const req = createRequire(process.env.HOME + '/.claude/tools/qa/');
let falhas = 0;
const eq = (a, b, m) => { if (JSON.stringify(a) !== JSON.stringify(b)) { falhas++; console.log('✗', m, '→', JSON.stringify(a), '≠', JSON.stringify(b)); } };
const f = P.ESPACO_FINO;
eq(P.fmtNum(1316967), `1${f}316${f}967`, 'fmtNum');
eq(P.fmtNum('45'), '45', 'fmtNum curto');
eq(P.fmtConsumo(1247), `+${f}1${f}247${f}m³`, 'fmtConsumo');
eq(P.tituloMes(2026, 10), 'Outubro de 2026', 'tituloMes');
eq(P.analisar(90, [100, 80, 60, 40]).situacao, 'negativo', 'analisar negativo');
eq(P.analisar(130, [100, 80, 60, 40]).situacao, 'naMedia', 'analisar média');
eq(P.analisar(200, [100, 80, 60, 40]).situacao, 'acima', 'analisar acima');
eq(P.analisar(10, []).situacao, 'primeira', 'analisar primeira');
eq(P.plausivel(131967, [1316967, 1316800]), false, 'plausível dígito perdido');
eq(P.plausivel(1317000, [1316967, 1316800]), true, 'plausível ok');
eq(P.plausivel(1999999, [1316967, 1316800]), false, 'plausível salto');
eq(P.digitosDaLinha('O1461S', 6), '014615', 'troca de letras');
eq(P.digitosDaLinha('12x', 3), null, 'letra estranha');
eq(P.consensoPosicional(['0763', '07?3', '0763'], 4), '0763', 'consenso');
eq(P.consensoPosicional(['0763', '0863'], 4), null, 'sem consenso');
// estado, meses e relatório
const e = P.estadoVazio();
e.predio = { nome: 'Aurora', emails: ['a@b.com'] };
e.aptos = P.gerarAptos(1, 2, 2);
eq(e.aptos.map((a) => a.numero), ['101', '102', '201', '202'], 'gerador');
const out = P.mesAtual(e, new Date(2026, 9, 5)), nov = P.mesAtual(e, new Date(2026, 10, 3));
eq([out, nov], ['2026-10', '2026-11'], 'chaves de mês');
e.leituras[P.chaveLeitura(out, 1, 'agua')] = { valor: '1250' };
e.leituras[P.chaveLeitura(nov, 1, 'agua')] = { valor: '1500' };
eq(P.anteriores(e, 1, 'agua', nov), [1250], 'anteriores');
const lei = P.leiturasDoMes(e, nov);
const linhas = P.montarLinhas(e.aptos, lei, P.historicoAnterior(e, nov));
eq(linhas[0].aguaCons, 250, 'consumo na linha');
eq(P.pendencias(e.aptos, lei).length, 7, 'pendências');
eq(P.assunto(e.predio, 2026, 10), 'Leituras de água e gás – Outubro/2026 – Aurora', 'assunto');
eq(P.corpoEmail(), 'Segue em anexo a leitura.\n\nAtenciosamente,\nAlex Freitas\n', 'corpo do e-mail');
eq(P.corpoEmail().includes('m³'), false, 'sem consumo no e-mail');
eq(P.resumos(e)[0].agua, 250, 'histórico');
// PDF de verdade (jsPDF do mesmo pacote que a página carrega)
let jsPDF;
try { jsPDF = req('jspdf').jsPDF; } catch (_) { jsPDF = null; }
if (!jsPDF) { falhas++; console.log('✗ jspdf ausente em ~/.claude/tools/qa'); } else {
  const many = { ...e, aptos: P.gerarAptos(1, 12, 4) };
  const doc = P.gerarPdf(jsPDF, e.predio, 2026, 11, P.montarLinhas(many.aptos, {}, {}));
  const txt = doc.output();
  eq(txt.startsWith('%PDF'), true, 'PDF');
  eq(doc.getNumberOfPages() >= 2, true, '48 aptos em 2+ páginas');
  eq(/Respons.vel: Alex Freitas/.test(txt), true, 'rodapé com responsável');
  eq(/consumo|m³|CONSUMO/.test(txt), false, 'PDF sem consumo');
}
console.log(falhas ? `LOGICA WEB FALHOU (${falhas})` : 'LOGICA WEB OK');
process.exit(falhas ? 1 : 0);
