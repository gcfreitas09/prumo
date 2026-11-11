# Ligar o login do Prumo ao Firebase (uma vez, ~10 min)

O código de login (entrar, criar conta, confirmar e-mail, esqueci a senha) está pronto.
Enquanto `lib/firebase_config.dart` estiver vazio, o app usa a entrada local (nome + e-mail, sem senha).

1. Abra https://console.firebase.google.com → **Adicionar projeto** → nome **Prumo** → pode desligar o Google Analytics → **Criar projeto**.
2. Menu **Criação → Authentication → Vamos começar → Método de login → E-mail/senha**: ligue só a primeira chave (e-mail/senha), **Salvar**.
3. Em **Authentication → Modelos (Templates) → Verificação de endereço de e-mail**, clique no lápis e troque o idioma para **Português (Brasil)** (e o mesmo em "Redefinição de senha").
4. Na visão geral do projeto, **Adicionar app → iOS**: ID do pacote `br.com.leituras.leiturasPredio` → Registrar → baixe **GoogleService-Info.plist** (pode pular o resto das etapas).
5. **Adicionar app → Android**: nome do pacote `br.com.leituras.leituras_predio` → Registrar → baixe **google-services.json**.
6. Mande os dois arquivos para o Claude. Eles só têm identificadores públicos do app (não são senhas). Ele preenche `lib/firebase_config.dart`, testa e instala.

Notas
- Entrar e criar conta exigem internet; depois disso a sessão fica salva e o app funciona offline.
- O e-mail de confirmação pode cair no spam na primeira vez.
- Só quem tiver conta confirmada entra. As leituras continuam só no aparelho (não vão para o Firebase).
