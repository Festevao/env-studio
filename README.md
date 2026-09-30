# Env Studio

Editor de `.env` com vários ambientes no mesmo arquivo (`local`, `dev`, `hom`, `prod`) e, no macOS, túneis AWS SSM com token RDS de curta duração.

Linux e Windows ainda não têm app. O formato do arquivo é o mesmo em todas as plataformas.

| Plataforma | Estado | Instalação |
|------------|--------|------------|
| macOS (Apple Silicon) | disponível | [macos/README.md](macos/README.md) |
| Linux | em breve | — |
| Windows | em breve | — |

## Formato do arquivo

Um único `.env`. Cada variável tem **uma** linha ativa (`KEY=valor`). Os outros ambientes ficam comentados (`#KEY=valor`), sob um cabeçalho `# local`, `# dev`, `# hom` ou `# prod`.

Exemplo completo, sem segredos: [`.env.example`](.env.example). Abra a pasta desse arquivo no app para ver o editor.

## Uso

1. Abra a pasta que contém o `.env`.
2. Troque o ambiente global ou o ambiente de uma variável. Quando as linhas divergem, o seletor global mostra Mixed.
3. Marque no máximo **uma** tag por variável: `secret`, `sqlStringConn`, `senha SQL`, `mongoStringConn`, `redisStringConn` ou `amqpStringConn`.
4. Na coluna **Túnel SQL**, ligue a variável ao `flag` de um túnel MySQL ou Postgres. Ao gerar o token na aba daquele ambiente, o app atualiza só aquele bloco (`dev`, `hom` ou `prod`, nunca `local`):
   - `sqlStringConn` — troca só a senha dentro da URL (já escapada).
   - `senha SQL` — substitui o valor inteiro pela senha escapada.
5. No painel do token, **senha (cliente visual)** é a crua (Workbench, Beekeeper, DBeaver). **Senha escapada** é a que entra em variável de ambiente ou na URL. Não cole a senha crua no `.env`.

O export flat redige `user:password` nas connection strings. Com a tag `secret`, o valor sai vazio (ou a linha some, se a opção de omitir estiver ligada).
