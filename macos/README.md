# Env Studio no macOS

Instalação e configuração do app para Mac com chip Apple (M). O que o produto faz e o formato do `.env` estão no [README da raiz](../README.md).

## Requisitos

- macOS 14 ou mais novo
- Apple Silicon (arm64)
- Para compilar: Xcode 15+ ou Swift 5.9+ (Command Line Tools)
- Aba **Conexões** (opcional): AWS CLI v2 e [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
- **Testar senha** (opcional): `mysql` ou `psql` no PATH

## Instalar pelo DMG

Baixe `EnvStudio-arm64.dmg` no [Release](https://github.com/festevao/env-studio/releases) `v0.1.0`, abra e arraste **Env Studio** para **Aplicativos**.

O app não é notarizado. Na primeira abertura, se o macOS bloquear:

1. Clique com o botão direito no app e escolha **Abrir**, ou
2. No Terminal: `xattr -dr com.apple.quarantine /Applications/Env\ Studio.app`

## Compilar

Na pasta `macos/`:

```bash
chmod +x scripts/make-app.sh scripts/make-dmg.sh run.sh
./scripts/make-app.sh
open dist/EnvStudio.app
```

O DMG (não vai para o git; sai no Release):

```bash
./scripts/make-dmg.sh
```

Atalho de desenvolvimento, sem empacotar o `.app`:

```bash
./run.sh
```

Evite `swift run EnvStudio` enquanto edita um `.env`: o Terminal pode continuar recebendo o teclado.

Testes, a partir de `macos/`:

```bash
swift test
swift run EnvStudioCoreVerify
```

## Onde a configuração fica

Tudo em `~/Library/Application Support/EnvStudio/`. Nada disso é gravado na pasta do projeto.

| Arquivo | Conteúdo |
|---------|----------|
| `connectivity.json` | Profiles, alvos SSM e túneis de dev, hom e prod |
| `workspace-metadata/` | Tags e vínculo **Túnel SQL** de cada pasta aberta |
| `managed-workspaces.json` | Pastas que o app acompanha ao gerar token |
| `active-tunnel-sessions.json` | Túnel aberto pelo app; apagado ao sair com ⌘Q |

**Adicionar túnel…** cria o mesmo `flag` nos três ambientes. **Editar…** muda host e portas só na aba atual. **Excluir…** remove o `flag` de dev, hom e prod. Túnel indisponível é `remoteHost` vazio; preencha em **Editar…**.

Status do túnel: verde (aberto por este app), laranja (porta usada por outro ambiente), amarelo (outro processo; **Copiar PID**), vermelho (fechado). Portas locais iguais entre ambientes permitem um forward por vez. Para os três ao mesmo tempo, use portas distintas (por exemplo `26524`, `26534`, `26544`).

Sair do app (⌘Q) encerra os túneis que ele abriu. Encerrar à força pode deixar o processo no ar.
