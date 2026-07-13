# minhas-skills

Skills e configurações de agentes de IA, versionadas e portáteis entre máquinas.

As skills vivem em `.agents/skills/` — a fonte da verdade, agnóstica de agente — e são
replicadas como **symlink** para cada agente detectado na máquina (Claude Code, Codex,
Cursor, OpenCode). Escrever a skill uma vez basta; todos os agentes enxergam.

## Bootstrap numa máquina nova

```bash
git clone git@github.com:ChacMaster/minhas-skills.git ~/minhas-skills
cd ~/minhas-skills
./install.sh
```

O instalador pergunta o **escopo** (global ou projeto) e o **modo** (symlink ou cópia),
mostra a lista de itens e instala o que você escolher. Sem perguntas:

```bash
./install.sh --scope global --mode symlink --all --yes
./install.sh --only parzinho --scope project --mode copy -y
./install.sh --dry-run --all --scope global --mode symlink   # só mostra o que faria
```

Requer `jq` (`brew install jq`).

## Escopo e modo

| | |
|---|---|
| **global** | instala em `$HOME` — vale para todos os projetos |
| **project** | instala no diretório atual — vale só para aquele projeto |
| **symlink** | `.agents/skills/<id>` aponta para este clone; `git pull` atualiza na hora. Exige manter o clone no lugar. |
| **copy** | cópia independente do clone; atualizar exige rodar o instalador de novo. |

A escolha symlink/cópia vale para o elo **repo → `.agents/`**. O elo
**`.agents/` → agente** é sempre symlink relativo — é o padrão que os agentes já usam.

```
repo/skills/parzinho ──(symlink ou cópia)──> ~/.agents/skills/parzinho
                                                      ▲
                        ~/.claude/skills/parzinho ────┤  (symlink relativo,
                        ~/.codex/skills/parzinho  ────┤   criado só para os
                        ~/.cursor/skills-cursor/… ────┘   agentes detectados)
```

## O que tem aqui

| Item | Tipo | O que faz |
|---|---|---|
| `parzinho` | skill | Modo de pareamento iterativo item-a-item, com controle em `tmp/modificacoes.md` |
| `estilo-resposta` | home-file | `~/.claude/CLAUDE.md` — estilo de resposta (pt-BR, sem bajulação) |
| `rtk-doc` | home-file | `~/.claude/RTK.md` — referência do RTK |
| `settings` | settings-merge | Merge em `~/.claude/settings.json`: hook do RTK, language, theme, spinnerVerbs |

Nada é sobrescrito sem backup (`<arquivo>.bak.<timestamp>`). O `settings.json` recebe
**merge seletivo**: as chaves do fragmento vencem, todo o resto da sua config local sobrevive.
Rodar o instalador duas vezes é seguro — ele detecta o que já está correto e pula.

## Adicionar uma skill nova

1. Crie `skills/<nome>/SKILL.md` com frontmatter `name` e `description` (a `description` é o
   que faz o agente decidir invocar a skill — descreva os gatilhos reais).
2. Adicione a entrada correspondente em `manifest.json` (`"type": "skill"`).
3. Commit, push, e nas outras máquinas: `git pull` (modo symlink) ou `./install.sh` (modo cópia).

## Adicionar suporte a outro agente

Acrescente uma entrada em `targets.json` com `detect` (diretório que prova que o agente está
instalado), `global` e `project`. O instalador passa a linkar ali automaticamente — e continua
pulando em silêncio nas máquinas onde aquele agente não existe.
