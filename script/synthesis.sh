#!/bin/bash

# ==============================================================================
# Script de Análise de Timing (Versão Blindada + Fix Scopeinfo)
# ==============================================================================

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configurações
DESIGN_FILE=$1
TOP_MODULE="booth_radix8_multiplier"
DEVICE="hx8k"
PACKAGE="ct256"
JSON_FILE="design.json"
ASC_FILE="design.asc"
LOG_FILE="pnr.log"
PCF_FILE="pins.pcf"
RPT_FILE="timing_report.txt"

# Verificação de entrada
if [ -z "$DESIGN_FILE" ]; then
    echo -e "${RED}Erro: Nenhum arquivo de design especificado.${NC}"
    echo "Uso: $0 <arquivo.v> [top_module]"
    exit 1
fi

if [ ! -z "$2" ]; then
    TOP_MODULE=$2
fi

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}  Análise de Timing: ${NC}${YELLOW}$TOP_MODULE${NC}"
echo -e "${BLUE}======================================================${NC}"

# 1. SÍNTESE – Fluxo robusto que elimina '$scopeinfo'
echo -ne "1. Síntese (Yosys)... "

yosys -q -l synth.log <<EOF
read_verilog $DESIGN_FILE
hierarchy -check -top $TOP_MODULE

# Normalização e limpeza completa
proc
opt -full
#flatten -noscopeinfo
#opt_clean -purge

fsm
fsm_opt

memory -nomap
opt -full
#techmap
#opt
#opt_clean -purge
flatten -noscopeinfo
stat
# Síntese final para iCE40
synth_ice40 -abc9 -top $TOP_MODULE -json $JSON_FILE
EOF

if [ $? -eq 0 ]; then echo -e "${GREEN}OK${NC}"; else echo -e "${RED}FALHA${NC}"; exit 1; fi

# 2. PLACE & ROUTE
echo -ne "2. P&R (nextpnr)...   "
PCF_OPT=""
if [ -f "$PCF_FILE" ]; then PCF_OPT="--pcf $PCF_FILE"; fi

nextpnr-ice40 --$DEVICE --package $PACKAGE --json $JSON_FILE $PCF_OPT --asc $ASC_FILE --log $LOG_FILE 2>&1
if [ $? -eq 0 ]; then echo -e "${GREEN}OK${NC}"; else echo -e "${RED}FALHA (Veja $LOG_FILE)${NC}"; exit 1; fi

# 3. EXTRAÇÃO DE DADOS
echo -e "\n${BLUE}======================================================${NC}"
echo -e "${BLUE}  RELATÓRIO DE PERFORMANCE${NC}"
echo -e "${BLUE}======================================================${NC}"

# Extração da frequência
FMAX_LINE=$(grep "Max frequency for clock" $LOG_FILE | tail -n 1)

if [ -n "$FMAX_LINE" ]; then
    CLK_NAME=$(echo "$FMAX_LINE" | awk -F"'" '{print $2}')
    FMAX_VAL=$(echo "$FMAX_LINE" | awk -F' MHz' '{print $1}' | awk '{print $NF}')
    echo -e "Clock Domain:      ${YELLOW}$CLK_NAME${NC}"
    echo -e "Frequência Máxima: ${GREEN}$FMAX_VAL MHz${NC}"
else
    echo -e "${RED}Erro: Não foi possível ler a frequência do log.${NC}"
fi

# Recurso
echo -e "\n${BLUE}  UTILIZAÇÃO DE RECURSOS${NC}"
echo -e "${BLUE}------------------------------------------------------${NC}"

get_resource_data() {
    LINE=$(grep "$1" $LOG_FILE | grep "/" | tail -n 1)
    if [ -n "$LINE" ]; then
        CLEAN=$(echo "$LINE" | cut -d':' -f2-)
        echo "$CLEAN"
    else
        echo "N/A"
    fi
}

echo -e "Logic Cells (LCs): ${YELLOW}$(get_resource_data "ICESTORM_LC")${NC}"
echo -e "Block RAMs:        ${YELLOW}$(get_resource_data "ICESTORM_RAM")${NC}"
echo -e "IO Pins:           ${YELLOW}$(get_resource_data "SB_IO")${NC}"

# 4. Caminho crítico
echo -e "\n${BLUE}  CAMINHO CRÍTICO (icetime)${NC}"
echo -e "${BLUE}------------------------------------------------------${NC}"

icetime -d $DEVICE -P $PACKAGE -t -r $RPT_FILE $ASC_FILE > /dev/null 2>&1

if [ -f "$RPT_FILE" ]; then
    grep -B 15 "Total path delay" $RPT_FILE
else
    echo "Relatório icetime não gerado."
fi

echo -e "\n${BLUE}======================================================${NC}"

