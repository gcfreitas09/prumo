import 'package:flutter/cupertino.dart' show CupertinoSlidingSegmentedControl;
import 'package:flutter/material.dart';

import '../db.dart';
import '../formato.dart';
import '../tema.dart';
import 'config.dart';
import 'historico.dart';
import 'revisao.dart';
import 'camera.dart';

class TelaMes extends StatefulWidget {
  const TelaMes({super.key});
  @override
  State<TelaMes> createState() => _TelaMesState();
}

class _TelaMesState extends State<TelaMes> {
  Mes? mes;
  List<Apto> aptos = [];
  Leituras leituras = {};
  Map<String, List<int>> anteriores = {};
  String tipo = 'agua';
  bool pronto = false;
  bool erro = false;

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
    try {
      final m = await Db.i.mesAtual();
      final a = await Db.i.aptos();
      final l = await Db.i.leituras(m.id);
      final h = await Db.i.historicoAnterior(m, a);
      if (!mounted) return;
      setState(() { mes = m; aptos = a; leituras = l; anteriores = h; pronto = true; erro = false; });
    } catch (_) {
      if (mounted) setState(() { pronto = true; erro = true; });
    }
  }

  bool _lido(Apto a, String t) => leituras.containsKey(chave(a.id!, t));
  int _qtd(String t) => aptos.where((a) => _lido(a, t)).length;

  Apto? get _proximo {
    for (final a in aptos) {
      if (!_lido(a, tipo)) return a;
    }
    return null;
  }

  Future<void> _ler(Apto a) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TelaCamera(
        mes: mes!, aptos: aptos, indice: aptos.indexOf(a), tipo: tipo,
        leituras: leituras, anteriores: anteriores,
      ),
    ));
    _carregar();
  }

  Future<void> _abrir(Widget tela) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => tela));
    _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    if (!pronto) return Scaffold(body: Center(child: CircularProgressIndicator(color: p.acao)));
    if (erro || mes == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Não foi possível abrir os dados do mês.', textAlign: TextAlign.center, style: context.corpo),
              const SizedBox(height: 16),
              BotaoAcao('Tentar de novo', onTap: () { setState(() => pronto = false); _carregar(); }),
            ]),
          ),
        ),
      );
    }
    final m = mes!;
    final total = aptos.length * 2;
    final lidos = _qtd('agua') + _qtd('gas');
    final porAndar = <int, List<Apto>>{};
    for (final a in aptos) {
      (porAndar[a.andar] ??= []).add(a);
    }
    final andares = porAndar.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final l in porAndar.values) {
      l.sort((a, b) => a.ordemApto.compareTo(b.ordemApto));
    }
    final prox = _proximo;

    return Scaffold(
      appBar: AppBar(
        actions: [
          _icone(Icons.history, 'Histórico', () => _abrir(const TelaHistorico())),
          _icone(Icons.tune, 'Prédio e apartamentos', () => _abrir(const TelaConfig())),
          _icone(Icons.ios_share, 'Revisar e enviar', () => _abrir(const TelaRevisao())),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tituloMes(m.ano, m.mes), style: context.titulo),
                const SizedBox(height: 4),
                Text(total == 0 ? 'Nenhum apartamento ativo' : '$lidos de $total medidores lidos', style: context.corpo.copyWith(color: p.texto2)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<String>(
                    groupValue: tipo,
                    thumbColor: p.fundo,
                    backgroundColor: p.fundo2,
                    onValueChanged: (v) => setState(() => tipo = v ?? tipo),
                    children: {
                      'agua': _seg('Água', _qtd('agua'), aptos.length, tipo == 'agua'),
                      'gas': _seg('Gás', _qtd('gas'), aptos.length, tipo == 'gas'),
                    },
                  ),
                ),
                const SizedBox(height: 20),
                _mapa(andares, porAndar),
                const SizedBox(height: 12),
              ]),
            ),
            if (aptos.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Text('Nenhum apartamento ativo. Toque no botão abaixo para configurar o prédio e gerar os apartamentos.',
                    style: context.corpo.copyWith(color: p.texto2)),
              ),
            for (final andar in andares) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                child: Text('Andar $andar', style: context.legenda.copyWith(fontWeight: FontWeight.w600)),
              ),
              Divider(color: p.fio, height: 0.5, thickness: 0.5),
              for (final a in porAndar[andar]!) ...[
                _linha(a),
                Divider(color: p.fio, height: 0.5, thickness: 0.5, indent: 20),
              ],
            ],
            const SizedBox(height: 24),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: prox != null
                ? BotaoAcao('Ler ${prox.numero}', onTap: () => _ler(prox))
                : BotaoAcao(total == 0 ? 'Configurar prédio' : 'Todos lidos · Revisar e enviar',
                    onTap: () => _abrir(total == 0 ? const TelaConfig() : const TelaRevisao())),
          ),
        ),
      ]),
    );
  }

  Widget _icone(IconData i, String dica, VoidCallback f) => IconButton(
        icon: Icon(i), tooltip: dica, onPressed: f,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      );

  Widget _seg(String nome, int n, int total, bool ativo) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text('$nome  $n/$total',
            style: context.corpo.copyWith(fontSize: 15, fontWeight: ativo ? FontWeight.w600 : FontWeight.w400)),
      );

  Widget _mapa(List<int> andares, Map<int, List<Apto>> porAndar) {
    final p = context.p;
    final cor = p.doTipo(tipo);
    return Semantics(
      label: 'Mapa do prédio, ${_qtd(tipo)} de ${aptos.length} medidores lidos',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final andar in andares)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              SizedBox(width: 28, child: Text('$andar', style: context.legenda.copyWith(fontSize: 11))),
              for (final a in porAndar[andar]!)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: AnimatedContainer(
                    duration: context.dur,
                    width: 13, height: 13,
                    decoration: BoxDecoration(color: _lido(a, tipo) ? cor : p.vazio, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }

  Widget _linha(Apto a) {
    final p = context.p;
    final l = leituras[chave(a.id!, tipo)];
    final ant = anteriores[chave(a.id!, tipo)] ?? const [];
    final v = l?.numero;
    final consumo = (v != null && ant.isNotEmpty) ? v - ant.first : null;
    return InkWell(
      onTap: () => _ler(a),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
          child: Row(children: [
            Expanded(child: Text('Apto ${a.numero}', style: context.corpo)),
            if (l == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: Text('Ler', style: context.corpo.copyWith(color: p.acao, fontWeight: FontWeight.w600)),
              )
            else
              Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                Text(fmtNum(l.valor), style: context.corpo),
                if (consumo != null)
                  Text(fmtConsumo(consumo), style: context.legenda.copyWith(color: consumo < 0 ? p.erro : p.texto2)),
              ]),
          ]),
        ),
      ),
    );
  }
}
