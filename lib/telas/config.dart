import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoSwitch;

import '../conta.dart';
import '../db.dart';
import '../tema.dart';
import 'entrada.dart';
import 'mes.dart';

/// Configuração em passos curtos. `primeiraVez` false = edição a partir do mês.
class TelaConfig extends StatefulWidget {
  final bool primeiraVez;
  const TelaConfig({super.key, this.primeiraVez = false});
  @override
  State<TelaConfig> createState() => _TelaConfigState();
}

class _TelaConfigState extends State<TelaConfig> {
  int passo = 0;
  bool carregando = true;
  final nome = TextEditingController();
  final email1 = TextEditingController();
  final email2 = TextEditingController();
  final andarIni = TextEditingController(text: '1');
  final andarFim = TextEditingController(text: '6');
  final porAndar = TextEditingController(text: '4');
  bool incluirConsumo = true;
  List<Apto> aptos = [];
  String? erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final pr = await Db.i.predio();
    final u = await Db.i.usuario();
    if (u != null) email1.text = u.email; // sugestão: o próprio e-mail do síndico
    if (pr != null) {
      nome.text = pr.nome;
      final l = pr.listaEmails;
      email1.text = l.isNotEmpty ? l[0] : email1.text;
      email2.text = l.length > 1 ? l[1] : '';
      incluirConsumo = pr.incluirConsumo;
      aptos = await Db.i.aptos(soAtivos: false);
    }
    if (mounted) setState(() => carregando = false);
  }

  static const _titulos = ['Nome do prédio', 'Apartamentos', 'Ordem de leitura', 'E-mails de destino'];

  void _gerar() {
    final ini = int.tryParse(andarIni.text), fim = int.tryParse(andarFim.text), n = int.tryParse(porAndar.text);
    if (ini == null || fim == null || n == null || ini < 0 || fim < ini || n < 1 || n > 99 || fim - ini > 80) {
      setState(() => erro = 'Confira os números: andar final ≥ inicial e de 1 a 99 aptos por andar.');
      return;
    }
    final lista = <Apto>[];
    var ordem = 0;
    for (var a = ini; a <= fim; a++) {
      for (var u = 1; u <= n; u++) {
        lista.add(Apto(numero: '${a * 100 + u}', andar: a, ordemApto: ordem, ordemLeitura: ordem));
        ordem++;
      }
    }
    setState(() { aptos = lista; erro = null; });
  }

  bool _valido() {
    erro = null;
    if (passo == 0 && nome.text.trim().isEmpty) erro = 'Digite o nome do prédio.';
    if (passo == 1 && !aptos.any((a) => a.ativo)) erro = 'Gere ou adicione ao menos um apartamento.';
    if (passo == 3) {
      final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
      final a = email1.text.trim(), b = email2.text.trim();
      if (a.isEmpty) {
        erro = 'Informe o e-mail que recebe o relatório.';
      } else if (!ok.hasMatch(a)) {
        erro = 'E-mail inválido: $a';
      } else if (b.isNotEmpty && !ok.hasMatch(b)) {
        erro = 'E-mail inválido: $b';
      } else if (b.toLowerCase() == a.toLowerCase()) {
        erro = 'Os dois e-mails precisam ser diferentes.';
      }
    }
    setState(() {});
    return erro == null;
  }

  Future<void> _avancar() async {
    if (!_valido()) return;
    if (passo < 3) {
      setState(() => passo++);
      return;
    }
    // ordem de leitura = ordem atual da lista; inativos vão para o fim.
    final ativos = aptos.where((a) => a.ativo).toList();
    final inativos = aptos.where((a) => !a.ativo).toList();
    var o = 0;
    final final_ = [
      for (final a in ativos) a.copiar(ordemLeitura: o++),
      for (final a in inativos) a.copiar(ordemLeitura: 9000 + o++),
    ];
    try {
      await Db.i.salvarPredio(Predio(nome.text.trim(), [email1.text.trim(), email2.text.trim()].where((e) => e.isNotEmpty).join(', '), incluirConsumo));
      await Db.i.salvarAptos(final_);
    } catch (_) {
      if (mounted) setState(() => erro = 'Não foi possível salvar. Tente de novo.');
      return;
    }
    if (!mounted) return;
    if (widget.primeiraVez) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const TelaMes()));
    } else {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _sair() async {
    final sim = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair da conta?'),
        content: const Text('As leituras e o prédio continuam neste aparelho. Para voltar, entre de novo com e-mail e senha.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sair')),
        ],
      ),
    );
    if (sim != true) return;
    await Conta.i.sair();
    await Db.i.removerUsuario();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const TelaEntrada(temPredio: true)), (_) => false);
  }

  Future<void> _renomear(int i) async {
    final c = TextEditingController(text: aptos[i].numero);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renomear apartamento'),
        content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Salvar')),
        ],
      ),
    );
    if (r != null && r.isNotEmpty) setState(() => aptos[i] = aptos[i].copiar(numero: r));
  }

  Future<void> _adicionar() async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novo apartamento'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'Número, ex.: 705')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Adicionar')),
        ],
      ),
    );
    if (r == null || r.isEmpty) return;
    final n = int.tryParse(r);
    final andar = n == null ? (aptos.isEmpty ? 1 : aptos.last.andar) : n ~/ 100;
    final mais = aptos.length;
    setState(() => aptos.add(Apto(numero: r, andar: andar, ordemApto: mais, ordemLeitura: mais)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    if (carregando) return Scaffold(body: Center(child: CircularProgressIndicator(color: p.acao)));
    return Scaffold(
      appBar: AppBar(
        leading: passo > 0
            ? IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 20), tooltip: 'Voltar', onPressed: () => setState(() { passo--; erro = null; }))
            : (widget.primeiraVez ? null : IconButton(icon: const Icon(Icons.close), tooltip: 'Fechar', onPressed: () => Navigator.pop(context))),
        title: Text('Passo ${passo + 1} de 4', style: context.legenda),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Align(alignment: Alignment.centerLeft, child: Text(_titulos[passo], style: context.titulo)),
          ),
          Expanded(child: AnimatedSwitcher(duration: context.dur, child: KeyedSubtree(key: ValueKey(passo), child: _corpo()))),
          if (erro != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(alignment: Alignment.centerLeft, child: Text(erro!, style: context.legenda.copyWith(color: p.erro))),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: BotaoAcao(passo < 3 ? 'Continuar' : 'Concluir', onTap: _avancar),
          ),
        ]),
      ),
    );
  }

  Widget _corpo() {
    switch (passo) {
      case 0:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Aparece no assunto e no cabeçalho do relatório.', style: context.legenda),
            const SizedBox(height: 12),
            TextField(controller: nome, textCapitalization: TextCapitalization.words, style: context.corpo,
                decoration: const InputDecoration(hintText: 'Ex.: Edifício Aurora')),
            if (!widget.primeiraVez) ...[
              const SizedBox(height: 28),
              Text('Conta', style: context.legenda),
              const SizedBox(height: 4),
              Text(email1.text.isEmpty ? 'Sem conta' : email1.text, style: context.corpo),
              TextButton(
                onPressed: _sair,
                style: TextButton.styleFrom(minimumSize: const Size(44, 44), padding: EdgeInsets.zero, foregroundColor: context.p.erro),
                child: const Text('Sair da conta', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
            ],
          ]),
        );
      case 1:
        return _passoAptos();
      case 2:
        return _passoOrdem();
      default:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('O relatório em PDF vai para até dois e-mails diferentes.', style: context.legenda),
            const SizedBox(height: 12),
            Text('Primeiro e-mail', style: context.legenda),
            const SizedBox(height: 6),
            TextField(controller: email1, keyboardType: TextInputType.emailAddress, autocorrect: false, style: context.corpo,
                decoration: const InputDecoration(hintText: 'voce@exemplo.com.br')),
            const SizedBox(height: 12),
            Text('Segundo e-mail (opcional)', style: context.legenda),
            const SizedBox(height: 6),
            TextField(controller: email2, keyboardType: TextInputType.emailAddress, autocorrect: false, style: context.corpo,
                decoration: const InputDecoration(hintText: 'administradora@exemplo.com.br')),
            const SizedBox(height: 16),
          ]),
        );
    }
  }

  Widget _campo(String rotulo, TextEditingController c) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(rotulo, style: context.legenda),
          const SizedBox(height: 6),
          TextField(controller: c, keyboardType: TextInputType.number, style: context.corpo),
        ]),
      );

  Widget _passoAptos() {
    final p = context.p;
    final semLista = aptos.isEmpty;
    return ListView(padding: const EdgeInsets.only(bottom: 8), children: [
      if (semLista || widget.primeiraVez)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _campo('Andar inicial', andarIni), const SizedBox(width: 12),
              _campo('Andar final', andarFim), const SizedBox(width: 12),
              _campo('Aptos por andar', porAndar),
            ]),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _gerar,
                style: TextButton.styleFrom(minimumSize: const Size(44, 44), foregroundColor: p.acao),
                child: Text(semLista ? 'Gerar apartamentos' : 'Gerar de novo', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      for (var i = 0; i < aptos.length; i++) ...[
        Divider(color: p.fio, height: 0.5, thickness: 0.5, indent: 20),
        InkWell(
          onTap: () => _renomear(i),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
              child: Row(children: [
                Expanded(child: Text('Apto ${aptos[i].numero}', style: context.corpo.copyWith(color: aptos[i].ativo ? p.texto : p.texto2))),
                Text(aptos[i].ativo ? 'Renomear' : 'Desativado', style: context.legenda),
                const SizedBox(width: 12),
                CupertinoSwitch(value: aptos[i].ativo, activeTrackColor: p.acao, onChanged: (v) => setState(() => aptos[i] = aptos[i].copiar(ativo: v))),
              ]),
            ),
          ),
        ),
      ],
      if (!semLista) ...[
        Divider(color: p.fio, height: 0.5, thickness: 0.5, indent: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: TextButton(onPressed: _adicionar, style: TextButton.styleFrom(minimumSize: const Size(44, 48), foregroundColor: p.acao), child: const Text('Adicionar apartamento', style: TextStyle(fontSize: 17))),
          ),
        ),
      ],
    ]);
  }

  Widget _passoOrdem() {
    final p = context.p;
    final ativos = aptos.where((a) => a.ativo).toList()..sort((a, b) => a.ordemLeitura.compareTo(b.ordemLeitura));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Align(alignment: Alignment.centerLeft, child: Text('Arraste na ordem em que os medidores estão na sala.', style: context.legenda)),
      ),
      Expanded(
        child: ReorderableListView.builder(
          itemCount: ativos.length,
          buildDefaultDragHandles: false,
          onReorderItem: (a, b) {
            final item = ativos.removeAt(a);
            ativos.insert(b, item);
            setState(() {
              // reaplica a ordem na lista completa
              final inativos = aptos.where((x) => !x.ativo).toList();
              var o = 0;
              aptos = [for (final x in ativos) x.copiar(ordemLeitura: o++), ...inativos];
            });
          },
          itemBuilder: (ctx, i) => Container(
            key: ValueKey('${ativos[i].numero}-${ativos[i].id}-$i'),
            decoration: BoxDecoration(color: p.fundo, border: Border(bottom: BorderSide(color: p.fio, width: 0.5))),
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.only(left: 20),
            child: Row(children: [
              SizedBox(width: 36, child: Text('${i + 1}', style: context.legenda)),
              Expanded(child: Text('Apto ${ativos[i].numero}', style: context.corpo)),
              ReorderableDragStartListener(
                index: i,
                child: SizedBox(width: 56, height: 48, child: Icon(Icons.drag_handle, color: p.texto2)),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}
