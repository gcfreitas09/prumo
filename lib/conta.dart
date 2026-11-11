import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_config.dart';

// ------------------------------------------------------------ validações

final _reEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

String? validarNome(String v) => v.trim().length < 2 ? 'Digite o seu nome.' : null;

String? validarEmail(String v) {
  final e = v.trim();
  if (e.isEmpty) return 'Digite o seu e-mail.';
  return _reEmail.hasMatch(e) ? null : 'E-mail inválido. Use o formato voce@exemplo.com.br.';
}

/// Cadastro: mínimo 8 caracteres, com letra e número. (No login só exige preenchimento.)
String? validarSenhaNova(String v) {
  if (v.length < 8) return 'A senha precisa ter ao menos 8 caracteres.';
  if (!RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) return 'Use letras e números na senha.';
  return null;
}

String? validarSenhaEntrada(String v) => v.isEmpty ? 'Digite a sua senha.' : null;

/// Mensagem em português para cada código de erro do Firebase Auth.
String mensagemErroAuth(String codigo) {
  switch (codigo) {
    case 'invalid-email':
      return 'E-mail inválido.';
    case 'user-disabled':
      return 'Esta conta foi desativada.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
    case 'invalid-login-credentials':
      return 'E-mail ou senha incorretos.';
    case 'email-already-in-use':
      return 'Já existe uma conta com este e-mail. Toque em "Já tenho conta" para entrar.';
    case 'weak-password':
      return 'Senha fraca. Use ao menos 8 caracteres, com letras e números.';
    case 'too-many-requests':
      return 'Muitas tentativas. Espere alguns minutos e tente de novo.';
    case 'network-request-failed':
      return 'Sem conexão com a internet. Conecte-se e tente de novo.';
    case 'operation-not-allowed':
      return 'Login por e-mail e senha não está ativado no projeto Firebase.';
    default:
      return 'Não foi possível concluir. Tente de novo.';
  }
}

// --------------------------------------------------------------- serviço

class ContaErro implements Exception {
  final String mensagem;
  const ContaErro(this.mensagem);
  @override
  String toString() => mensagem;
}

class ContaUsuario {
  final String nome, email;
  final bool verificado;
  const ContaUsuario(this.nome, this.email, this.verificado);
}

/// Conta do síndico. Troque [Conta.i] nos testes.
abstract class Conta {
  static Conta i = FirebaseConta();

  /// False enquanto lib/firebase_config.dart estiver vazio: o app usa a entrada local.
  bool get configurada;
  Future<void> iniciar();
  ContaUsuario? get atual;
  Future<void> entrar(String email, String senha);
  Future<void> criar(String nome, String email, String senha);
  Future<void> reenviarVerificacao();
  Future<bool> recarregarVerificado();
  Future<void> recuperarSenha(String email);
  Future<void> sair();
}

class FirebaseConta implements Conta {
  bool _ativo = false;

  @override
  bool get configurada => opcoesFirebase() != null;

  FirebaseAuth get _auth => FirebaseAuth.instance;

  @override
  Future<void> iniciar() async {
    final o = opcoesFirebase();
    if (o == null) return;
    await Firebase.initializeApp(options: o);
    _ativo = true;
  }

  @override
  ContaUsuario? get atual {
    if (!_ativo) return null;
    final u = _auth.currentUser;
    return u == null ? null : ContaUsuario(u.displayName ?? '', u.email ?? '', u.emailVerified);
  }

  Future<T> _tentar<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on FirebaseAuthException catch (e) {
      throw ContaErro(mensagemErroAuth(e.code));
    }
  }

  @override
  Future<void> entrar(String email, String senha) => _tentar(() async {
        final c = await _auth.signInWithEmailAndPassword(email: email.trim(), password: senha);
        await c.user?.reload();
      });

  @override
  Future<void> criar(String nome, String email, String senha) => _tentar(() async {
        final c = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: senha);
        await c.user?.updateDisplayName(nome.trim());
        await c.user?.sendEmailVerification();
      });

  @override
  Future<void> reenviarVerificacao() => _tentar(() async => _auth.currentUser?.sendEmailVerification());

  @override
  Future<bool> recarregarVerificado() => _tentar(() async {
        final u = _auth.currentUser;
        if (u == null) return false;
        await u.reload();
        return _auth.currentUser?.emailVerified ?? false;
      });

  @override
  Future<void> recuperarSenha(String email) => _tentar(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Future<void> sair() async {
    if (_ativo) await _auth.signOut();
  }
}
