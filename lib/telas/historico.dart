import 'package:flutter/material.dart';

import '../db.dart';
import '../formato.dart';
import '../tema.dart';

class TelaHistorico extends StatefulWidget {
  const TelaHistorico({super.key});
  @override
  State<TelaHistorico> createState() => _TelaHistoricoState();
}

class _TelaHistoricoState extends State<TelaHistorico> {
  List<ResumoMes>? itens;

  @override
  void initState() {
    super.initState();
    Db.i.resumos().then((r) => mounted ? setState(() => itens = r) : null).catchError((_) {
      if (mounted) setState(() => itens = []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final lista = itens;
    return Scaffold(
      appBar: AppBar(),
      body: lista == null
          ? Center(child: CircularProgressIndicator(color: p.acao))
          : ListView(padding: EdgeInsets.zero, children: [
              Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), child: Text('Histórico', style: context.titulo)),
              if (lista.isEmpty)
                Padding(padding: const EdgeInsets.all(20), child: Text('Nenhum mês registrado ainda.', style: context.corpo.copyWith(color: p.texto2))),
              for (final r in lista) ...[
                Divider(color: p.fio, height: 0.5, thickness: 0.5, indent: 20),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tituloMes(r.mes.ano, r.mes.mes), style: context.corpo),
                        const SizedBox(height: 2),
                        Text('${r.lidas} de ${r.total} lidos${r.mes.enviadoEm != null ? ' · enviado' : ''}', style: context.legenda),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('Água  ${fmtConsumo(r.agua)}', style: context.corpo.copyWith(color: p.agua)),
                      const SizedBox(height: 2),
                      Text('Gás  ${fmtConsumo(r.gas)}', style: context.corpo.copyWith(color: p.gas)),
                    ]),
                  ]),
                ),
              ],
              if (lista.isNotEmpty) Divider(color: p.fio, height: 0.5, thickness: 0.5, indent: 20),
            ]),
    );
  }
}
