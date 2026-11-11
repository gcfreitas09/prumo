import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analise.dart';
import '../db.dart';
import '../formato.dart';
import '../tema.dart';

class ResultadoFolha {
  final String valor;
  final bool editado;
  const ResultadoFolha(this.valor, this.editado);
}

/// Bottom sheet de conferência: leitura em 44 pt, mês anterior, consumo, aviso.
class FolhaLeitura extends StatefulWidget {
  final Apto apto;
  final String tipo;
  final String valor;
  final List<int> anteriores;
  final bool iniciarEditando;
  const FolhaLeitura({super.key, required this.apto, required this.tipo, required this.valor, required this.anteriores, this.iniciarEditando = false});
  @override
  State<FolhaLeitura> createState() => _FolhaLeituraState();
}

class _FolhaLeituraState extends State<FolhaLeitura> {
  late final c = TextEditingController(text: widget.valor);
  late bool editando = widget.iniciarEditando;
  bool editou = false;
  bool toqueExtra = false;

  Analise get analise => analisar(parteInteira(c.text), widget.anteriores);

  void _confirmar() {
    if (analise.pedeConfirmacao && !toqueExtra) {
      setState(() => toqueExtra = true);
      return;
    }
    Navigator.pop(context, ResultadoFolha(c.text, editou));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final a = analise;
    final nome = widget.tipo == 'agua' ? 'Água' : 'Gás';
    final cor = a.situacao == Situacao.negativo ? p.erro : a.situacao == Situacao.acima ? p.aviso : p.ok;
    final vazio = c.text.isEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Apto ${widget.apto.numero} · $nome', style: context.legenda),
          const SizedBox(height: 4),
          editando
              ? TextField(
                  controller: c,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                  style: context.leitura.copyWith(color: p.doTipo(widget.tipo)),
                  onChanged: (_) => setState(() { editou = true; toqueExtra = false; }),
                  decoration: const InputDecoration(hintText: '0'),
                )
              : Text(vazio ? '—' : fmtNum(c.text), style: context.leitura.copyWith(color: p.doTipo(widget.tipo))),
          const SizedBox(height: 12),
          _linha('Mês anterior', widget.anteriores.isEmpty ? '—' : fmtNum(widget.anteriores.first)),
          _linha('Consumo', a.consumo == null ? '—' : fmtConsumo(a.consumo!)),
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 14),
            child: Text(
              toqueExtra ? '${a.texto}. Toque de novo para confirmar mesmo assim.' : (vazio ? ' ' : a.texto),
              style: context.legenda.copyWith(color: cor),
            ),
          ),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: TextButton(
                  onPressed: editando ? null : () => setState(() => editando = true),
                  style: TextButton.styleFrom(
                    backgroundColor: p.fundo2, foregroundColor: p.texto,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Editar', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: editando ? p.texto2 : p.texto)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: BotaoAcao(toqueExtra ? 'Confirmar mesmo assim' : 'Confirmar', onTap: vazio ? null : _confirmar)),
          ]),
        ]),
      ),
    );
  }

  Widget _linha(String r, String v) => Container(
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.p.fio, width: 0.5))),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(r, style: context.corpo),
          Text(v, style: context.corpo.copyWith(color: context.p.texto2)),
        ]),
      );
}
