import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'db.dart';
import 'formato.dart';

/// Uma linha do relatório (um apartamento).
class LinhaRel {
  final String numero;
  final String? agua, gas; // leitura como guardada ("2689,58")
  final int? aguaCons, gasCons; // m³ inteiros
  const LinhaRel(this.numero, this.agua, this.aguaCons, this.gas, this.gasCons);
}

class Pendencia {
  final Apto apto;
  final String tipo;
  const Pendencia(this.apto, this.tipo);
  String get texto => 'Apto ${apto.numero} · ${tipo == 'agua' ? 'Água' : 'Gás'}';
}

List<LinhaRel> montarLinhas(List<Apto> aptos, Leituras lei, Map<String, List<int>> ant) {
  final ordenados = [...aptos]..sort((a, b) => a.ordemApto.compareTo(b.ordemApto));
  return [
    for (final a in ordenados)
      () {
        String? v(String t) => lei[chave(a.id!, t)]?.valor;
        int? cons(String t) {
          final x = lei[chave(a.id!, t)]?.numero, p = ant[chave(a.id!, t)];
          return (x != null && p != null && p.isNotEmpty) ? x - p.first : null;
        }
        return LinhaRel(a.numero, v('agua'), cons('agua'), v('gas'), cons('gas'));
      }(),
  ];
}

List<Pendencia> pendencias(List<Apto> aptos, Leituras lei) => [
      for (final a in aptos)
        for (final t in const ['agua', 'gas'])
          if (!lei.containsKey(chave(a.id!, t))) Pendencia(a, t),
    ];

// Fontes padrão do PDF (só Latin-1): sem espaço fino, "−" nem "—"; usar nbsp e "-".
String _n(String? v) => v == null ? '-' : fmtNum(v).replaceAll(espacoFino, ' ');


String assunto(Predio p, Mes m) => 'Leituras de água e gás – ${assuntoMes(m.ano, m.mes)} – ${p.nome}';

String _data(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

Future<Uint8List> gerarPdf(Predio predio, Mes mes, List<LinhaRel> linhas) async {
  final doc = pw.Document(title: assunto(predio, mes), author: predio.nome, creator: 'Prumo');
  // paleta do app (lib/tema.dart), no papel
  const tinta = PdfColor.fromInt(0xFF111111);
  const cinza = PdfColor.fromInt(0xFF6E6E73);
  const fio = PdfColor.fromInt(0xFFD9D9D5);
  const listra = PdfColor.fromInt(0xFFF6F6F4);
  const acao = PdfColor.fromInt(0xFF1F4647);
  const agua = PdfColor.fromInt(0xFF2B7BD6);
  const gas = PdfColor.fromInt(0xFFDD6B2B);

  final total = linhas.length * 2;
  final lidos = linhas.fold<int>(0, (s, l) => s + (l.agua != null ? 1 : 0) + (l.gas != null ? 1 : 0));
  final faltam = total - lidos;

  pw.Widget cel(String t, {bool dir = true, bool negrito = false, PdfColor cor = tinta, double tam = 11}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: pw.Text(t,
            textAlign: dir ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(fontSize: tam, fontWeight: negrito ? pw.FontWeight.bold : pw.FontWeight.normal, color: cor)),
      );

  pw.Widget titulo(String t, PdfColor marca) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
          pw.Container(width: 6, height: 6, decoration: pw.BoxDecoration(color: marca, shape: pw.BoxShape.circle)),
          pw.SizedBox(width: 5),
          pw.Text(t, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: cinza)),
        ]),
      );

  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: tinta, width: 0.8))),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 8),
          child: pw.Text('APTO', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: cinza)),
        ),
        titulo('ÁGUA', agua),
        titulo('GÁS', gas),
      ],
    ),
    for (var i = 0; i < linhas.length; i++)
      pw.TableRow(
        decoration: pw.BoxDecoration(
          color: i.isOdd ? listra : null,
          border: const pw.Border(bottom: pw.BorderSide(color: fio, width: 0.4)),
        ),
        children: [
          cel(linhas[i].numero, dir: false, negrito: true),
          cel(_n(linhas[i].agua), cor: linhas[i].agua == null ? cinza : tinta),
          cel(_n(linhas[i].gas), cor: linhas[i].gas == null ? cinza : tinta),
        ],
      ),
  ];

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(56, 52, 56, 48),
    header: (c) => c.pageNumber == 1
        ? pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('LEITURA DE ÁGUA E GÁS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: acao, letterSpacing: 1.2)),
            pw.SizedBox(height: 6),
            pw.Text(predio.nome, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: tinta)),
            pw.SizedBox(height: 4),
            pw.Text(tituloMes(mes.ano, mes.mes), style: const pw.TextStyle(fontSize: 14, color: tinta)),
            pw.SizedBox(height: 14),
            pw.Container(height: 1.2, color: acao),
            pw.SizedBox(height: 8),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('${linhas.length} apartamentos  ·  $lidos de $total medidores lidos', style: const pw.TextStyle(fontSize: 9, color: cinza)),
              pw.Text('Emitido em ${_data(DateTime.now())}', style: const pw.TextStyle(fontSize: 9, color: cinza)),
            ]),
            pw.SizedBox(height: 18),
          ])
        : pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 12),
            child: pw.Text('${predio.nome}  ·  ${tituloMes(mes.ano, mes.mes)}', style: const pw.TextStyle(fontSize: 9, color: cinza)),
          ),
    footer: (c) => pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: fio, width: 0.4))),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Responsável: $assinaturaEmail', style: const pw.TextStyle(fontSize: 8, color: cinza)),
        pw.Text('Página ${c.pageNumber} de ${c.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: cinza)),
      ]),
    ),
    build: (_) => [
      pw.Table(
        columnWidths: const {
          0: pw.FlexColumnWidth(1),
          1: pw.FlexColumnWidth(1.4),
          2: pw.FlexColumnWidth(1.4),
        },
        children: rows,
      ),
      if (faltam > 0)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12),
          child: pw.Text('"-" = medidor sem leitura neste mês ($faltam).', style: const pw.TextStyle(fontSize: 8.5, color: cinza)),
        ),
    ],
  ));
  return doc.save();
}

/// Corpo do e-mail: só o aviso do anexo e a assinatura (sem tabela de consumos).
const assinaturaEmail = 'Alex Freitas';

String corpoEmail() => 'Segue em anexo a leitura.\n\nAtenciosamente,\n$assinaturaEmail\n';
