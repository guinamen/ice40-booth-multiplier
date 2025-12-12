#!/bin/bash

###############################################################################
# Script Otimizado iCE40 v2.2 (FIXED)
# - Correção de erro de sintaxe (EOF/Quotes)
# - Help atualizado
# - Funcionalidades: Build, Timing, Seed Test, Flash, PLL Gen
###############################################################################

# Configurações de Shell
set -o pipefail

# =====================
# Definição de Cores
# =====================
RED='\033[1;31m'      # Vermelho Brilhante
GREEN='\033[1;32m'    # Verde Brilhante
YELLOW='\033[1;33m'   # Amarelo
BLUE='\033[0;34m'     # Azul
CYAN='\033[0;36m'     # Ciano
BOLD='\033[1m'
GRAY='\033[0;90m'
NC='\033[0m'          # No Color

# =====================
# Funções de Log
# =====================
info()    { echo -e "${BLUE}==>${NC} ${BOLD}$1${NC}"; }
success() { echo -e "${GREEN}==>${NC} ${BOLD}$1${NC}"; }
warn()    { echo -e "${YELLOW}==> AVISO:${NC} $1"; }
error()   { echo -e "${RED}==> ERRO:${NC} $1"; }

check_status() {
    if [ $1 -ne 0 ]; then
        error "Falha na execução ($2)."
        if [ -f "$3" ]; then
            echo -e "${YELLOW}--- Últimas 20 linhas do log ($3) ---${NC}"
            tail -n 20 "$3"
        fi
        exit 1
    fi
}

# =====================
# Configurações padrão
# =====================
DEVICE="hx8k"
PACKAGE="ct256"
PCF_FILE="pins.pcf"    # Padrão
CUSTOM_PCF=false
NUM_SEEDS_TO_TEST=10
SEED=""
TEST_SEEDS=false
TARGET_FREQ=""
USE_DSP=false
USE_ABC2=false
OPTIMIZE_TIMING=false
DEVICE_TYPE="hx"

# Novas Variáveis
FLASH_DEVICE=false
GENERATE_PLL=false
PLL_IN_FREQ=""
PLL_OUT_FREQ=""

# =====================
# Verificação de ferramentas essenciais
# =====================
for tool in yosys nextpnr-ice40 icetime icepack; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        error "Ferramenta essencial '$tool' não encontrada no PATH."
        exit 1
    fi
done

# =====================
# Parsing de argumentos
# =====================
DESIGN_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            info "Limpando diretório build/..."
            rm -rf build
            success "Limpeza concluída."
            exit 0
            ;;
        --seed) SEED="$2"; shift 2 ;;
        --test-seeds)
            TEST_SEEDS=true
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                NUM_SEEDS_TO_TEST="$2"; shift 2
            else
                shift
            fi
            ;;
        --freq) TARGET_FREQ="$2"; shift 2 ;;
        --dsp) USE_DSP=true; shift ;;
        --abc2) USE_ABC2=true; shift ;;
        --opt-timing) OPTIMIZE_TIMING=true; shift ;;
        --device-type) DEVICE_TYPE="$2"; shift 2 ;;
        
        # Novas flags
        --pcf) 
            PCF_FILE="$2"
            CUSTOM_PCF=true
            shift 2 
            ;;
        --flash) 
            FLASH_DEVICE=true
            shift 
            ;;
        --pll)
            if [[ -n "$2" && -n "$3" ]]; then
                PLL_IN_FREQ="$2"
                PLL_OUT_FREQ="$3"
                GENERATE_PLL=true
                shift 3
            else
                error "Uso incorreto de --pll. Exemplo: --pll 16 100"
                exit 1
            fi
            ;;
        
        *) DESIGN_FILE="$1"; shift ;;
    esac
done

# =====================
# Menu de Ajuda (Help)
# =====================
if [ -z "$DESIGN_FILE" ] || [ ! -f "$DESIGN_FILE" ]; then
    echo -e "${BOLD}Uso:${NC} $0 [opções] <arquivo.v>"
    echo ""
    echo -e "${BOLD}Opções Gerais:${NC}"
    echo -e "  ${CYAN}--clean${NC}                Limpa o diretório 'build/' e sai"
    echo -e "  ${CYAN}--flash${NC}                Grava o bitstream na FPGA após sucesso (iceprog)"
    echo -e "  ${CYAN}--device-type <type>${NC}   Tipo do dispositivo (hx, lp, u). Padrão: hx"
    
    echo ""
    echo -e "${BOLD}Hardware e Pinos:${NC}"
    echo -e "  ${CYAN}--pcf <arquivo>${NC}        Define arquivo de pinos (Padrão: pins.pcf)"
    echo -e "  ${CYAN}--pll <in> <out>${NC}       Gera módulo PLL via icepll (Ex: 12MHz -> 100MHz)"

    echo ""
    echo -e "${BOLD}Otimização e Performance:${NC}"
    echo -e "  ${CYAN}--seed <N>${NC}             Usa uma seed específica para o P&R"
    echo -e "  ${CYAN}--test-seeds [N]${NC}       Testa N seeds (padrão: 10) e escolhe a melhor"
    echo -e "  ${CYAN}--freq <MHz>${NC}           Define frequência alvo (constraint de timing)"
    echo -e "  ${CYAN}--dsp${NC}                  Habilita uso de blocos DSP (Multiplicadores)"
    echo -e "  ${CYAN}--abc2${NC}                 Habilita otimização lógica ABC2 (pode reduzir área)"
    echo -e "  ${CYAN}--opt-timing${NC}           Otimização extra de timing no P&R (lento)"

    echo ""
    echo -e "${BOLD}Exemplos:${NC}"
    echo -e "  $0 top.v                             ${GRAY}# Build simples${NC}"
    echo -e "  $0 --flash top.v                     ${GRAY}# Build + Upload${NC}"
    echo -e "  $0 --test-seeds 20 top.v             ${GRAY}# Testa 20 seeds p/ melhor performance${NC}"
    echo -e "  $0 --pll 16 100 --flash top.v        ${GRAY}# Gera PLL 100MHz e grava${NC}"
    echo -e "  $0 --pcf board.pcf --dsp top.v       ${GRAY}# Pinos customizados + DSP${NC}"
    exit 1
fi

# =====================
# Detecção automática do TOP
# =====================
info "Analisando arquivo Verilog..."
# Correção: Uso de aspas simples para o sed dentro do subshell para evitar escape incorreto
TOP_MODULE=$(yosys -Q -p "read_verilog $DESIGN_FILE; hierarchy -auto-top; stat" 2>&1 | grep 'Top module:' | head -n1 | awk '{print $3}' | sed -e 's/\\//')
TOP_MODULE=$(echo "$TOP_MODULE" | tr -d '\r\n\t ')

[ -z "$TOP_MODULE" ] && { error "Top module não detectado."; exit 1; }

# =====================
# Diretórios
# =====================
BUILD_ROOT="build"
MODULE_BUILD="$BUILD_ROOT/$TOP_MODULE"
mkdir -p "$MODULE_BUILD"

JSON_FILE="$MODULE_BUILD/design.json"
ASC_FILE="$MODULE_BUILD/design.asc"
LOG_FILE="$MODULE_BUILD/pnr.log"
RPT_FILE="$MODULE_BUILD/timing.rpt"
SYNTH_LOG="$MODULE_BUILD/synth.log"
BIN_FILE="$MODULE_BUILD/output.bin"
PLL_FILE="$MODULE_BUILD/pll.v"

echo -e "   Módulo Top: ${CYAN}$TOP_MODULE${NC}"

# =====================
# 0. Geração de PLL (Opcional)
# =====================
EXTRA_VERILOG_FILES=""

if [ "$GENERATE_PLL" = true ]; then
    info "0. Gerando PLL ($PLL_IN_FREQ MHz -> $PLL_OUT_FREQ MHz)..."
    if ! command -v icepll >/dev/null 2>&1; then
        error "Ferramenta 'icepll' não encontrada."
        exit 1
    fi

    icepll -i "$PLL_IN_FREQ" -o "$PLL_OUT_FREQ" -m pll -f "$PLL_FILE" > /dev/null 2>&1
    check_status $? "icepll generation" ""
    
    EXTRA_VERILOG_FILES="$PLL_FILE"
    echo -e "   PLL Gerado: ${CYAN}$PLL_FILE${NC}"
    echo -e "   Instancie como: ${YELLOW}pll my_pll (.clock_in(clk), .clock_out(clk_fast), .locked(lock));${NC}"
fi

# =====================
# 1. Síntese
# =====================
info "1. Executando Síntese (Yosys)..."
SYNTH_FLAGS="-abc9 -device $DEVICE_TYPE"
[ "$USE_DSP" = true ] && SYNTH_FLAGS="$SYNTH_FLAGS -dsp"
[ "$USE_ABC2" = true ] && SYNTH_FLAGS="$SYNTH_FLAGS -abc2"

FILES_TO_READ="$DESIGN_FILE $EXTRA_VERILOG_FILES"

yosys -Q -l "$SYNTH_LOG" <<EOF > /dev/null 2>&1
read_verilog $FILES_TO_READ
hierarchy -check -top $TOP_MODULE
proc; opt -full; fsm; fsm_opt; memory -nomap; opt -full
flatten -noscopeinfo
synth_ice40 $SYNTH_FLAGS -top $TOP_MODULE -json $JSON_FILE
EOF
check_status $? "Síntese" "$SYNTH_LOG"
success "Síntese concluída."

# =====================
# Funções Auxiliares P&R
# =====================
run_pnr() {
    local s=$1; local asc=$2; local log=$3
    local OPTS=""
    
    if [ -f "$PCF_FILE" ]; then
        OPTS="$OPTS --pcf $PCF_FILE"
    elif [ "$CUSTOM_PCF" = true ]; then
        error "Arquivo PCF '$PCF_FILE' não encontrado."
        exit 1
    else
        warn "Nenhum arquivo .pcf encontrado. Roteando sem pin constraints."
    fi

    [ -n "$TARGET_FREQ" ] && OPTS="$OPTS --freq $TARGET_FREQ"
    [ "$OPTIMIZE_TIMING" = true ] && OPTS="$OPTS --opt-timing"
    
    nextpnr-ice40 --$DEVICE --package $PACKAGE --json "$JSON_FILE" \
        $OPTS --seed "$s" --asc "$asc" --log "$log" > /dev/null 2>&1
    return $?
}

get_pnr_fmax() {
    # Correção: Uso de aspas simples escapadas para o awk
    local val=$(grep -F "Max frequency for clock" "$1" | tail -n 1 | awk -F " MHz" '{print $1}' | awk '{print $NF}')
    [ -z "$val" ] && echo "0" || echo "$val"
}

# =====================
# 2. Place & Route
# =====================
info "2. Executando Place & Route..."

if [ "$TEST_SEEDS" = true ]; then
    SEEDS_DIR="$MODULE_BUILD/seeds"
    mkdir -p "$SEEDS_DIR"
    BEST_SEED=1; BEST_FMAX=0
    
    echo -e "   ${BOLD}Testando $NUM_SEEDS_TO_TEST seeds:${NC}"
    for i in $(seq 1 $NUM_SEEDS_TO_TEST); do
        LOG_TMP="$SEEDS_DIR/s$i.log"
        ASC_TMP="$SEEDS_DIR/s$i.asc"
        run_pnr "$i" "$ASC_TMP" "$LOG_TMP"
        if [ $? -ne 0 ]; then
             printf "   Seed %2d: ${RED}FALHA${NC}\n" $i
             continue
        fi
        CUR_FMAX=$(get_pnr_fmax "$LOG_TMP")
        if (( $(echo "$CUR_FMAX > $BEST_FMAX" | bc -l) )); then
            BEST_FMAX=$CUR_FMAX; BEST_SEED=$i
            printf "   Seed %2d: ${GREEN}%-8s MHz${NC} (Novo Recorde)\n" $i $CUR_FMAX
        else
            printf "   Seed %2d: %-8s MHz\n" $i $CUR_FMAX
        fi
    done
    cp "$SEEDS_DIR/s$BEST_SEED.asc" "$ASC_FILE"
    cp "$SEEDS_DIR/s$BEST_SEED.log" "$LOG_FILE"
    SEED=$BEST_SEED
else
    [ -z "$SEED" ] && SEED=1
    run_pnr "$SEED" "$ASC_FILE" "$LOG_FILE"
    check_status $? "P&R" "$LOG_FILE"
fi
success "P&R finalizado (Seed: $SEED)."

# =====================
# 3. Empacotamento e Timing
# =====================
info "3. Gerando Binário e Relatório..."
icepack "$ASC_FILE" "$BIN_FILE" > /dev/null 2>&1
icetime -d $DEVICE -P $PACKAGE -t -m -r "$RPT_FILE" "$ASC_FILE" > /dev/null 2>&1

# =====================
# 4. RESUMO FINAL
# =====================
echo ""
echo -e "${BOLD}================ RESUMO DE PERFORMANCE ================${NC}"

# --- A. Frequência estimada pelo Place & Route ---
PNR_FMAX_LINE=$(grep -F "Max frequency for clock" "$LOG_FILE" | tail -n 1)
if [ -n "$PNR_FMAX_LINE" ]; then
    # Correção Crítica: Mudança no AWK para evitar aspas aninhadas problemáticas
    CLK_NAME=$(echo "$PNR_FMAX_LINE" | awk -F\' '{print $2}')
    FMAX_VAL=$(echo "$PNR_FMAX_LINE" | awk -F " MHz" '{print $1}' | awk '{print $NF}')
    echo -e "Clock (Estimado P&R):  ${CYAN}$CLK_NAME${NC}"
    echo -e "Frequência (P&R):      ${CYAN}$FMAX_VAL MHz${NC}"
fi

echo ""
echo -e "${BOLD}--- Análise de Caminho Crítico (Static Timing) ---${NC}"

# --- B. Frequência Real e Delay (Em Vermelho) ---
CRITICAL_LINE=$(grep "Total path delay" "$RPT_FILE" | tail -n 1)
if [ -n "$CRITICAL_LINE" ]; then
    echo -e "Pior Caso (Icetime):   ${RED}$CRITICAL_LINE${NC}"
    
    # --- C. Sequência do Caminho Crítico ---
    echo ""
    echo -e "${BOLD}Sequência do Caminho Crítico:${NC}"
    echo -e "${GRAY} (Extraído de $RPT_FILE)${NC}"
    echo "--------------------------------------------------------"
    grep -B 25 "Total path delay" "$RPT_FILE" | head -n -1 | sed 's/^/   /'
    echo "--------------------------------------------------------"
else
    echo -e "${RED}Dados de timing não encontrados no relatório.${NC}"
fi

# --- D. Recursos e Porcentagem ---
echo ""
echo -e "${BOLD}Utilização (Recursos / Total %):${NC}"

get_usage() {
    # Extração robusta
    grep -F "$1" "$LOG_FILE" | tail -n 1 | sed 's/.*://' | tr -s ' ' | sed 's/^[ \t]*//'
}

LC_USAGE=$(get_usage "ICESTORM_LC")
RAM_USAGE=$(get_usage "ICESTORM_RAM")

echo -e "   Logic Cells: ${YELLOW}$LC_USAGE${NC}"
echo -e "   Block RAMs:  ${YELLOW}$RAM_USAGE${NC}"
echo ""
echo -e "   Binário:     ${CYAN}$BIN_FILE${NC}"
if [ -f "$PCF_FILE" ]; then
    echo -e "   Pinout:      ${CYAN}$PCF_FILE${NC}"
else
    echo -e "   Pinout:      ${YELLOW}Nenhum (Float)${NC}"
fi
echo ""

# =====================
# 5. Gravação Automática (FLASH)
# =====================
if [ "$FLASH_DEVICE" = true ]; then
    echo -e "${BOLD}================ GRAVAÇÃO (ICEPROG) ================${NC}"
    
    if ! command -v iceprog >/dev/null 2>&1; then
        error "Ferramenta 'iceprog' não encontrada. Instale para usar --flash."
        exit 1
    fi

    info "Gravando bitstream na FPGA..."
    iceprog "$BIN_FILE"
    
    if [ $? -eq 0 ]; then
        success "Gravação concluída com sucesso!"
    else
        error "Falha na gravação."
    fi
    echo ""
fi
