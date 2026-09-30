# Env Studio

Editor de `.env` com quatro ambientes no mesmo arquivo (`local`, `dev`, `hom`, `prod`) e, no macOS, túneis AWS SSM com token RDS de curta duração.

O app tem duas abas:

- **.env** — edita as variáveis da pasta aberta.
- **Conexões** — profiles AWS, túneis SSM e token RDS. Essa configuração é do Mac, não da pasta.

Linux e Windows ainda não têm app. O formato do arquivo é o mesmo em todas as plataformas.

| Plataforma | Estado | Instalação |
|------------|--------|------------|
| macOS (Apple Silicon) | disponível | [baixar o DMG](https://github.com/Festevao/env-studio/releases/tag/v0.1.2). Passo a passo, Gatekeeper e programas opcionais: [macos/README.md](macos/README.md) |
| Linux | em breve | — |
| Windows | em breve | — |

## Formato do arquivo

Um único `.env` na pasta aberta. Cada variável tem **uma** linha ativa (`KEY=valor`). Os outros ambientes ficam comentados (`#KEY=valor`), sob um cabeçalho `# local`, `# dev`, `# hom` ou `# prod`.

Exemplo sem segredos: [`.env.example`](.env.example).

**Abrir pasta…** carrega o `.env` dessa pasta. Se o arquivo não existir, o editor começa vazio e o primeiro salvamento cria o arquivo.

**Salvar automaticamente** grava sozinho depois de uma pausa curta. Com o interruptor desligado, use **Salvar** ou ⌘S. O ponto laranja significa que ainda há alteração na memória.

**Recarregar** lê o `.env` do disco de novo e descarta o que ainda não foi gravado.

Tags e o vínculo **Túnel SQL** não vão para dentro do `.env`. Ficam ao lado, em `~/Library/Application Support/EnvStudio/workspace-metadata/`, um arquivo por pasta.

## Colunas da aba .env

### Variável

O nome da chave, como `MYSQL_DATABASE_URL`. **Adicionar variável** cria uma linha nova. O nome precisa ser único no arquivo.

### Valor

O texto do ambiente que está ativo **nessa linha**. Trocar o ambiente da linha mostra o outro bloco, sem apagar os demais. O que você edita é o valor daquele ambiente.

### Ambiente

O bloco ativo da linha: `local`, `dev`, `hom` ou `prod`.

**Ambiente global**, acima da tabela, muda o ambiente de todas as linhas de uma vez. Se as linhas não estão todas no mesmo ambiente, o seletor mostra **Mixed**. Mixed não é uma opção para escolher: ele some quando todas as linhas voltam a ficar iguais.

### Tags

No máximo **uma** tag por variável. Escolher outra substitui a anterior. **Nenhuma** limpa a tag. Se sobrar mais de uma em metadado antigo, `secret` fica e as outras saem.

| Tag | Para que serve |
|-----|----------------|
| `secret` | Na exportação, o valor sai vazio. Com “Omitir linhas com tag secret”, a linha nem aparece. |
| `sqlStringConn` | URL MySQL ou Postgres. Na exportação, `user:password` vira `<user>:<password>`. Ao gerar token, só a senha dentro da URL é trocada. |
| `senha SQL` | A variável é a senha pura, não uma URL. Na exportação o valor sai como está. Ao gerar token, o valor inteiro vira a senha escapada. |
| `mongoStringConn` | URL `mongodb` ou `mongodb+srv`. Na exportação, o usuário e a senha da URL são redatados. Não entra no fluxo de token RDS. |
| `redisStringConn` | URL `redis` ou `rediss`. Mesma redação na exportação. Não entra no fluxo de token RDS. |
| `amqpStringConn` | URL `amqp` ou `amqps`. Mesma redação na exportação. Não entra no fluxo de token RDS. |

### Túnel SQL

Liga a variável ao `flag` de um túnel MySQL ou Postgres cadastrado em **Conexões**. Sem esse vínculo, gerar token não mexe na linha.

O seletor lista os túneis cujo driver é MySQL ou Postgres. Túnel com driver **Nenhum** (por exemplo Rabbit) não aparece aqui.

## Replicar valores

O ícone de setas no rodapé copia o valor **exibido** de cada linha (o ambiente ativo daquela linha) para um bloco inteiro: `local`, `dev`, `hom` ou `prod`.

O app pede confirmação. Confirmar sobrescreve todos os valores daquele ambiente. Ainda é preciso salvar (ou deixar o salvamento automático ligado) para gravar no `.env`.

## Pastas gerenciadas

Cada pasta aberta entra na lista **Pastas gerenciadas**, no rodapé. Ao gerar um token na aba **Conexões**, o app atualiza as variáveis ligadas àquele `flag` em todas essas pastas, só no bloco do ambiente selecionado em Conexões (`dev`, `hom` ou `prod`). `local` nunca recebe token.

**Remover do app** tira a pasta da lista. O `.env` no disco continua onde está.

A lista fica em `~/Library/Application Support/EnvStudio/managed-workspaces.json`.

## Importar

**Importar…** cola texto. Não abre um arquivo pelo Finder: copie o conteúdo e cole na caixa.

Dois formatos:

- **Multi-seção.** O texto tem cabeçalho `# local`, `# dev`, `# hom` ou `# prod`. O app usa esses blocos. O picker **Ambiente (import flat)** é ignorado.
- **Flat.** Só linhas `KEY=valor`, sem esses cabeçalhos. Tudo entra no ambiente escolhido no picker. Os outros ambientes de uma chave nova ficam vazios.

Dois modos:

- **Mesclar.** Chave que já existe recebe os valores colados. Chave nova é acrescentada. O resto do documento permanece.
- **Substituir documento.** O texto colado vira o documento inteiro. No flat, o ambiente ativo das linhas passa a ser o escolhido no picker.

Importar altera o documento na memória. Grave com **Salvar** ou com o salvamento automático.

## Exportar

**Exportar…** monta um `.env` flat, uma linha `KEY=valor` por variável, usando o ambiente ativo de cada linha. Não é o arquivo de quatro blocos. Não grava por cima do `.env` aberto.

O que cada tag faz na saída:

- `secret` — a linha fica `KEY=`. Se **Omitir linhas com tag secret** estiver ligado (é o padrão), a linha some.
- `sqlStringConn`, `mongoStringConn`, `redisStringConn`, `amqpStringConn` — `usuario:senha@host` vira `<user>:<password>@host`. O host, a porta e o caminho permanecem.
- `senha SQL` — o valor sai inteiro, sem redação, porque não é uma URL.
- Sem tag — o valor sai como está.

**Copiar** manda o texto para a área de transferência. **Salvar como…** sugere o nome `.env.export`.

## Conexões (SSM), do zero

A aba **Conexões** não depende da pasta do `.env`. Tudo fica em `~/Library/Application Support/EnvStudio/connectivity.json`.

Quem instala do zero vê `dev`, `hom` e `prod` vazios. Não há `local` aqui: túnel é só para os três ambientes remotos. **Restaurar defaults**, dentro de **Configurar…**, limpa o ambiente selecionado. Não recoloca hosts de exemplo.

### O que precisa existir no Mac antes

O editor de `.env` abre sem isso. Túnel e token precisam de:

- AWS CLI v2
- Session Manager plugin
- Profiles já escritos em `~/.aws/config`

O app **não importa** um arquivo de profile. Ele só lê os nomes das seções `[profile nome]` e `[default]` desse arquivo e mostra no picker. Criar o profile (SSO, `aws configure sso`, região, `sso_start_url`) é fora do app, com a AWS CLI.

Cliente `mysql` ou `psql` só entra em **Testar senha**. O caminho de instalação desses programas está em [macos/README.md](macos/README.md).

### Configurar o ambiente

1. Na aba **Conexões**, escolha `dev`, `hom` ou `prod`.
2. **Configurar…**
3. Preencha:
   - **Profile AWS** — o nome que está em `~/.aws/config`. Pode digitar ou escolher em **Profile existente**.
   - **Região** — por exemplo `us-east-1`.
   - **Instance ID (SSM target)** — a instância bastion que o Session Manager usa (`i-…`).
   - **Usuário RDS IAM** — o usuário do banco que recebe o token. Não é o usuário IAM da sua conta AWS.
   - **Caminho certificado RDS** — por padrão `~/.aws/rds/global-bundle.pem`. O app baixa o bundle da AWS nesse caminho na primeira geração de token, se o arquivo ainda não existir.
4. **Salvar.**

Repita para os outros ambientes. Profile, região, bastion e usuário podem ser diferentes em cada um.

### Login e teste

**Login SSO** chama o login da AWS CLI para o profile da aba atual.

**Testar profile** confere se a credencial responde.

A bolinha ao lado:

- verde, **SSO OK** — credencial válida para esse profile (o app confere de tempos em tempos)
- vermelha, **SSO necessário** — faça login e teste de novo
- cinza, **SSO —** — ainda não verificado

### Cadastrar túneis

**Adicionar túnel…** cria o mesmo `flag` em `dev`, `hom` e `prod`, com os mesmos valores iniciais.

Campos:

- **Identificador (flag)** — nome estável, usado na coluna **Túnel SQL**. Letras, números e hífen.
- **Título** — o nome que aparece na lista.
- **Aliases** — opcional, apelidos separados por vírgula.
- **Host remoto** — endpoint do RDS, broker ou o que o túnel alcança. Pode ficar vazio.
- **Porta local** — a porta no seu Mac, a que o cliente e o `.env` usam (`127.0.0.1`).
- **Porta remota** — a porta no host remoto (3306 no MySQL, 5432 no Postgres, etc.).
- **Driver** — Nenhum, MySQL ou Postgres.
- **Gerar token RDS** e **Database** — só aparecem com MySQL ou Postgres. O database entra na URL do token.

Host vazio deixa o túnel **Indisponível neste ambiente**. **Editar…** continua visível: preencha o host daquela aba para habilitar **Abrir**. Editar muda host, portas, driver e database só no ambiente da aba. O `flag` é o mesmo nos três.

**Excluir…** pede confirmação e remove o `flag` de `dev`, `hom` e `prod`. Túnel que o app abriu é encerrado.

### Abrir, cores e portas

| Cor | Significado | Ação |
|-----|-------------|------|
| Vermelho | Fechado | **Abrir** |
| Verde | Aberto por este app | **Encerrar**. **Token** aparece se o driver for MySQL ou Postgres |
| Laranja | A porta local está com outro túnel ou outro ambiente deste app | **Abrir** fica desligado. **Copiar PID** mostra quem está na porta. Encerre na aba do dono |
| Amarelo | Outro processo, fora deste app, escuta a porta | **Copiar PID** |
| Cinza | Indisponível: host remoto vazio | **Editar…** |

A mesma porta local nos três ambientes permite **um** forward por vez. Para `dev`, `hom` e `prod` ao mesmo tempo, use portas distintas (por exemplo `26524`, `26534` e `26544`).

Sair com ⌘Q encerra os túneis que o app abriu. Encerrar o app à força pode deixar o processo no ar; o amarelo e **Copiar PID** servem para achar esse processo.

## Token RDS

Com o túnel verde (aberto por este app) e driver MySQL ou Postgres, **Token** abre o painel.

**Gerar token** pede um token IAM de curta duração à AWS, usando o profile, a região, o host remoto, a porta remota e o usuário RDS IAM do ambiente da aba. A validade é de cerca de 15 minutos. O contador é local.

Quatro textos:

- **Senha (cliente visual)** — o token cru. Cole no Workbench, Beekeeper, DBeaver ou outro cliente com tela. Não cole no `.env` nem na linha de comando: caracteres como `/` e `+` quebram a URL.
- **Senha escapada** — o mesmo token com esses caracteres codificados. É o que entra em variável de ambiente e na URL.
- **URL** — a connection string com usuário, senha escapada, `127.0.0.1`, porta local, database e o certificado.
- **Linha .env** — `NOME="url"`, pronta para colar. O nome padrão é `MYSQL_DATABASE_URL` quando o `flag` é `mysql`; nos outros flags, `FLAG_DATABASE_URL`.

**Aplicar no .env** e a própria geração atualizam as variáveis da pasta aberta e das pastas gerenciadas que tenham o mesmo **Túnel SQL**, só no bloco do ambiente selecionado em Conexões:

- tag `sqlStringConn` — troca só o trecho da senha dentro de `usuario:senha@`. O usuário, o host e o resto da URL ficam. Se a URL não tiver `usuario:senha@`, a linha é pulada.
- tag `senha SQL` — substitui o valor inteiro pela senha escapada.

Os dois já vão escapados. Sem a coluna **Túnel SQL** apontando para esse `flag`, a linha não muda.

**Testar senha** conecta com `mysql` ou `psql` na porta local, usando o token. O cliente precisa estar em `/opt/homebrew/bin`, `/usr/local/bin` ou no `PATH`. O túnel precisa continuar verde.
