---
name: parzinho
description: Modo de pareamento iterativo item-a-item ("codar em parzinho"). Use quando o usuário pedir para "codar em parzinho", "vamos codar em parzinho", entrar em modo parzinho, ou pedir um fluxo de pareamento onde ele passa um item por vez (bug, ajuste ou feature) e cada item é registrado e controlado em tmp/modificacoes.md com status OPEN/VALIDATING/DONE/CANCELLED. Não use para tarefas soltas fora desse fluxo de controle.
---

# Modo de trabalho: "codar em parzinho"

Quando o usuário pedir para **"codar em parzinho"** (ex.: "vamos agora codar em parzinho"),
entre neste modo de pareamento iterativo e permaneça nele até o usuário sinalizar o fim.

## Modos: offline (padrão) e online

O modo parzinho tem dois modos de operação:

- **Offline (padrão):** funciona em qualquer projeto. Todo o controle vive apenas em
  `tmp/modificacoes.md`, sem nenhuma integração externa. É o comportamento descrito neste arquivo.
- **Online:** além do `tmp/modificacoes.md`, os itens são espelhados **bidirecionalmente** num board
  externo (ex.: Azure DevOps). Ative o modo online **somente** quando o projeto tiver um sincronizador
  configurado — convenção: existir `scripts/devops-sync.mjs` no repo **e** o respectivo `scripts/.env`.
  Os detalhes específicos (qual board, org/projeto, mapeamento de colunas, como conectar) ficam
  **documentados no próprio projeto** (ex.: `AGENTS.md`), nunca nesta skill.

No modo online valem estes acréscimos ao schema base abaixo:
- estado extra **`[A]` EM ANDAMENTO** (item sendo implementado ativamente), além de `[O]/[V]/[D]/[C]`;
- campo **`**WorkItem:** #<id>`** em cada item, logo após `**Status:**`, ligando ao item do board (essa
  é a chave de correlação — renumerar/mover itens não quebra o vínculo);
- rodar a sincronização (ex.: `node scripts/devops-sync.mjs sync`) no **início** e no **fim** da sessão;
- **triagem**: itens criados direto no board chegam numa seção de entrada (ex.: `## 0 - Triage`) com
  número provisório; no início da sessão, avaliar e **mover** cada um para a seção/área correta;
- **classificação por área do board**: quando o board usar *Area Paths*, classificar cada item numa
  categoria ao registrá-lo. Default automático por seção, com campo opcional **`**Área:**`** no item
  para sobrepor. As categorias válidas e o mapeamento ficam documentados no próprio projeto.

## Fluxo (loop)

1. O usuário passa **um item por vez** (bug, ajuste ou feature).
2. Você **verifica/investiga** no código antes de agir.
3. **Avalie a complexidade** da solicitação. Se for **alta ou acima**, sugira **quebrar em itens menores** (você mesmo propõe a divisão) antes de prosseguir.
4. **Registra o item** no arquivo de controle `tmp/modificacoes.md` (ver estrutura abaixo).
5. Faz **perguntas de clarificação só se necessário**; o usuário responde quando necessário.
6. Você **implementa a correção** e marca o item como **[V] VALIDATING**.
7. O usuário **valida**. Você **só** muda o status para **[D] DONE** após o **OK explícito** do usuário — nunca marca DONE por conta própria.
8. Repete para o próximo item.

Mantenha as respostas **sucintas** — sem explicações longas, salvo se o usuário pedir detalhe.

## Arquivo de controle `tmp/modificacoes.md`

- Fica **sempre na raiz do repositório/projeto** (controla as modificações como um todo), nunca dentro de um subprojeto.
- **Sempre indique a qual projeto/subdiretório** o item pertence.
- Estrutura do arquivo:
  - Título: `# Correções <nome do projeto/repo>`.
  - Seção `## Diretivas para AGENTES` definindo os campos (abaixo).
  - Uma seção por área: `## 1 - Root` para mudanças no nível do repositório/monorepo, e **uma seção numerada por projeto/subdiretório** existente. Itens numerados como `<seção>.<n>` (ex.: `### 2.1`).
  - Cada seção termina com `<!-- Próximos itens entram abaixo conforme forem relatados -->`.
- Campos de cada item:
  - **Status:** [O] OPEN | [V] VALIDATING | [D] DONE | [C] CANCELLED. Ao concluir a implementação, marca **[V] VALIDATING** e aguarda; só passa para **[D] DONE** após o OK explícito do usuário.
  - **Sintoma:** o que o usuário pediu, como você entendeu, sucinto.
  - **Causa raiz:** causa identificada do problema/solicitação.
  - **Histórico:** todo o histórico de modificações e ações realizadas (tentativas, fixes, resultados).
  - **Motivo Cancelamento:** razão, preenchida apenas quando Status = [C].

Adapte os nomes de projeto/repo à estrutura real do repositório em que estiver trabalhando.
