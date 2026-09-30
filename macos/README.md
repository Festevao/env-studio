# Env Studio no macOS

Instalação do app para Mac com chip Apple (M) e macOS 14 ou mais novo. O que o produto faz está no [README da raiz](../README.md).

O arquivo já vem compilado. Não é preciso instalar Swift nem gerar o DMG.

## Instalar

1. Abra a aba [Releases](https://github.com/Festevao/env-studio/releases/tag/v0.1.2) e baixe **EnvStudio-arm64.dmg**.
2. Abra o DMG.
3. Arraste **Env Studio** para a pasta **Aplicativos**.
4. Abra o Launchpad ou a pasta Aplicativos e clique no ícone. O macOS avisa que a Apple não verificou o EnvStudio. Isso é esperado: o app não está na App Store. Vá em **Ajustes do Sistema → Privacidade e Segurança**, role até o aviso do EnvStudio e clique em **Abrir mesmo assim**.
5. Com o app aberto, clique com o botão direito no ícone do Dock e escolha **Opções → Manter no Dock**.

O nome do arquivo é `EnvStudio.app`. O rótulo **Env Studio** é só o que o Finder mostra.

Se a mensagem for **está danificado** e pedir para mover para o Lixo, o app não está corrompido. No Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/EnvStudio.app
open /Applications/EnvStudio.app
```

O editor de `.env` abre sem nenhum programa extra. AWS, MySQL e Postgres só entram se você for usar túneis ou **Testar senha**.

## Onde a configuração fica

Nada da sua máquina vai dentro do instalador. O DMG traz só o app e o ícone. Perfil AWS, túneis, tags e pastas nascem no Mac de quem instalou, em `~/Library/Application Support/EnvStudio/`:

| Arquivo | Conteúdo |
|---------|----------|
| `connectivity.json` | Profiles, alvos SSM e túneis de dev, hom e prod |
| `workspace-metadata/` | Tags e vínculo **Túnel SQL** de cada pasta aberta |
| `managed-workspaces.json` | Pastas que o app acompanha ao gerar token |
| `active-tunnel-sessions.json` | Túnel aberto pelo app; apagado ao sair com ⌘Q |

A primeira abertura começa com os três ambientes vazios. Use **Adicionar túnel…** e **Configurar…**. **Restaurar defaults** limpa o ambiente selecionado. Não recoloca hosts de ninguém.

Sair com ⌘Q encerra os túneis que o app abriu.

**Adicionar túnel…** cria o mesmo `flag` nos três ambientes. **Editar…** muda host e portas só na aba atual. **Excluir…** remove o `flag` de dev, hom e prod. Túnel indisponível é `remoteHost` vazio; preencha em **Editar…**.

Status: verde (aberto por este app), laranja (porta usada por outro ambiente), amarelo (outro processo; **Copiar PID**), vermelho (fechado). Portas locais iguais entre ambientes permitem um forward por vez. Para os três ao mesmo tempo, use portas distintas (por exemplo `26524`, `26534`, `26544`).

## Programas opcionais

### AWS CLI v2

Necessária para **Login SSO**, **Testar profile** e abrir túnel. Instalador de duplo clique:

[https://awscli.amazonaws.com/AWSCLIV2.pkg](https://awscli.amazonaws.com/AWSCLIV2.pkg)

Abra o pacote e siga o assistente. O app procura `aws` no PATH e também em `/opt/homebrew/bin/aws`.

### Session Manager plugin

Sem este plugin, **Abrir** túnel falha mesmo com a AWS CLI instalada. Instalador de duplo clique (macOS arm64):

[https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac_arm64/session-manager-plugin.pkg](https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac_arm64/session-manager-plugin.pkg)

### Cliente MySQL (`mysql`) — só para Testar senha

O app procura, nesta ordem: `/opt/homebrew/bin/mysql`, `/usr/local/bin/mysql` e o PATH. O pacote do Homebrew não se coloca sozinho nesse caminho. No Terminal:

```bash
brew install mysql-client
brew link --force mysql-client
```

`brew link --force` só cria o atalho em `/opt/homebrew/bin`. Não instala um servidor MySQL. Feche e abra o Env Studio depois do link.

### Cliente Postgres (`psql`) — só para Testar senha

Mesma ideia, com o pacote `libpq`:

```bash
brew install libpq
brew link --force libpq
```

O atalho fica em `/opt/homebrew/bin/psql`, que é um dos caminhos que o app já consulta.

## Só para quem mexe no código

Na pasta `macos/`:

```bash
chmod +x scripts/make-app.sh scripts/make-dmg.sh run.sh
./scripts/make-app.sh
open dist/EnvStudio.app
```

DMG local (o arquivo publicado é o do Release, não este):

```bash
./scripts/make-dmg.sh
```

Atalho de desenvolvimento: `./run.sh`. Evite `swift run EnvStudio` enquanto edita um `.env`, porque o Terminal pode ficar com o teclado.

Testes:

```bash
swift test
swift run EnvStudioCoreVerify
```

Requisito para compilar: Xcode 15+ ou Swift 5.9+ (Command Line Tools).
