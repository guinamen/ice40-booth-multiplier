#!/bin/bash

# ==============================================================================
# Script de Análise de Timing (Versão Blindada)
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

# 1. SÍNTESE
echo -ne "1. Síntese (Yosys)... "
yosys -q -p "read_verilog $DESIGN_FILE; synth_ice40 -top $TOP_MODULE -json $JSON_FILE" > synth.log 2>&1
if [ $? -eq 0 ]; then echo -e "${GREEN}OK${NC}"; else echo -e "${RED}FALHA${NC}"; exit 1; fi

# 2. PLACE & ROUTE
echo -ne "2. P&R (nextpnr)...   "
PCF_OPT=""
if [ -f "$PCF_FILE" ]; then PCF_OPT="--pcf $PCF_FILE"; fi

# Executa nextpnr
nextpnr-ice40 --$DEVICE --package $PACKAGE --json $JSON_FILE  --asc $ASC_FILE --log $LOG_FILE 2>&1
if [ $? -eq 0 ]; then echo -e "${GREEN}OK${NC}"; else echo -e "${RED}FALHA (Veja $LOG_FILE)${NC}"; exit 1; fi

# 3. EXTRAÇÃO DE DADOS (Lógica Simplificada)
echo -e "\n${BLUE}======================================================${NC}"
echo -e "${BLUE}  RELATÓRIO DE PERFORMANCE${NC}"
echo -e "${BLUE}======================================================${NC}"

# -- Extração da Frequência --
# Formato esperado: "Info: Max frequency for clock 'clk...': 109.21 MHz (PASS at ...)"
# Usamos grep para pegar a linha e awk para pegar o campo ANTES de "MHz"
FMAX_LINE=$(grep "Max frequency for clock" $LOG_FILE | tail -n 1)

if [ -n "$FMAX_LINE" ]; then
    # Pega o nome do clock (tudo entre aspas simples)
    CLK_NAME=$(echo "$FMAX_LINE" | awk -F"'" '{print $2}')

    # Pega o valor numérico.
    # Estratégia: Quebra a linha na palavra "MHz" e pega a última palavra da parte anterior.
    FMAX_VAL=$(echo "$FMAX_LINE" | awk -F' MHz' '{print $1}' | awk '{print $NF}')

    echo -e "Clock Domain:      ${YELLOW}$CLK_NAME${NC}"
    echo -e "Frequência Máxima: ${GREEN}$FMAX_VAL MHz${NC}"
else
    echo -e "${RED}Erro: Não foi possível ler a frequência do log.${NC}"
fi

# -- Extração de Recursos --
echo -e "\n${BLUE}  UTILIZAÇÃO DE RECURSOS${NC}"
echo -e "${BLUE}------------------------------------------------------${NC}"

# Função para extrair dados no formato "xxx/ yyy z%"
get_resource_data() {
    # Procura a linha com a TAG, pega a parte depois dos dois pontos, remove espaços extras
    LINE=$(grep "$1" $LOG_FILE | grep "/" | tail -n 1)
    if [ -n "$LINE" ]; then
        # Remove o prefixo até o primeiro dois pontos
        CLEAN=$(echo "$LINE" | cut -d':' -f2-)
        echo "$CLEAN"
    else
        echo "N/A"
    fi
}

LC_DATA=$(get_resource_data "ICESTORM_LC")
RAM_DATA=$(get_resource_data "ICESTORM_RAM")
IO_DATA=$(get_resource_data "SB_IO")

echo -e "Logic Cells (LCs): ${YELLOW}$LC_DATA${NC}"
echo -e "Block RAMs:        ${YELLOW}$RAM_DATA${NC}"
echo -e "IO Pins:           ${YELLOW}$IO_DATA${NC}"

# 4. CAMINHO CRÍTICO
echo -e "\n${BLUE}  CAMINHO CRÍTICO (icetime)${NC}"
echo -e "${BLUE}------------------------------------------------------${NC}"

icetime -d $DEVICE -P $PACKAGE -t -r $RPT_FILE $ASC_FILE > /dev/null 2>&1

if [ -f "$RPT_FILE" ]; then
    # Mostra as 15 linhas finais onde o caminho crítico geralmente aparece
    grep -B 15 "Total path delay" $RPT_FILE
else
    echo "Relatório icetime não gerado."
fi

echo -e "\n${BLUE}======================================================${NC}"
