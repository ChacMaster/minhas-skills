#!/usr/bin/env bash
#
# minhas-skills — instalador
#
# Materializa skills em <base>/.agents/skills/<id> (fonte da verdade, agnóstica de agente)
# e replica como symlink para cada agente detectado na máquina (Claude Code, Codex, Cursor,
# OpenCode). Também instala arquivos de configuração (CLAUDE.md, RTK.md) e faz merge
# seletivo no settings.json, sempre com backup.
#
# Uso:
#   ./install.sh                                      # interativo
#   ./install.sh --scope global --mode symlink --all --yes
#   ./install.sh --only parzinho --scope project
#   ./install.sh --dry-run --all                      # mostra o que faria
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$REPO/manifest.json"
TARGETS="$REPO/targets.json"
STAMP="$(date +%Y%m%d-%H%M%S)"

SCOPE=""      # global | project
MODE=""       # symlink | copy
ONLY=""       # csv de ids
ASSUME_YES=0
SELECT_ALL=0
DRY_RUN=0

# ---------------------------------------------------------------- ui

if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; GRN=$'\033[32m'; YLW=$'\033[33m'; RED=$'\033[31m'; RST=$'\033[0m'
else
  B=""; DIM=""; GRN=""; YLW=""; RED=""; RST=""
fi

info() { printf '%s\n' "$*"; }
ok()   { printf '  %s✓%s %s\n' "$GRN" "$RST" "$*"; }
skip() { printf '  %s·%s %s%s%s\n' "$DIM" "$RST" "$DIM" "$*" "$RST"; }
warn() { printf '  %s!%s %s\n' "$YLW" "$RST" "$*"; }
die()  { printf '%serro:%s %s\n' "$RED" "$RST" "$*" >&2; exit 1; }

usage() {
  cat <<EOF
${B}minhas-skills${RST} — instala skills e configurações de agentes de IA.

  --scope <global|project>   global = \$HOME; project = diretório atual
  --mode  <symlink|copy>     symlink aponta pro clone (git pull atualiza); copy é independente
  --only  <id,id,...>        instala apenas estes itens do manifest
  --all                      instala todos os itens do manifest
  --yes, -y                  não pergunta nada (exige --scope e --mode)
  --dry-run, -n              apenas mostra o que faria
  --help, -h                 esta ajuda
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --scope)   SCOPE="${2:-}"; shift 2 ;;
    --mode)    MODE="${2:-}";  shift 2 ;;
    --only)    ONLY="${2:-}";  shift 2 ;;
    --all)     SELECT_ALL=1;   shift ;;
    --yes|-y)  ASSUME_YES=1;   shift ;;
    --dry-run|-n) DRY_RUN=1;   shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "argumento desconhecido: $1 (use --help)" ;;
  esac
done

command -v jq >/dev/null 2>&1 || die "jq não encontrado. Instale com: brew install jq"
[ -f "$MANIFEST" ] || die "manifest.json não encontrado em $REPO"
[ -f "$TARGETS" ]  || die "targets.json não encontrado em $REPO"

# ---------------------------------------------------------------- helpers

# SO atual — usado pelo campo "os" do manifest (itens específicos de plataforma).
case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)  OS=linux ;;
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  *) OS=unknown ;;
esac

expand_tilde() { case "$1" in "~/"*) printf '%s' "$HOME/${1#\~/}" ;; *) printf '%s' "$1" ;; esac; }

# Caminho relativo de $2 (alvo) a partir do diretório $1. Bash puro — sem realpath/python.
relpath() {
  local from="$1" to="$2" up=""
  from="${from%/}"; to="${to%/}"
  while [ "$to" != "$from" ] && [ "${to#"$from"/}" = "$to" ]; do
    up="../$up"
    from="$(dirname "$from")"
    [ "$from" = "/" ] && break
  done
  if [ "$to" = "$from" ]; then printf '%s' "${up%/}"
  else printf '%s%s' "$up" "${to#"$from"/}"; fi
}

TMPFILES=()
cleanup() { [ ${#TMPFILES[@]} -gt 0 ] && rm -f "${TMPFILES[@]}"; return 0; }
trap cleanup EXIT

run() { if [ "$DRY_RUN" = 1 ]; then printf '  %s[dry-run]%s %s\n' "$DIM" "$RST" "$*"; else "$@"; fi; }

backup() {
  local f="$1"
  [ -e "$f" ] || [ -L "$f" ] || return 0
  local bak="$f.bak.$STAMP"
  if [ "$DRY_RUN" = 1 ]; then printf '  %s[dry-run]%s backup %s -> %s\n' "$DIM" "$RST" "$f" "$bak"
  else mv "$f" "$bak"; warn "backup: $(basename "$bak")"; fi
}

ask() { # ask <pergunta> <opt1> <opt2> -> ecoa a escolha
  local q="$1" a="$2" b="$3" ans
  while :; do
    printf '%s%s%s [%s/%s] ' "$B" "$q" "$RST" "$a" "$b" >&2
    read -r ans </dev/tty || die "sem tty — use --scope/--mode/--yes"
    ans="${ans:-$a}"
    case "$ans" in "$a") printf '%s' "$a"; return ;; "$b") printf '%s' "$b"; return ;; esac
    printf '  responda %s ou %s\n' "$a" "$b" >&2
  done
}

# ---------------------------------------------------------------- escopo e modo

if [ -z "$SCOPE" ]; then
  [ "$ASSUME_YES" = 1 ] && die "--yes exige --scope"
  info ""
  info "${B}Escopo da instalação${RST}"
  info "  ${DIM}global  → \$HOME (${HOME}) — vale para todos os projetos${RST}"
  info "  ${DIM}project → diretório atual ($(pwd)) — vale só para este projeto${RST}"
  SCOPE="$(ask "Escopo?" global project)"
fi
[ "$SCOPE" = global ] || [ "$SCOPE" = project ] || die "--scope deve ser 'global' ou 'project'"

if [ -z "$MODE" ]; then
  [ "$ASSUME_YES" = 1 ] && die "--yes exige --mode"
  info ""
  info "${B}Modo de instalação${RST}"
  info "  ${DIM}symlink → aponta para este clone ($REPO); 'git pull' atualiza na hora${RST}"
  info "  ${DIM}copy    → cópia independente; atualizar exige rodar o instalador de novo${RST}"
  MODE="$(ask "Modo?" symlink copy)"
fi
[ "$MODE" = symlink ] || [ "$MODE" = copy ] || die "--mode deve ser 'symlink' ou 'copy'"

if [ "$SCOPE" = global ]; then BASE="$HOME"; else BASE="$(pwd)"; fi
AGENTS_DIR="$BASE/.agents/skills"

# ---------------------------------------------------------------- seleção de itens

ITEM_IDS=(); while IFS= read -r l; do ITEM_IDS+=("$l"); done < <(jq -r '.items[].id' "$MANIFEST")
SELECTED=()

if [ -n "$ONLY" ]; then
  IFS=',' read -r -a want <<< "$ONLY"
  for w in "${want[@]}"; do
    w="$(printf '%s' "$w" | tr -d '[:space:]')"
    printf '%s\n' "${ITEM_IDS[@]}" | grep -qx "$w" || die "item desconhecido no --only: $w"
    SELECTED+=("$w")
  done
elif [ "$SELECT_ALL" = 1 ] || [ "$ASSUME_YES" = 1 ]; then
  SELECTED=("${ITEM_IDS[@]}")
else
  info ""
  info "${B}Itens disponíveis${RST}"
  for id in "${ITEM_IDS[@]}"; do
    desc="$(jq -r --arg i "$id" '.items[] | select(.id==$i) | .description' "$MANIFEST")"
    printf '  %s%-18s%s %s%s%s\n' "$B" "$id" "$RST" "$DIM" "$desc" "$RST"
  done
  printf '\n%sQuais instalar?%s (ids separados por espaço, ou ENTER para todos) ' "$B" "$RST"
  read -r line </dev/tty || true
  if [ -z "${line// /}" ]; then
    SELECTED=("${ITEM_IDS[@]}")
  else
    for w in $line; do
      printf '%s\n' "${ITEM_IDS[@]}" | grep -qx "$w" || die "item desconhecido: $w"
      SELECTED+=("$w")
    done
  fi
fi

info ""
info "${B}Instalando${RST} escopo=${SCOPE} modo=${MODE} base=${BASE}"
[ "$DRY_RUN" = 1 ] && info "${YLW}(dry-run — nada será escrito)${RST}"

# ---------------------------------------------------------------- instaladores por tipo

install_skill() {
  local id="$1" src="$REPO/$2" dst="$AGENTS_DIR/$1"
  [ -d "$src" ] || die "skill não encontrada: $src"

  run mkdir -p "$AGENTS_DIR"

  # Camada 1: repo -> .agents/skills/<id>
  if [ "$MODE" = symlink ] && [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    skip ".agents/skills/$id (symlink já correto)"
  else
    backup "$dst"
    if [ "$MODE" = symlink ]; then
      run ln -s "$src" "$dst"; ok ".agents/skills/$id → $src"
    else
      run cp -R "$src" "$dst"; ok ".agents/skills/$id (cópia)"
    fi
  fi

  # Camada 2: .agents/skills/<id> -> <agente>/skills/<id>, sempre symlink relativo
  local agent detect adir link rel
  while IFS= read -r agent; do
    detect="$(expand_tilde "$(jq -r --arg a "$agent" '.agents[$a].detect' "$TARGETS")")"
    if [ ! -d "$detect" ]; then
      skip "$agent: não instalado nesta máquina ($detect)"
      continue
    fi
    adir="$(jq -r --arg a "$agent" --arg s "$SCOPE" '.agents[$a][$s]' "$TARGETS")"
    case "$adir" in "~/"*) adir="$(expand_tilde "$adir")" ;; *) adir="$BASE/$adir" ;; esac
    link="$adir/$id"
    rel="$(relpath "$adir" "$AGENTS_DIR/$id")"

    if [ -L "$link" ] && [ "$(readlink "$link")" = "$rel" ]; then
      skip "$agent: link já correto"
      continue
    fi
    run mkdir -p "$adir"
    backup "$link"
    run ln -s "$rel" "$link"
    ok "$agent: ${link/#$HOME/\~} → $rel"
  done < <(jq -r '.agents | keys[]' "$TARGETS")
}

install_home_file() {
  local id="$1" src="$REPO/$2" dst="$BASE/$3" is_exec="${4:-false}"
  [ -f "$src" ] || die "arquivo não encontrado: $src"

  [ "$is_exec" = true ] && [ ! -x "$src" ] && run chmod +x "$src"

  if [ "$MODE" = symlink ] && [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    skip "$3 (symlink já correto)"; return
  fi
  run mkdir -p "$(dirname "$dst")"
  backup "$dst"
  if [ "$MODE" = symlink ]; then run ln -s "$src" "$dst"; ok "$3 → $src"
  else
    run cp "$src" "$dst"
    [ "$is_exec" = true ] && run chmod +x "$dst"
    ok "$3 (cópia)"
  fi
}

install_settings_merge() {
  local id="$1" src="$REPO/$2" dst="$BASE/$3"
  [ -f "$src" ] || die "fragmento não encontrado: $src"
  run mkdir -p "$(dirname "$dst")"

  # {{BASE}} no fragmento vira o diretório de instalação (\$HOME ou o projeto).
  if grep -q '{{BASE}}' "$src"; then
    local resolved; resolved="$(mktemp)"; TMPFILES+=("$resolved")
    sed "s|{{BASE}}|${BASE}|g" "$src" > "$resolved"
    src="$resolved"
  fi

  local current merged
  if [ -f "$dst" ]; then
    jq -e . "$dst" >/dev/null 2>&1 || die "$dst não é JSON válido — corrija antes de mesclar"
    current="$dst"
  else
    current=/dev/null
  fi

  # merge recursivo: o fragmento vence nas chaves que declara; o resto é preservado.
  merged="$(jq -s 'if length==1 then .[0] else .[0] * .[1] end' \
            <(if [ "$current" = /dev/null ]; then echo '{}'; else cat "$dst"; fi) "$src")"

  if [ -f "$dst" ] && [ "$(jq -S . "$dst")" = "$(printf '%s' "$merged" | jq -S .)" ]; then
    skip "$3 (já mesclado)"; return
  fi
  if [ "$DRY_RUN" = 1 ]; then
    printf '  %s[dry-run]%s merge em %s (chaves: %s)\n' "$DIM" "$RST" "$3" \
      "$(jq -r 'keys | join(", ")' "$src")"
    return
  fi
  backup "$dst"
  printf '%s\n' "$merged" > "$dst"
  ok "$3 (merge: $(jq -r 'keys | join(", ")' "$src"))"
}

# ---------------------------------------------------------------- loop principal

for id in "${SELECTED[@]}"; do
  type="$(jq -r --arg i "$id" '.items[] | select(.id==$i) | .type'   "$MANIFEST")"
  src="$( jq -r --arg i "$id" '.items[] | select(.id==$i) | .source' "$MANIFEST")"
  dest="$(jq -r --arg i "$id" '.items[] | select(.id==$i) | .dest // ""' "$MANIFEST")"
  isexec="$(jq -r --arg i "$id" '.items[] | select(.id==$i) | .exec // false' "$MANIFEST")"
  oses="$(jq -r --arg i "$id" '.items[] | select(.id==$i) | (.os // []) | join(" ")' "$MANIFEST")"

  info ""
  info "${B}▸ $id${RST} ${DIM}($type)${RST}"

  if [ -n "$oses" ] && ! printf '%s\n' $oses | grep -qx "$OS"; then
    skip "não suportado neste SO ($OS) — suportados: $oses"
    continue
  fi

  case "$type" in
    skill)          install_skill        "$id" "$src" ;;
    home-file)      install_home_file    "$id" "$src" "$dest" "$isexec" ;;
    settings-merge) install_settings_merge "$id" "$src" "$dest" ;;
    *) die "tipo desconhecido no manifest: $type" ;;
  esac
done

info ""
info "${GRN}${B}Pronto.${RST} Backups (se houve) com sufixo ${DIM}.bak.$STAMP${RST}"
[ "$MODE" = symlink ] && info "${DIM}Modo symlink: mantenha o clone em $REPO. 'git pull' atualiza tudo.${RST}"
exit 0
