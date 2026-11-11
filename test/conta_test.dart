import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leituras_predio/conta.dart';
import 'package:leituras_predio/tema.dart';
import 'package:leituras_predio/telas/entrada.dart';

/// Conta de mentira: guarda usuários na memória, como o servidor faria.
class ContaFalsa implements Conta {
  final contas = <String, ({String nome, String senha, bool verificado})>{};
  ContaUsuario? _atual;
  int verificacoesEnviadas = 0, recuperacoes = 0;
  bool semRede = false;
  bool confirmarAoRecarregar = false;

  @override
  bool get configurada => true;
  @override
  Future<void> iniciar() async {}
  @override
  ContaUsuario? get atual => _atual;

  void _rede() {
    if (semRede) throw ContaErro(mensagemErroAuth('network-request-failed'));
  }

  @override
  Future<void> entrar(String email, String senha) async {
    _rede();
    final c = contas[email.trim()];
    if (c == null || c.senha != senha) throw ContaErro(mensagemErroAuth('invalid-credential'));
    _atual = ContaUsuario(c.nome, email.trim(), c.verificado);
  }

  @override
  Future<void> criar(String nome, String email, String senha) async {
    _rede();
    if (contas.containsKey(email.trim())) throw ContaErro(mensagemErroAuth('email-already-in-use'));
    contas[email.trim()] = (nome: nome.trim(), senha: senha, verificado: false);
    _atual = ContaUsuario(nome.trim(), email.trim(), false);
    verificacoesEnviadas++;
  }

  @override
  Future<void> reenviarVerificacao() async {
    _rede();
    verificacoesEnviadas++;
  }

  @override
  Future<bool> recarregarVerificado() async {
    _rede();
    if (confirmarAoRecarregar && _atual != null) _atual = ContaUsuario(_atual!.nome, _atual!.email, true);
    return _atual?.verificado ?? false;
  }

  @override
  Future<void> recuperarSenha(String email) async {
    _rede();
    recuperacoes++;
  }

  @override
  Future<void> sair() async => _atual = null;
}

Future<ContaFalsa> abrir(WidgetTester t, {Modo modo = Modo.entrar}) async {
  t.view.physicalSize = const Size(780, 1688);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final f = ContaFalsa();
  Conta.i = f;
  await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: montarTema(Brightness.light), home: TelaEntrada(temPredio: true, modoInicial: modo)));
  await t.pumpAndSettle();
  return f;
}

Finder campo(String chave) => find.byKey(Key(chave));

void main() {
  group('validações', () {
    test('e-mail', () {
      expect(validarEmail(''), isNotNull);
      expect(validarEmail('ana@'), isNotNull);
      expect(validarEmail('ana@exemplo'), isNotNull);
      expect(validarEmail('ana exemplo@x.com'), isNotNull);
      expect(validarEmail(' ana@exemplo.com.br '), isNull);
    });
    test('senha nova: 8+ com letra e número', () {
      expect(validarSenhaNova('abc123'), isNotNull);
      expect(validarSenhaNova('abcdefghi'), isNotNull);
      expect(validarSenhaNova('123456789'), isNotNull);
      expect(validarSenhaNova('prumo2026'), isNull);
    });
    test('nome', () {
      expect(validarNome(' '), isNotNull);
      expect(validarNome('A'), isNotNull);
      expect(validarNome('Ana'), isNull);
    });
    test('mensagens de erro em português para os códigos do Firebase', () {
      for (final c in ['invalid-email', 'user-disabled', 'wrong-password', 'invalid-credential', 'email-already-in-use', 'weak-password', 'too-many-requests', 'network-request-failed', 'operation-not-allowed', 'xyz']) {
        expect(mensagemErroAuth(c), isNotEmpty);
        expect(mensagemErroAuth(c).contains('Exception'), isFalse);
      }
      expect(mensagemErroAuth('user-not-found'), mensagemErroAuth('wrong-password'), reason: 'não revela se o e-mail existe');
    });
  });

  group('tela de entrada', () {
    testWidgets('entrar: mostra erro de cada campo antes de chamar o servidor', (t) async {
      final f = await abrir(t);
      await t.tap(find.text('Entrar'));
      await t.pump();
      expect(find.text('Digite o seu e-mail.'), findsOneWidget);
      expect(find.text('Digite a sua senha.'), findsOneWidget);
      expect(f.atual, isNull);
    });

    testWidgets('entrar: senha errada → mensagem genérica, sem sair da tela', (t) async {
      final f = await abrir(t);
      f.contas['ana@x.com'] = (nome: 'Ana', senha: 'prumo2026', verificado: true);
      await t.enterText(campo('campo-email'), 'ana@x.com');
      await t.enterText(campo('campo-senha'), 'errada123');
      await t.tap(find.text('Entrar'));
      await t.pumpAndSettle();
      expect(find.text('E-mail ou senha incorretos.'), findsOneWidget);
      expect(find.text('Prumo'), findsOneWidget);
    });

    testWidgets('entrar: sem internet → avisa em português', (t) async {
      final f = await abrir(t);
      f.semRede = true;
      await t.enterText(campo('campo-email'), 'ana@x.com');
      await t.enterText(campo('campo-senha'), 'prumo2026');
      await t.tap(find.text('Entrar'));
      await t.pumpAndSettle();
      expect(find.textContaining('Sem conexão com a internet'), findsOneWidget);
    });

    testWidgets('entrar: conta ainda não confirmada vai para a tela de confirmação', (t) async {
      final f = await abrir(t);
      f.contas['ana@x.com'] = (nome: 'Ana', senha: 'prumo2026', verificado: false);
      await t.enterText(campo('campo-email'), 'ana@x.com');
      await t.enterText(campo('campo-senha'), 'prumo2026');
      await t.tap(find.text('Entrar'));
      await t.pumpAndSettle();
      expect(find.text('Confirme seu e-mail'), findsOneWidget);
      expect(find.textContaining('ana@x.com'), findsWidgets);
    });

    testWidgets('criar conta: valida nome, e-mail e senha fraca', (t) async {
      await abrir(t);
      await t.tap(find.text('Criar conta'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, 'Criar conta'));
      await t.pump();
      expect(find.text('Digite o seu nome.'), findsOneWidget);
      await t.enterText(campo('campo-nome'), 'Ana');
      await t.enterText(campo('campo-email'), 'ana@x.com');
      await t.enterText(campo('campo-senha'), 'curta1');
      await t.tap(find.widgetWithText(TextButton, 'Criar conta'));
      await t.pump();
      expect(find.text('A senha precisa ter ao menos 8 caracteres.'), findsOneWidget);
    });

    testWidgets('criar conta: envia e-mail de confirmação e espera; só segue depois de confirmar', (t) async {
      final f = await abrir(t);
      await t.tap(find.text('Criar conta'));
      await t.pumpAndSettle();
      await t.enterText(campo('campo-nome'), 'Ana');
      await t.enterText(campo('campo-email'), 'ana@x.com');
      await t.enterText(campo('campo-senha'), 'prumo2026');
      await t.tap(find.widgetWithText(TextButton, 'Criar conta'));
      await t.pumpAndSettle();
      expect(f.verificacoesEnviadas, 1);
      expect(find.text('Confirme seu e-mail'), findsOneWidget);
      // ainda não clicou no link
      await t.tap(find.text('Já confirmei'));
      await t.pumpAndSettle();
      expect(find.textContaining('Ainda não confirmado'), findsOneWidget);
      expect(find.text('Confirme seu e-mail'), findsOneWidget);
    });

    testWidgets('criar conta: e-mail repetido → mensagem clara', (t) async {
      final f = await abrir(t);
      f.contas['ana@x.com'] = (nome: 'Ana', senha: 'prumo2026', verificado: true);
      await t.tap(find.text('Criar conta'));
      await t.pumpAndSettle();
      await t.enterText(campo('campo-nome'), 'Ana');
      await t.enterText(campo('campo-email'), 'ana@x.com');
      await t.enterText(campo('campo-senha'), 'prumo2026');
      await t.tap(find.widgetWithText(TextButton, 'Criar conta'));
      await t.pumpAndSettle();
      expect(find.textContaining('Já existe uma conta'), findsOneWidget);
    });

    testWidgets('confirmação: reenviar só depois da espera de 30 s', (t) async {
      final f = await abrir(t, modo: Modo.verificar);
      expect(find.text('Reenviar e-mail'), findsOneWidget);
      await t.tap(find.text('Reenviar e-mail'));
      await t.pump();
      expect(f.verificacoesEnviadas, 1);
      expect(find.textContaining('Reenviar e-mail em'), findsOneWidget);
      await t.tap(find.textContaining('Reenviar e-mail em'));
      await t.pump();
      expect(f.verificacoesEnviadas, 1, reason: 'durante a espera não reenvia');
      await t.pump(const Duration(seconds: 31));
      expect(find.text('Reenviar e-mail'), findsOneWidget);
    });

    testWidgets('esqueci a senha: valida o e-mail e confirma o envio sem revelar se a conta existe', (t) async {
      final f = await abrir(t);
      await t.tap(find.text('Esqueci a senha'));
      await t.pumpAndSettle();
      await t.tap(find.text('Enviar link'));
      await t.pump();
      expect(find.text('Digite o seu e-mail.'), findsOneWidget);
      await t.enterText(campo('campo-email'), 'qualquer@x.com');
      await t.tap(find.text('Enviar link'));
      await t.pumpAndSettle();
      expect(f.recuperacoes, 1);
      expect(find.textContaining('Se existir uma conta'), findsOneWidget);
    });

    testWidgets('a senha começa oculta e pode ser mostrada', (t) async {
      await abrir(t);
      TextField senha() => t.widget<TextField>(campo('campo-senha'));
      expect(senha().obscureText, isTrue);
      await t.tap(find.byTooltip('Mostrar senha'));
      await t.pump();
      expect(senha().obscureText, isFalse);
    });
  });
}
