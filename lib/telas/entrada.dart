import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../conta.dart';
import '../db.dart';
import '../tema.dart';
import 'config.dart';
import 'mes.dart';

enum Modo { entrar, criar, verificar, recuperar }

/// Entrada do síndico. A marca é o fio de prumo: o peso de latão balança, se
/// acomoda na vertical e para sobre a marca no chão. Só depois o formulário
/// aparece. Com Firebase configurado: e-mail e senha, e-mail de verificação e
/// recuperação de senha. Sem configuração: entrada local (nome + e-mail).
class TelaEntrada extends StatefulWidget {
  final bool temPredio;
  final Modo modoInicial;
  const TelaEntrada({super.key, required this.temPredio, this.modoInicial = Modo.entrar});
  @override
  State<TelaEntrada> createState() => _TelaEntradaState();
}

class _TelaEntradaState extends State<TelaEntrada> with SingleTickerProviderStateMixin {
  static const _duracao = Duration(milliseconds: 3000);
  late final AnimationController _c = AnimationController(vsync: this, duration: _duracao);
  final nome = TextEditingController();
  final email = TextEditingController();
  final senha = TextEditingController();
  late Modo modo = widget.modoInicial;
  String? erroNome, erroEmail, erroSenha, erroGeral, aviso;
  bool ocupado = false, verSenha = false, _iniciou = false;
  int espera = 0; // segundos até poder reenviar o e-mail
  Timer? _relogio;

  bool get _local => !Conta.i.configurada;

  @override
  void initState() {
    super.initState();
    final u = Conta.i.atual;
    if (u != null) email.text = u.email;
    if (modo == Modo.verificar) _esperar(0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciou) return;
    _iniciou = true;
    if (context.semAnimacao) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _relogio?.cancel();
    _c.dispose();
    nome.dispose();
    email.dispose();
    senha.dispose();
    super.dispose();
  }

  void _trocar(Modo m) => setState(() {
        modo = m;
        erroNome = erroEmail = erroSenha = erroGeral = aviso = null;
      });

  void _esperar(int segundos) {
    _relogio?.cancel();
    setState(() => espera = segundos);
    if (segundos <= 0) return;
    _relogio = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => espera = math.max(0, espera - 1));
      if (espera == 0) t.cancel();
    });
  }

  /// Roda [f] com o botão ocupado; erro de conta vira mensagem na tela.
  Future<bool> _rodar(Future<void> Function() f) async {
    setState(() { ocupado = true; erroGeral = null; aviso = null; });
    try {
      await f();
      return true;
    } on ContaErro catch (e) {
      if (mounted) setState(() => erroGeral = e.mensagem);
      return false;
    } catch (_) {
      if (mounted) setState(() => erroGeral = 'Não foi possível concluir. Tente de novo.');
      return false;
    } finally {
      if (mounted) setState(() => ocupado = false);
    }
  }

  Future<void> _concluir(String nomeUsuario, String emailUsuario) async {
    await Db.i.salvarUsuario(Usuario(nomeUsuario, emailUsuario));
    if (!mounted) return;
    final destino = widget.temPredio ? const TelaMes() : const TelaConfig(primeiraVez: true);
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: context.semAnimacao ? Duration.zero : const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => destino,
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  Future<void> _enviar() async {
    FocusScope.of(context).unfocus();
    switch (modo) {
      case Modo.entrar:
        if (_local) return _entrarLocal();
        setState(() {
          erroEmail = validarEmail(email.text);
          erroSenha = validarSenhaEntrada(senha.text);
        });
        if (erroEmail != null || erroSenha != null) return;
        if (!await _rodar(() => Conta.i.entrar(email.text, senha.text))) return;
        final u = Conta.i.atual;
        if (u == null) return;
        if (!u.verificado) {
          _trocar(Modo.verificar);
          return;
        }
        await _concluir(u.nome.isEmpty ? u.email.split('@').first : u.nome, u.email);
      case Modo.criar:
        setState(() {
          erroNome = validarNome(nome.text);
          erroEmail = validarEmail(email.text);
          erroSenha = validarSenhaNova(senha.text);
        });
        if (erroNome != null || erroEmail != null || erroSenha != null) return;
        if (!await _rodar(() => Conta.i.criar(nome.text, email.text, senha.text))) return;
        _trocar(Modo.verificar);
        _esperar(30);
      case Modo.verificar:
        var ok = false;
        if (!await _rodar(() async => ok = await Conta.i.recarregarVerificado())) return;
        if (!ok) {
          setState(() => erroGeral = 'Ainda não confirmado. Abra o link que enviamos para ${email.text.trim()} e toque de novo.');
          return;
        }
        final u = Conta.i.atual!;
        await _concluir(u.nome.isEmpty ? u.email.split('@').first : u.nome, u.email);
      case Modo.recuperar:
        setState(() => erroEmail = validarEmail(email.text));
        if (erroEmail != null) return;
        if (await _rodar(() => Conta.i.recuperarSenha(email.text))) {
          setState(() => aviso = 'Se existir uma conta com ${email.text.trim()}, enviamos um link para criar uma nova senha.');
        }
    }
  }

  Future<void> _entrarLocal() async {
    setState(() {
      erroNome = validarNome(nome.text);
      erroEmail = validarEmail(email.text);
    });
    if (erroNome != null || erroEmail != null) return;
    if (!await _rodar(() => Db.i.salvarUsuario(Usuario(nome.text.trim(), email.text.trim())))) return;
    await _concluir(nome.text.trim(), email.text.trim());
  }

  Future<void> _reenviar() async {
    if (!await _rodar(Conta.i.reenviarVerificacao)) return;
    _esperar(30);
    setState(() => aviso = 'Enviamos o e-mail de novo.');
  }

  Future<void> _outraConta() async {
    await Conta.i.sair();
    senha.clear();
    _trocar(Modo.entrar);
  }

  String get _titulo => switch (modo) {
        Modo.entrar => 'Prumo',
        Modo.criar => 'Criar conta',
        Modo.verificar => 'Confirme seu e-mail',
        Modo.recuperar => 'Nova senha',
      };

  String get _subtitulo => switch (modo) {
        Modo.entrar => _local ? 'Leitura de água e gás do prédio, no prumo.' : 'Entre para ler os medidores do seu prédio.',
        Modo.criar => 'Uma conta por síndico. Leva menos de um minuto.',
        Modo.verificar => 'Enviamos um link para ${email.text.trim()}. Abra o e-mail, toque no link e volte aqui.',
        Modo.recuperar => 'Digite o e-mail da conta. Enviamos um link para você criar outra senha.',
      };

  String get _botao => ocupado
      ? 'Aguarde…'
      : switch (modo) {
          Modo.entrar => _local ? 'Começar' : 'Entrar',
          Modo.criar => 'Criar conta',
          Modo.verificar => 'Já confirmei',
          Modo.recuperar => 'Enviar link',
        };

  Widget _campo(TextEditingController c, String dica, {String? erro, bool senhaCampo = false, TextInputType? tipo, TextInputAction? acao, List<String>? dicas, Key? key}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          key: key,
          controller: c,
          obscureText: senhaCampo && !verSenha,
          keyboardType: tipo,
          autocorrect: false,
          enableSuggestions: !senhaCampo,
          textInputAction: acao ?? TextInputAction.next,
          autofillHints: dicas,
          onSubmitted: acao == TextInputAction.done ? (_) => _enviar() : null,
          textCapitalization: tipo == null && !senhaCampo ? TextCapitalization.words : TextCapitalization.none,
          style: context.corpo,
          decoration: InputDecoration(
            hintText: dica,
            errorText: erro,
            errorStyle: context.legenda.copyWith(color: context.p.erro),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.p.erro, width: 1)),
            focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.p.erro, width: 1)),
            suffixIcon: senhaCampo
                ? IconButton(
                    tooltip: verSenha ? 'Ocultar senha' : 'Mostrar senha',
                    icon: Icon(verSenha ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: context.p.texto2),
                    onPressed: () => setState(() => verSenha = !verSenha),
                  )
                : null,
          ),
        ),
      );

  Widget _link(String texto, VoidCallback f) => TextButton(
        onPressed: ocupado ? null : f,
        style: TextButton.styleFrom(minimumSize: const Size(44, 44), padding: const EdgeInsets.symmetric(horizontal: 4), foregroundColor: context.p.acao),
        child: Text(texto, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final teclado = MediaQuery.of(context).viewInsets.bottom > 0;
    final alturaTela = MediaQuery.of(context).size.height;
    final formulario = CurvedAnimation(parent: _c, curve: const Interval(0.55, 1.0, curve: Curves.easeOutCubic));
    final campos = <Widget>[
      if (modo == Modo.criar || (_local && modo == Modo.entrar))
        _campo(nome, 'Seu nome', erro: erroNome, dicas: const [AutofillHints.name], key: const Key('campo-nome')),
      if (modo != Modo.verificar)
        _campo(email, 'Seu e-mail', erro: erroEmail, tipo: TextInputType.emailAddress,
            acao: (_local || modo == Modo.recuperar) ? TextInputAction.done : TextInputAction.next, dicas: const [AutofillHints.email], key: const Key('campo-email')),
      if (!_local && (modo == Modo.entrar || modo == Modo.criar))
        _campo(senha, modo == Modo.criar ? 'Crie uma senha' : 'Sua senha', erro: erroSenha, senhaCampo: true, tipo: TextInputType.visiblePassword,
            acao: TextInputAction.done, dicas: [modo == Modo.criar ? AutofillHints.newPassword : AutofillHints.password], key: const Key('campo-senha')),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          AnimatedContainer(
            duration: context.dur,
            height: alturaTela * (teclado ? 0.16 : 0.28),
            width: double.infinity,
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) => CustomPaint(painter: _PrumoPainter(_c.value * _duracao.inMilliseconds / 1000, p, context.semAnimacao)),
            ),
          ),
          Expanded(
            child: FadeTransition(
              opacity: formulario,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(formulario),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_titulo, style: context.titulo),
                    const SizedBox(height: 6),
                    Text(_subtitulo, style: context.corpo.copyWith(color: p.texto2)),
                    const SizedBox(height: 22),
                    ...campos,
                    if (modo == Modo.criar)
                      Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Senha com 8 caracteres ou mais, com letras e números.', style: context.legenda)),
                    if (erroGeral != null)
                      Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(erroGeral!, key: const Key('erro-geral'), style: context.legenda.copyWith(color: p.erro))),
                    if (aviso != null)
                      Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(aviso!, key: const Key('aviso'), style: context.legenda.copyWith(color: p.ok))),
                    const SizedBox(height: 4),
                    BotaoAcao(_botao, onTap: ocupado ? null : _enviar),
                    const SizedBox(height: 8),
                    if (modo == Modo.entrar && !_local)
                      Wrap(alignment: WrapAlignment.spaceBetween, children: [
                        _link('Esqueci a senha', () => _trocar(Modo.recuperar)),
                        _link('Criar conta', () => _trocar(Modo.criar)),
                      ]),
                    if (modo == Modo.criar) _link('Já tenho conta', () => _trocar(Modo.entrar)),
                    if (modo == Modo.recuperar) _link('Voltar para entrar', () => _trocar(Modo.entrar)),
                    if (modo == Modo.verificar) ...[
                      _link(espera > 0 ? 'Reenviar e-mail em ${espera}s' : 'Reenviar e-mail', espera > 0 ? () {} : _reenviar),
                      _link('Usar outra conta', _outraConta),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      _local
                          ? 'Nada sai do seu aparelho: nome, e-mail e leituras ficam salvos aqui.'
                          : 'As leituras ficam só neste aparelho. A conta serve para identificar você; entrar exige internet.',
                      style: context.legenda,
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Fio de prumo: oscilação amortecida até a vertical, com a ponta sobre a marca no chão.
class _PrumoPainter extends CustomPainter {
  final double t; // segundos
  final Paleta p;
  final bool parado;
  _PrumoPainter(this.t, this.p, this.parado);

  static const _amplitude = 0.52; // rad
  static const _freq = 1.05; // Hz
  static const _amortecimento = 1.55;

  @override
  void paint(Canvas canvas, Size s) {
    final cx = s.width / 2;
    const pino = 14.0, pesoAlt = 46.0;
    final chao = s.height - 12;
    final comprimento = chao - pino - 10; // a ponta fica 10 px acima da marca
    final angulo = parado ? 0.0 : _amplitude * math.exp(-_amortecimento * t) * math.cos(2 * math.pi * _freq * t);

    // marca no chão: onde a ponta do prumo deve parar
    final marca = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = p.texto2;
    canvas.drawCircle(Offset(cx, chao), 7, marca);
    canvas.drawLine(Offset(cx - 14, chao), Offset(cx + 14, chao), marca);
    canvas.drawLine(Offset(cx, chao - 14), Offset(cx, chao + 14), marca);

    canvas.save();
    canvas.translate(cx, pino);
    canvas.rotate(angulo);
    // fio
    canvas.drawLine(Offset.zero, Offset(0, comprimento - pesoAlt), Paint()..strokeWidth = 1.4..color = p.texto2);
    // peso de latão
    final topo = comprimento - pesoAlt;
    final peso = Path()
      ..moveTo(-8, topo)
      ..lineTo(8, topo)
      ..lineTo(12, topo + 12)
      ..lineTo(0, comprimento)
      ..lineTo(-12, topo + 12)
      ..close();
    canvas.drawPath(peso, Paint()..color = p.latao);
    canvas.drawLine(Offset(-12, topo + 12), Offset(12, topo + 12), Paint()..strokeWidth = 1..color = p.fundo.withValues(alpha: 0.35));
    canvas.restore();

    // pino de onde o fio pende
    canvas.drawCircle(Offset(cx, pino), 4.5, Paint()..color = p.texto);
  }

  @override
  bool shouldRepaint(_PrumoPainter o) => o.t != t || o.parado != parado || o.p != p;
}
