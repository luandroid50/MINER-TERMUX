#!/data/data/com.termux/files/usr/bin/bash
#
# install.sh — VerusCoin (VRSC) Termux Miner Installer
# Pool: VIPOR.NET (América do Sul)
# Minerador: Darktron/pre-compiled (branch "generic")
#
# Uso:
#   ./install.sh                → instalação/atualização completa (idempotente)
#   ./install.sh --status       → mostra status atual sem reinstalar nada
#   ./install.sh --diagnostico  → roda apenas os testes de verificação
#   ./install.sh --help         → ajuda
#
set -u

# ---------------------------------------------------------------------------
# Constantes / caminhos
# ---------------------------------------------------------------------------
MINER_DIR="$HOME/CCMINER"
LOG_FILE="$HOME/verus-install.log"
CONFIG_CONF="$MINER_DIR/config.conf"
CCMINER_BIN="$MINER_DIR/ccminer"
CCMINER_JSON="$MINER_DIR/ccminer-config.json"
START_SCRIPT="$MINER_DIR/start-miner.sh"
PASSWORD_MARKER="$MINER_DIR/.ssh_password_set"
BASHRC="$HOME/.bashrc"
TMUX_SESSION="ccminer"

RAW_BASE="https://raw.githubusercontent.com/Darktron/pre-compiled/generic"
CCMINER_URL="$RAW_BASE/ccminer"

# Pool fixa solicitada: VIPOR América do Sul
DEFAULT_POOL_NAME="SA-VIPOR"
DEFAULT_POOL_HOST="sa.vipor.net"
DEFAULT_POOL_PORT="5040"
DEFAULT_ALGO="verus"
DEFAULT_WALLET="RBysS5nvfnjFaRVZFZ6q5evAkPdSEbcBJg"
DEFAULT_SSH_PASSWORD="9292"

STEP_TOTAL=8
STEP_CUR=0

# ---------------------------------------------------------------------------
# Cores (com fallback se terminal não suportar)
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    C_RESET="\033[0m"; C_OK="\033[1;32m"; C_INFO="\033[1;36m"
    C_WARN="\033[1;33m"; C_ERR="\033[1;31m"; C_TITLE="\033[1;35m"
else
    C_RESET=""; C_OK=""; C_INFO=""; C_WARN=""; C_ERR=""; C_TITLE=""
fi

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log_raw() { printf '%s\n' "$1" >> "$LOG_FILE"; }

log_ok()    { printf "${C_OK}[OK]${C_RESET} %s\n" "$1";   log_raw "[OK] $1"; }
log_info()  { printf "${C_INFO}[INFO]${C_RESET} %s\n" "$1"; log_raw "[INFO] $1"; }
log_warn()  { printf "${C_WARN}[AVISO]${C_RESET} %s\n" "$1"; log_raw "[AVISO] $1"; }
log_error() { printf "${C_ERR}[ERRO]${C_RESET} %s\n" "$1" >&2; log_raw "[ERRO] $1"; }

step() {
    STEP_CUR=$((STEP_CUR + 1))
    printf "\n${C_TITLE}[%d/%d] %s...${C_RESET}\n" "$STEP_CUR" "$STEP_TOTAL" "$1"
    log_raw "== [$STEP_CUR/$STEP_TOTAL] $1 =="
}

banner() {
    printf "${C_TITLE}"
    cat <<'EOF'
╔══════════════════════════════════════╗
║       VERUSCOIN TERMUX MINER          ║
║              VIPOR.NET                ║
╚══════════════════════════════════════╝
EOF
    printf "${C_RESET}"
}

# ---------------------------------------------------------------------------
# Utilitários
# ---------------------------------------------------------------------------
mask_wallet() {
    local w="$1"
    if [ "${#w}" -le 12 ]; then
        printf '%s' "$w"
    else
        printf '%s...%s' "${w:0:6}" "${w: -6}"
    fi
}

sanitize_worker() {
    # Recebe um nome cru e devolve algo seguro para Stratum:
    # apenas [A-Za-z0-9-_], sem espaços, sem pontos, tamanho limitado.
    local raw="$1"
    local clean
    clean=$(printf '%s' "$raw" \
        | tr ' ' '-' \
        | tr -cd 'A-Za-z0-9-_' )
    [ -z "$clean" ] && clean="worker"
    printf '%.32s' "$clean"
}

# ---------------------------------------------------------------------------
# [1/8] Verificação do Termux
# ---------------------------------------------------------------------------
check_termux() {
    step "Verificando Termux"

    if [ -z "${PREFIX:-}" ] || [ ! -d "$PREFIX" ]; then
        log_error "Variável \$PREFIX não encontrada. Este script deve ser executado dentro do Termux."
        exit 1
    fi
    if [ ! -d "/data/data/com.termux" ]; then
        log_warn "Diretório /data/data/com.termux não encontrado. Prosseguindo mesmo assim, mas isto pode não ser um Termux padrão."
    fi

    log_ok "Termux detectado (PREFIX=$PREFIX)"

    if [ "$(id -u)" = "0" ]; then
        log_warn "Script rodando como root/UID 0. Isso não é necessário nem recomendado — o instalador não precisa de root em nenhuma etapa."
    fi
}

# ---------------------------------------------------------------------------
# [2/8] Arquitetura
# ---------------------------------------------------------------------------
detect_arch() {
    step "Detectando arquitetura"

    ARCH_RAW="$(uname -m 2>/dev/null || echo desconhecida)"

    case "$ARCH_RAW" in
        aarch64|arm64)
            ARCH="aarch64"
            log_ok "Arquitetura: aarch64 (compatível com o binário do repositório Darktron/pre-compiled)"
            ;;
        armv7l|armv7|arm)
            log_error "Arquitetura detectada: $ARCH_RAW (ARMv7 / 32-bit)."
            log_error "O repositório Darktron/pre-compiled fornece binários EXCLUSIVAMENTE para ARMv8 64-bit (aarch64)."
            log_error "O próprio autor do repositório afirma que dispositivos 32-bit não são suportados de propósito, por não serem viáveis para mineração."
            log_error "Não é possível prosseguir com uma instalação real e funcional neste aparelho usando este binário."
            log_error "Alternativa: compilar o CCminer a partir do código-fonte para ARMv7 (fora do escopo deste script) ou usar um aparelho ARMv8."
            exit 1
            ;;
        *)
            log_error "Arquitetura não reconhecida: $ARCH_RAW. Abortando por segurança (não é possível confirmar compatibilidade com o binário)."
            exit 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# [3/8] Dependências
# ---------------------------------------------------------------------------
install_dependencies() {
    step "Instalando dependências"

    local needed=()
    command -v git    >/dev/null 2>&1 || needed+=("git")
    command -v wget   >/dev/null 2>&1 || needed+=("wget")
    command -v curl   >/dev/null 2>&1 || needed+=("curl")
    command -v tar    >/dev/null 2>&1 || needed+=("tar")
    command -v unzip  >/dev/null 2>&1 || needed+=("unzip")
    command -v tmux   >/dev/null 2>&1 || needed+=("tmux")
    command -v sshd   >/dev/null 2>&1 || needed+=("openssh")
    command -v ip     >/dev/null 2>&1 || needed+=("iproute2")
    # coreutils quase sempre já vem com o Termux base; só instala se faltar algo básico como 'timeout'
    command -v timeout >/dev/null 2>&1 || needed+=("coreutils")
    # libjansson é uma biblioteca dinâmica exigida em tempo de execução pelo
    # binário do ccminer (Darktron/pre-compiled). Sem ela, o binário falha ao
    # carregar com um erro que parece (mas não é) incompatibilidade de ABI.
    dpkg -s libjansson >/dev/null 2>&1 || needed+=("libjansson")

    if [ "${#needed[@]}" -eq 0 ]; then
        log_ok "Todas as dependências já estão instaladas (nenhuma ação necessária)"
        return 0
    fi

    log_info "Pacotes faltando: ${needed[*]}"
    pkg update -y >>"$LOG_FILE" 2>&1

    if pkg install -y "${needed[@]}" >>"$LOG_FILE" 2>&1; then
        log_ok "Dependências instaladas: ${needed[*]}"
    else
        log_error "Falha ao instalar um ou mais pacotes: ${needed[*]}"
        log_error "Veja $LOG_FILE para detalhes. Tente rodar manualmente: pkg install ${needed[*]}"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# [4/8] CCminer
# ---------------------------------------------------------------------------
install_ccminer() {
    step "Instalando CCminer"

    mkdir -p "$MINER_DIR"

    if [ -x "$CCMINER_BIN" ]; then
        # Já existe um binário — testa se realmente executa antes de reaproveitar
        if "$CCMINER_BIN" -V >/dev/null 2>&1 || "$CCMINER_BIN" -h >/dev/null 2>&1; then
            log_ok "CCminer já instalado e funcional em $CCMINER_BIN (reaproveitando, sem novo download)"
            return 0
        else
            log_warn "Binário existente em $CCMINER_BIN não respondeu corretamente. Baixando novamente."
            rm -f "$CCMINER_BIN"
        fi
    fi

    log_info "Baixando binário de $CCMINER_URL"
    if ! wget -q -O "$CCMINER_BIN" "$CCMINER_URL"; then
        log_error "Não foi possível baixar o CCminer de $CCMINER_URL"
        log_error "Verifique sua conexão com a internet e tente novamente: ./install.sh"
        exit 1
    fi

    chmod +x "$CCMINER_BIN"

    if [ ! -s "$CCMINER_BIN" ]; then
        log_error "O arquivo baixado está vazio ou corrompido."
        exit 1
    fi
    log_ok "CCminer baixado"

    local exec_err
    exec_err="$("$CCMINER_BIN" -V 2>&1 1>/dev/null)"
    if [ -z "$exec_err" ] && "$CCMINER_BIN" -V >/dev/null 2>&1; then
        log_ok "CCminer executável e responde corretamente"
    elif "$CCMINER_BIN" -h >/dev/null 2>&1; then
        log_ok "CCminer executável e responde corretamente"
    else
        log_error "O binário foi baixado, mas não conseguiu ser executado neste dispositivo."
        log_error "Mensagem original do sistema: ${exec_err:-<sem saída de erro>}"
        if printf '%s' "$exec_err" | grep -qi "not found\|cannot locate\|library"; then
            log_error "Isso indica uma biblioteca dinâmica faltando (não é incompatibilidade de arquitetura)."
            log_error "Tente: pkg install libjansson -y   e rode ./install.sh de novo."
        else
            log_error "Rode manualmente para ver o erro completo: $CCMINER_BIN -V"
            log_error "Se o Termux estiver desatualizado, rode: pkg update -y && pkg upgrade -y"
        fi
        exit 1
    fi

    # Checagem best-effort do algoritmo verus (informativa, não bloqueante)
    if "$CCMINER_BIN" -h 2>&1 | grep -qi verus; then
        log_ok "Algoritmo 'verus' encontrado na ajuda do CCminer"
    else
        log_warn "Não foi possível confirmar 'verus' no texto de ajuda do binário (checagem apenas informativa)."
        log_warn "O repositório Darktron/pre-compiled é focado em VerusHash; a mineração será testada de forma real na etapa de verificação final."
    fi
}

# ---------------------------------------------------------------------------
# [Config central] ~/CCMINER/config.conf
# ---------------------------------------------------------------------------
load_or_create_config_conf() {
    if [ -f "$CONFIG_CONF" ]; then
        # shellcheck disable=SC1090
        source "$CONFIG_CONF"
        log_ok "Configuração existente carregada de $CONFIG_CONF"
    else
        WALLET="$DEFAULT_WALLET"
        POOL_NAME="$DEFAULT_POOL_NAME"
        POOL_HOST="$DEFAULT_POOL_HOST"
        POOL_PORT="$DEFAULT_POOL_PORT"
        ALGO="$DEFAULT_ALGO"
        SSH_PASSWORD="$DEFAULT_SSH_PASSWORD"
        WORKER=""   # preenchido em detect_worker_name()
        log_info "Nenhuma configuração encontrada — usando valores padrão"
    fi
}

save_config_conf() {
    cat > "$CONFIG_CONF" <<EOF
# Configuração central do Verus Termux Miner
# Edite este arquivo para trocar carteira, pool ou senha do SSH.
# Depois de editar, rode ./install.sh novamente para aplicar.

WALLET="$WALLET"
POOL_NAME="$POOL_NAME"
POOL_HOST="$POOL_HOST"
POOL_PORT="$POOL_PORT"
ALGO="$ALGO"
SSH_PASSWORD="$SSH_PASSWORD"
WORKER="$WORKER"
EOF
    chmod 600 "$CONFIG_CONF"
}

# ---------------------------------------------------------------------------
# Worker automático
# ---------------------------------------------------------------------------
detect_worker_name() {
    if [ -n "${WORKER:-}" ]; then
        log_ok "Worker já definida anteriormente: $WORKER (mantendo para consistência)"
        return 0
    fi

    local model=""
    if command -v getprop >/dev/null 2>&1; then
        model="$(getprop ro.product.model 2>/dev/null)"
        [ -z "$model" ] && model="$(getprop ro.product.name 2>/dev/null)"
    fi
    [ -z "$model" ] && model="$(hostname 2>/dev/null)"
    [ -z "$model" ] && model="android-device"

    WORKER="$(sanitize_worker "$model")"
    log_ok "Worker detectada automaticamente: $WORKER"
}

# ---------------------------------------------------------------------------
# Gera o config.json real do CCminer a partir do config.conf
# ---------------------------------------------------------------------------
generate_ccminer_json() {
    step "Configurando mineração"

    # Detecta o número de núcleos de CPU disponíveis e usa TODOS por padrão,
    # em vez de depender do comportamento implícito de "threads": 0.
    local cpu_cores
    cpu_cores="$(nproc 2>/dev/null)"
    [ -z "$cpu_cores" ] && cpu_cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null)"
    [ -z "$cpu_cores" ] && cpu_cores="$(grep -c ^processor /proc/cpuinfo 2>/dev/null)"
    [ -z "$cpu_cores" ] && cpu_cores=4  # fallback conservador se nada funcionar

    cat > "$CCMINER_JSON" <<EOF
{
    "pools":
        [{
            "name": "$POOL_NAME",
            "url": "stratum+tcp://$POOL_HOST:$POOL_PORT",
            "timeout": 180,
            "disabled": 0
        }],

    "user": "$WALLET.$WORKER",
    "pass": "",
    "algo": "$ALGO",
    "threads": $cpu_cores,
    "cpu-priority": 1,
    "cpu-affinity": -1,
    "retry-pause": 10,
    "api-allow": "127.0.0.1",
    "api-bind": "127.0.0.1:4068"
}
EOF
    log_ok "Pool configurada: $POOL_NAME ($POOL_HOST:$POOL_PORT)"
    log_ok "Carteira configurada: $(mask_wallet "$WALLET")"
    log_ok "Worker configurada: $WORKER"
    log_ok "Threads configuradas: $cpu_cores (todos os núcleos detectados neste aparelho)"
    log_info "API do CCminer restrita a 127.0.0.1:4068 (não exposta na rede, por segurança)"
}

# ---------------------------------------------------------------------------
# [5/8] SSH
# ---------------------------------------------------------------------------
setup_ssh() {
    step "Configurando SSH"

    local sshd_config="$PREFIX/etc/ssh/sshd_config"
    SSH_USER="$(whoami)"

    if [ ! -f "$PASSWORD_MARKER" ]; then
        if echo -e "$SSH_PASSWORD\n$SSH_PASSWORD" | passwd >>"$LOG_FILE" 2>&1; then
            touch "$PASSWORD_MARKER"
            log_ok "Senha de SSH definida"
        else
            log_warn "Não foi possível confirmar a definição automática da senha. Defina manualmente com: passwd"
        fi
    else
        log_ok "Senha de SSH já configurada anteriormente (não alterada, para não sobrescrever mudanças manuais)"
    fi

    if [ -f "$sshd_config" ]; then
        SSH_PORT="$(grep -E '^Port ' "$sshd_config" 2>/dev/null | awk '{print $2}')"
    fi
    [ -z "${SSH_PORT:-}" ] && SSH_PORT="8022"

    if pgrep -x sshd >/dev/null 2>&1; then
        log_ok "Servidor SSH já está em execução"
    else
        if sshd 2>>"$LOG_FILE"; then
            log_ok "Servidor SSH iniciado na porta $SSH_PORT"
        else
            log_error "Não foi possível iniciar o sshd. Verifique se o pacote 'openssh' está instalado corretamente."
            log_error "Tente manualmente: sshd"
        fi
    fi

    LOCAL_IP="$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')"
    [ -z "$LOCAL_IP" ] && LOCAL_IP="$(ip -4 addr show 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | grep -v '^127' | head -n1)"
    [ -z "$LOCAL_IP" ] && LOCAL_IP="não-detectado"

    log_ok "Usuário SSH: $SSH_USER"
    log_ok "IP local detectado: $LOCAL_IP"
}

# ---------------------------------------------------------------------------
# Script de inicialização do minerador (start-miner.sh)
# ---------------------------------------------------------------------------
write_start_miner_script() {
    cat > "$START_SCRIPT" <<'EOSCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
# start-miner.sh — inicia o CCminer dentro de uma sessão tmux persistente,
# evitando duplicar instâncias caso já esteja rodando.

MINER_DIR="$HOME/CCMINER"
CCMINER_BIN="$MINER_DIR/ccminer"
CCMINER_JSON="$MINER_DIR/ccminer-config.json"
TMUX_SESSION="ccminer"

# Se o processo já está rodando, não faz nada (evita instâncias duplicadas)
if pgrep -f "$CCMINER_BIN" >/dev/null 2>&1; then
    exit 0
fi

if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    # Sessão tmux existe mas o processo do minerador morreu dentro dela: recria
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null
fi

# tmux recusa criar uma sessão com nome já existente, então mesmo que duas
# sessões do Termux cheguem aqui quase ao mesmo tempo, apenas uma vence
# e nenhum minerador duplicado é criado.
tmux new-session -d -s "$TMUX_SESSION" "$CCMINER_BIN -c $CCMINER_JSON" 2>/dev/null
EOSCRIPT
    chmod +x "$START_SCRIPT"
}

# ---------------------------------------------------------------------------
# [6/8] Persistência tmux + [7/8] Inicialização automática
# ---------------------------------------------------------------------------
setup_tmux_and_autostart() {
    step "Configurando inicialização"

    write_start_miner_script
    log_ok "Script de inicialização criado em $START_SCRIPT"

    local marker_start="# >>> verus-termux-miner autostart >>>"
    local marker_end="# <<< verus-termux-miner autostart <<<"

    touch "$BASHRC"
    if grep -qF "$marker_start" "$BASHRC" 2>/dev/null; then
        log_ok "Hook de inicialização automática já presente em ~/.bashrc"
    else
        {
            echo ""
            echo "$marker_start"
            echo "# Ao abrir uma nova sessão interativa do Termux, garante SSH e CCminer rodando"
            echo "pgrep -x sshd >/dev/null 2>&1 || sshd >/dev/null 2>&1"
            echo "[ -x \"$START_SCRIPT\" ] && \"$START_SCRIPT\" >/dev/null 2>&1 &"
            echo "$marker_end"
        } >> "$BASHRC"
        log_ok "Hook adicionado a ~/.bashrc: SSH e CCminer serão verificados/iniciados sempre que uma nova sessão do Termux for aberta"
    fi

    # Também garante que a mineração comece agora, nesta execução
    "$START_SCRIPT" >/dev/null 2>&1 &
    disown 2>/dev/null || true
    sleep 1
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        log_ok "Sessão tmux '$TMUX_SESSION' criada"
    else
        log_warn "Sessão tmux ainda não apareceu — será verificada na etapa de testes finais"
    fi
}

# ---------------------------------------------------------------------------
# [8/8] Verificação final
# ---------------------------------------------------------------------------
run_tests() {
    step "Executando testes"

    local fail=0

    # Termux
    if [ -n "${PREFIX:-}" ]; then log_ok "Termux funcionando"; else log_error "Termux não detectado"; fail=1; fi

    # Arquitetura
    log_ok "Arquitetura detectada: ${ARCH_RAW:-$(uname -m)}"

    # CCminer
    if [ -x "$CCMINER_BIN" ]; then
        log_ok "CCminer existe e é executável"
        if "$CCMINER_BIN" -V >/dev/null 2>&1 || "$CCMINER_BIN" -h >/dev/null 2>&1; then
            log_ok "CCminer inicia corretamente"
        else
            log_error "CCminer não inicia"
            fail=1
        fi
    else
        log_error "CCminer não encontrado em $CCMINER_BIN"
        fail=1
    fi

    # SSH
    if command -v sshd >/dev/null 2>&1; then log_ok "Servidor SSH instalado"; else log_error "Servidor SSH não instalado"; fail=1; fi
    if pgrep -x sshd >/dev/null 2>&1; then log_ok "Servidor SSH rodando"; else log_warn "Servidor SSH não está rodando no momento"; fi

    # tmux
    if command -v tmux >/dev/null 2>&1; then log_ok "tmux instalado"; else log_error "tmux não instalado"; fail=1; fi
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then log_ok "Sessão tmux '$TMUX_SESSION' criada"; else log_warn "Sessão tmux '$TMUX_SESSION' não encontrada"; fi

    # Conectividade com a pool
    if command -v timeout >/dev/null 2>&1; then
        if timeout 6 bash -c "exec 3<>/dev/tcp/$POOL_HOST/$POOL_PORT" 2>/dev/null; then
            log_ok "Conectividade TCP com $POOL_HOST:$POOL_PORT confirmada"
        else
            log_warn "Não foi possível confirmar conectividade TCP com $POOL_HOST:$POOL_PORT (pode ser bloqueio de rede/firewall, ou instabilidade momentânea)"
        fi
    fi

    # Mineração ativa
    sleep 3
    if pgrep -f "$CCMINER_BIN" >/dev/null 2>&1; then
        log_ok "Processo do CCminer está ativo"
    else
        log_warn "Processo do CCminer não foi encontrado ativo no momento da checagem final (ele pode iniciar em background com pequeno atraso — verifique com: tmux attach -t $TMUX_SESSION)"
    fi

    return $fail
}

# ---------------------------------------------------------------------------
# Resumo final
# ---------------------------------------------------------------------------
print_summary() {
    local status_txt="ONLINE"
    pgrep -f "$CCMINER_BIN" >/dev/null 2>&1 || status_txt="VERIFICAR (rode ./install.sh --status)"

    local ssh_status="PARADO"
    pgrep -x sshd >/dev/null 2>&1 && ssh_status="ONLINE"

    cat <<EOF

==================================================
       VERUS MINER - INSTALAÇÃO CONCLUÍDA
==================================================

Status:                 $status_txt

Minerador:               CCminer (Darktron/pre-compiled)
Diretório:               $MINER_DIR
Algoritmo:                $ALGO
Threads:                  $(nproc 2>/dev/null || echo "?") (todos os núcleos)
Pool:                     $POOL_NAME
Servidor:                 $POOL_HOST:$POOL_PORT
Worker:                   $WORKER
Carteira:                 $(mask_wallet "$WALLET")
Arquitetura:              ${ARCH_RAW:-$(uname -m)}

SSH:                      $ssh_status
Usuário:                  ${SSH_USER:-$(whoami)}
IP local:                 ${LOCAL_IP:-desconhecido}
Porta SSH:                ${SSH_PORT:-8022}
Senha:                    $SSH_PASSWORD

Sessão do minerador:      $TMUX_SESSION

Para acessar o console:
    tmux attach -t $TMUX_SESSION

Para sair sem parar o minerador:
    CTRL+B e depois D

Para conectar via SSH:
    ssh ${SSH_USER:-$(whoami)}@${LOCAL_IP:-<IP>} -p ${SSH_PORT:-8022}

Para verificar o status:
    ./install.sh --status

Para executar diagnóstico:
    ./install.sh --diagnostico

==================================================
EOF
}

# ---------------------------------------------------------------------------
# --status
# ---------------------------------------------------------------------------
show_status() {
    banner
    if [ ! -f "$CONFIG_CONF" ]; then
        log_error "Nenhuma instalação encontrada. Rode ./install.sh primeiro."
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$CONFIG_CONF"

    local sshd_config="$PREFIX/etc/ssh/sshd_config"
    local port; port="$(grep -E '^Port ' "$sshd_config" 2>/dev/null | awk '{print $2}')"
    [ -z "$port" ] && port="8022"

    local miner_state="PARADO"
    pgrep -f "$CCMINER_BIN" >/dev/null 2>&1 && miner_state="RODANDO"

    local ssh_state="PARADO"
    pgrep -x sshd >/dev/null 2>&1 && ssh_state="RODANDO"

    local tmux_state="INEXISTENTE"
    tmux has-session -t "$TMUX_SESSION" 2>/dev/null && tmux_state="ATIVA"

    local temp="indisponível (sem acesso a sensores sem root/Termux:API)"

    cat <<EOF

--------------------------------------------------
 STATUS - VERUS TERMUX MINER
--------------------------------------------------
CCminer:        $miner_state
Threads:        $(nproc 2>/dev/null || echo "?")
SSH:            $ssh_state (porta $port)
Pool:           $POOL_NAME ($POOL_HOST:$POOL_PORT)
Worker:         $WORKER
Carteira:       $(mask_wallet "$WALLET")
Sessão tmux:    $tmux_state
Arquitetura:    $(uname -m)
Temperatura:    $temp
--------------------------------------------------
EOF
}

# ---------------------------------------------------------------------------
# --diagnostico
# ---------------------------------------------------------------------------
run_diagnostico() {
    banner
    if [ ! -f "$CONFIG_CONF" ]; then
        log_error "Nenhuma instalação encontrada. Rode ./install.sh primeiro."
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$CONFIG_CONF"
    ARCH_RAW="$(uname -m)"
    STEP_TOTAL=1
    run_tests
    exit $?
}

show_help() {
    cat <<EOF
Verus Termux Miner — instalador

Uso:
  ./install.sh                instala/atualiza tudo (idempotente)
  ./install.sh --status       mostra o status atual, sem alterar nada
  ./install.sh --diagnostico  roda os testes de verificação, sem reinstalar
  ./install.sh --help         mostra esta ajuda
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    case "${1:-}" in
        --status)
            show_status
            exit 0
            ;;
        --diagnostico)
            run_diagnostico
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
    esac

    : > /dev/null  # no-op
    touch "$LOG_FILE"
    banner
    log_raw "===== Nova execução: $(date) ====="

    check_termux
    detect_arch
    install_dependencies
    install_ccminer
    load_or_create_config_conf
    detect_worker_name
    save_config_conf
    generate_ccminer_json
    setup_ssh
    setup_tmux_and_autostart

    run_tests
    print_summary
}

main "$@"
