import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../db.dart';
import '../formato.dart';
import '../relatorio.dart';
import '../tema.dart';
import 'camera.dart';
import 'config.dart';

/// Revisão e envio: pendentes no topo, prévia do PDF e botão Enviar.
class TelaRevisao extends StatefulWidget {
  const TelaRevisao({super.key});
  @override
  State<TelaRevisao> createState() => _TelaRevisaoState();
}

class _TelaRevisaoState extends State<TelaRevisao> {
  Predio? predio;
  Mes? mes;
  List<Apto> aptos = [];
  Leituras leituras = {};
  Map<String, List<int>> anteriores = {};
  List<LinhaRel> linhas = [];
  List<Uint8List> paginas = [];
  bool carregando = true;
  bool enviando = false;
  String? erro;
  int _geracao = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
    Db.i.versao.addListener(_carregar);
  }

  @override
  void dispose() {
    Db.i.versao.removeListener(_carregar);
    super.dispose();
  }

  Future<void> _carregar() async {
    final g = ++_geracao;
    try {
      final pr = await Db.i.predio();
      final m = await Db.i.mesAtual();
      final a = await Db.i.aptos();
      final l = await Db.i.leituras(m.id);
      final h = await Db.i.historicoAnterior(m, a);
      final ln = montarLinhas(a, l, h);
      final pdf = await gerarPdf(pr!, m, ln);
      final pgs = <Uint8List>[];
      await for (final pg in Printing.raster(pdf, dpi: 120)) {
        pgs.add(await pg.toPng());
      }
      if (!mounted || g != _geracao) return;
      setState(() {
        predio = pr; mes = m; aptos = a; leituras = l; anteriores = h;
        linhas = ln; paginas = pgs; carregando = false; erro = null;
      });
    } catch (e) {
      if (!mounted || g != _geracao) return;
      setState(() { carregando = false; erro = 'Não foi possível montar o relatório. Tente de novo.'; });
    }
  }

  List<Pendencia> get _pend => pendencias(aptos, leituras);

  Future<void> _lerPendente(Pendencia pe) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) {
        // câmera na ordem física, abrindo no apto pendente
        return TelaCamera(
          mes: mes!, aptos: aptos, indice: aptos.indexWhere((a) => a.id == pe.apto.id),
          tipo: pe.tipo, leituras: leituras, anteriores: anteriores,
        );
      },
    ));
  }

  Future<bool> _confirmarPendentes() async {
    final n = _pend.length;
    if (n == 0) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Faltam leituras'),
        content: Text('$n medidor${n == 1 ? '' : 'es'} sem leitura. Eles aparecem como "—" no relatório. Enviar mesmo assim?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar mesmo assim')),
        ],
      ),
    );
    return r ?? false;
  }

  Future<void> _enviar() async {
    if (enviando || predio == null || mes == null) return;
    final msg = ScaffoldMessenger.of(context);
    if (!await _confirmarPendentes()) return;
    if (!mounted) return;
    setState(() => enviando = true);
    final pr = predio!, m = mes!;
    try {
      final dir = await getTemporaryDirectory();
      final base = 'leituras-${m.ano}-${m.mes.toString().padLeft(2, '0')}';
      final pdf = File(p.join(dir.path, '$base.pdf'))..writeAsBytesSync(await gerarPdf(pr, m, linhas));
      final assuntoTxt = assunto(pr, m);
      final corpo = corpoEmail();
      var enviado = false;
      try {
        final r = await FlutterEmailSender.send(Email(
          recipients: pr.listaEmails, subject: assuntoTxt, body: corpo,
          attachmentPaths: [pdf.path],
        ));
        enviado = r != EmailSendResult.cancelled && r != EmailSendResult.saved;
      } on FlutterEmailSenderException {
        // sem app de e-mail configurado: plano B, folha de compartilhamento
        final r = await SharePlus.instance.share(ShareParams(
          files: [XFile(pdf.path)], subject: assuntoTxt, text: corpo,
        ));
        enviado = r.status == ShareResultStatus.success;
      }
      if (enviado) {
        await Db.i.marcarEnviado(m.id);
        final novo = await Db.i.mesAtual();
        if (mounted) setState(() => mes = novo);
        msg.showSnackBar(const SnackBar(content: Text('Relatório enviado')));
      }
    } catch (e) {
      msg.showSnackBar(const SnackBar(content: Text('Não consegui enviar. Verifique o app de e-mail e tente de novo.')));
    } finally {
      if (mounted) setState(() => enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    if (carregando) return Scaffold(appBar: AppBar(), body: Center(child: CircularProgressIndicator(color: p.acao)));
    if (erro != null || predio == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(erro ?? 'Configure o prédio antes de enviar.', textAlign: TextAlign.center, style: context.corpo),
              const SizedBox(height: 16),
              BotaoAcao('Tentar de novo', onTap: () { setState(() => carregando = true); _carregar(); }),
            ]),
          ),
        ),
      );
    }
    final pend = _pend;
    final m = mes!;
    final emails = predio!.listaEmails;
    final enviado = m.enviadoEm;
    return Scaffold(
      appBar: AppBar(),
      body: Column(children: [
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Revisar e enviar', style: context.titulo),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tituloMes(m.ano, m.mes), style: context.corpo.copyWith(color: p.texto2)),
                const SizedBox(height: 2),
                if (emails.isEmpty)
                  GestureDetector(
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TelaConfig()));
                      _carregar();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('Nenhum e-mail de destino. Toque para adicionar.', style: context.legenda.copyWith(color: p.aviso)),
                    ),
                  )
                else
                  Text('Para: ${emails.join(', ')}', style: context.legenda),
                if (enviado != null)
                  Text('Enviado em ${enviado.day.toString().padLeft(2, '0')}/${enviado.month.toString().padLeft(2, '0')} às ${enviado.hour.toString().padLeft(2, '0')}:${enviado.minute.toString().padLeft(2, '0')}',
                      style: context.legenda.copyWith(color: p.ok)),
              ]),
            ),
            if (pend.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                child: Text('Pendentes · ${pend.length}', style: context.legenda.copyWith(fontWeight: FontWeight.w600, color: p.aviso)),
              ),
              Divider(color: p.fio, height: 0.5, thickness: 0.5),
              for (final pe in pend) ...[
                InkWell(
                  onTap: () => _lerPendente(pe),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(children: [
                        Expanded(child: Text(pe.texto, style: context.corpo)),
                        Text('Ler', style: context.corpo.copyWith(color: p.acao, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ),
                Divider(color: p.fio, height: 0.5, thickness: 0.5, indent: 20),
              ],
              const SizedBox(height: 12),
            ] else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text('Todos os ${aptos.length * 2} medidores lidos.', style: context.corpo.copyWith(color: p.ok)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text('Prévia do PDF', style: context.legenda.copyWith(fontWeight: FontWeight.w600)),
            ),
            Container(
              color: p.fundo2,
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                for (final pg in paginas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: p.fio, width: 0.5)),
                      child: Image.memory(pg, fit: BoxFit.fitWidth, width: double.infinity, semanticLabel: 'Página do relatório'),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 16),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: BotaoAcao(
              enviando ? 'Preparando…' : enviado != null ? 'Enviar de novo' : (pend.isEmpty ? 'Enviar por e-mail' : 'Enviar com ${pend.length} pendente${pend.length == 1 ? '' : 's'}'),
              onTap: enviando ? null : _enviar,
            ),
          ),
        ),
      ]),
    );
  }
}
