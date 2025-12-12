#!/bin/bash

###############################################################################
# Script Otimizado iCE40 v2.4
# - CORREÇÃO FINAL no Parser de Utilização (Espaços em branco)
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
PCF_FILE="pins.pcf"
CUSTOM_PCF=false
NUM_SEEDS_TO_TEST=10
SEED=""
TEST_SEEDS=false
TARGET_FREQ=""
USE_DSP=false
USE_ABC2=false
OPTIMIZE_TIMING=false
DEVICE_TYPE="hx"

# Variáveis Opcionais
FLASH_DEVICE=false
GENERATE_PLL=false
PLL_IN_FREQ=""
PLL_OUT_FREQ=""

# =====================
# Verificação de ferramentas
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
        --pcf) PCF_FILE="$2"; CUSTOM_PCF=true; shift 2 ;;
        --flash) FLASH_DEVICE=true; shift ;;
        --pll)
            if [[ -n "$2" && -n "$3" ]]; then
                PLL_IN_FREQ="$2"; PLL_OUT_FREQ="$3"; GENERATE_PLL=true; shift 3
            else
                error "Uso: --pll <in> <out>"; exit 1
            fi
            ;;
        *) DESIGN_FILE="$1"; shift ;;
    esac
done

# =====================
# Menu de Ajuda
# =====================
if [ -z "$DESIGN_FILE" ] || [ ! -f "$DESIGN_FILE" ]; then
    echo -e "${BOLD}Uso:${NC} $0 [opções] <arquivo.v>"
    echo -e "  ${CYAN}--clean${NC}                Limpa build/"
    echo -e "  ${CYAN}--flash${NC}                Grava na FPGA"
    echo -e "  ${CYAN}--pcf <arq>${NC}            Arquivo de pinos"
    echo -e "  ${CYAN}--pll <in> <out>${NC}       Gera PLL (Ex: 12 100)"
    echo -e "  ${CYAN}--test-seeds [N]${NC}       Testa N seeds"
    echo -e "  ${CYAN}--freq <MHz>${NC}           Define Freq Alvo"
    exit 1
fi

# =====================
# Início do Fluxo
# =====================
info "Analisando arquivo Verilog..."
TOP_MODULE=$(yosys -Q -p "read_verilog $DESIGN_FILE; hierarchy -auto-top; stat" 2>&1 | grep 'Top module:' | head -n1 | awk '{print $3}' | sed -e 's/\\//')
TOP_MODULE=$(echo "$TOP_MODULE" | tr -d '\r\n\t ')

[ -z "$TOP_MODULE" ] && { error "Top module não detectado."; exit 1; }

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

# 0. PLL
EXTRA_VERILOG_FILES=""
if [ "$GENERATE_PLL" = true ]; then
    info "0. Gerando PLL ($PLL_IN_FREQ -> $PLL_OUT_FREQ MHz)..."
    icepll -i "$PLL_IN_FREQ" -o "$PLL_OUT_FREQ" -m pll -f "$PLL_FILE" > /dev/null 2>&1
    check_status $? "icepll" ""
    EXTRA_VERILOG_FILES="$PLL_FILE"
    echo -e "   PLL Criado: ${CYAN}$PLL_FILE${NC}"
fi

# 1. Síntese
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

# Auxiliares P&R
run_pnr() {
    local s=$1; local asc=$2; local log=$3; local OPTS=""
    if [ -f "$PCF_FILE" ]; then OPTS="$OPTS --pcf $PCF_FILE"
    elif [ "$CUSTOM_PCF" = true ]; then error "PCF '$PCF_FILE' não existe."; exit 1
    else warn "Sem arquivo PCF. Pinos livres."; fi
    [ -n "$TARGET_FREQ" ] && OPTS="$OPTS --freq $TARGET_FREQ"
    [ "$OPTIMIZE_TIMING" = true ] && OPTS="$OPTS --opt-timing"
    nextpnr-ice40 --$DEVICE --package $PACKAGE --json "$JSON_FILE" $OPTS --seed "$s" --asc "$asc" --log "$log" > /dev/null 2>&1
    return $?
}

get_pnr_fmax() {
    local val=$(grep -F "Max frequency for clock" "$1" | tail -n 1 | awk -F " MHz" '{print $1}' | awk '{print $NF}')
    [ -z "$val" ] && echo "0" || echo "$val"
}

# 2. P&R
info "2. Executando Place & Route..."
if [ "$TEST_SEEDS" = true ]; then
    SEEDS_DIR="$MODULE_BUILD/seeds"; mkdir -p "$SEEDS_DIR"
    BEST_SEED=1; BEST_FMAX=0
    echo -e "   ${BOLD}Testando $NUM_SEEDS_TO_TEST seeds:${NC}"
    for i in $(seq 1 $NUM_SEEDS_TO_TEST); do
        LOG_TMP="$SEEDS_DIR/s$i.log"; ASC_TMP="$SEEDS_DIR/s$i.asc"
        run_pnr "$i" "$ASC_TMP" "$LOG_TMP"
        if [ $? -ne 0 ]; then printf "   Seed %2d: ${RED}FALHA${NC}\n" $i; continue; fi
        CUR_FMAX=$(get_pnr_fmax "$LOG_TMP")
        if (( $(echo "$CUR_FMAX > $BEST_FMAX" | bc -l) )); then
            BEST_FMAX=$CUR_FMAX; BEST_SEED=$i
            printf "   Seed %2d: ${GREEN}%-8s MHz${NC} (Novo Recorde)\n" $i $CUR_FMAX
        else printf "   Seed %2d: %-8s MHz\n" $i $CUR_FMAX; fi
    done
    cp "$SEEDS_DIR/s$BEST_SEED.asc" "$ASC_FILE"; cp "$SEEDS_DIR/s$BEST_SEED.log" "$LOG_FILE"; SEED=$BEST_SEED
else
    [ -z "$SEED" ] && SEED=1
    run_pnr "$SEED" "$ASC_FILE" "$LOG_FILE"
    check_status $? "P&R" "$LOG_FILE"
fi
success "P&R finalizado (Seed: $SEED)."

# 3. Binário e Timing
info "3. Gerando Binário e Relatório..."
icepack "$ASC_FILE" "$BIN_FILE" > /dev/null 2>&1
icetime -d $DEVICE -P $PACKAGE -t -m -r "$RPT_FILE" "$ASC_FILE" > /dev/null 2>&1

# 4. RESUMO
echo ""
echo -e "${BOLD}================ RESUMO DE PERFORMANCE ================${NC}"

# A. Freq P&R
PNR_FMAX_LINE=$(grep -F "Max frequency for clock" "$LOG_FILE" | tail -n 1)
if [ -n "$PNR_FMAX_LINE" ]; then
    CLK_NAME=$(echo "$PNR_FMAX_LINE" | awk -F\' '{print $2}')
    FMAX_VAL=$(echo "$PNR_FMAX_LINE" | awk -F " MHz" '{print $1}' | awk '{print $NF}')
    echo -e "Clock (Estimado P&R):  ${CYAN}$CLK_NAME${NC}"
    echo -e "Frequência (P&R):      ${CYAN}$FMAX_VAL MHz${NC}"
fi

echo ""
echo -e "${BOLD}--- Análise de Caminho Crítico (Static Timing) ---${NC}"

# B. Freq Real (Icetime)
CRITICAL_LINE=$(grep "Total path delay" "$RPT_FILE" | tail -n 1)
if [ -n "$CRITICAL_LINE" ]; then
    echo -e "Pior Caso (Icetime):   ${RED}$CRITICAL_LINE${NC}"
    echo ""
    echo -e "${BOLD}Sequência do Caminho Crítico:${NC}"
    echo -e "${GRAY} (Extraído de $RPT_FILE)${NC}"
    echo "--------------------------------------------------------"
    grep -B 25 "Total path delay" "$RPT_FILE" | head -n -1 | sed 's/^/   /'
    echo "--------------------------------------------------------"
else
    echo -e "${RED}Dados de timing não encontrados.${NC}"
fi

# C. Recursos (Corrigido para ignorar espaços extras)
echo ""
echo -e "${BOLD}Utilização (Recursos / Total %):${NC}"

get_usage() {
    # 1. Busca nome do recurso (ex: ICESTORM_LC)
    # 2. Garante que tem '/' para pegar a linha de contagem
    # 3. Remove prefixos e espaços
    grep -F "$1" "$LOG_FILE" | grep "/" | tail -n 1 | sed 's/.*://' | sed 's/^[ \t]*//'
}

LC_USAGE=$(get_usage "ICESTORM_LC")
RAM_USAGE=$(get_usage "ICESTORM_RAM")

echo -e "   Logic Cells: ${YELLOW}$LC_USAGE${NC}"
echo -e "   Block RAMs:  ${YELLOW}$RAM_USAGE${NC}"
echo ""
echo -e "   Binário:     ${CYAN}$BIN_FILE${NC}"
[ -f "$PCF_FILE" ] && echo -e "   Pinout:      ${CYAN}$PCF_FILE${NC}" || echo -e "   Pinout:      ${YELLOW}Float${NC}"
echo ""

# 5. Flash
if [ "$FLASH_DEVICE" = true ]; then
    echo -e "${BOLD}================ GRAVAÇÃO (ICEPROG) ================${NC}"
    command -v iceprog >/dev/null || { error "iceprog não encontrado."; exit 1; }
    info "Gravando..."
    iceprog "$BIN_FILE" && success "Sucesso!" || error "Falha na gravação."
    echo ""
fi
