#!/usr/bin/env python3
import re
import sys
import json
import argparse
from pathlib import Path
from dataclasses import dataclass
from typing import Dict, List, Tuple, Optional

@dataclass
class ICE40PowerModel:
    device: str = 'up5k'
    temp_c: float = 25.0
    voltage_v: float = 1.2
    
    STATIC_POWER = {'hx1k': 15.0, 'hx4k': 25.0, 'hx8k': 35.0, 'lp1k': 8.0, 'lp4k': 12.0, 'lp8k': 18.0, 'up5k': 10.0}
    DEVICE_CAPACITY = {'hx1k': 1280, 'hx4k': 3520, 'hx8k': 7680, 'lp1k': 1280, 'lp4k': 3520, 'lp8k': 7680, 'up5k': 5280}
    
    @property
    def static_power_mw(self) -> float:
        base = self.STATIC_POWER.get(self.device.lower(), 10.0)
        temp_factor = 2.0 ** ((self.temp_c - 25.0) / 12.0)
        return base * temp_factor * (self.voltage_v / 1.2)**2

    @property
    def lc_dynamic_nj(self) -> float: return 0.12 * (self.voltage_v / 1.2)**2
    @property
    def ff_dynamic_nj(self) -> float: return 0.08 * (self.voltage_v / 1.2)**2
    @property
    def io_dynamic_nj(self) -> float: return 1.5 * (self.voltage_v / 1.2)**2
    @property
    def clock_tree_mw_per_mhz(self) -> float: return 0.05 * (self.voltage_v / 1.2)**2

class VCDSwitchingAnalyzer:
    def __init__(self, vcd_path: str):
        self.vcd_path = Path(vcd_path)
        self.timescale = 1e-9
        self.total_time = 0
        self.id_to_name = {}

    def parse(self) -> Dict[str, int]:
        if not self.vcd_path.exists(): return {}
        content = self.vcd_path.read_text()
        
        # Timescale
        ts = re.search(r'\$timescale\s+(\d+)(\w+)', content)
        if ts:
            unit_map = {'s':1, 'ms':1e-3, 'us':1e-6, 'ns':1e-9, 'ps':1e-12}
            self.timescale = int(ts.group(1)) * unit_map.get(ts.group(2), 1e-9)

        # Map IDs
        for m in re.finditer(r'\$var\s+\w+\s+\d+\s+(\S+)\s+(\S+)\s+\$end', content):
            self.id_to_name[m.group(1)] = m.group(2)

        toggles = {}
        states = {}
        for line in content.splitlines():
            if line.startswith('#'):
                self.total_time = max(self.total_time, int(line[1:]))
            elif line and line[0] in '01xzbB':
                m = re.match(r'^([01xz])(\S+)$', line) or re.match(r'^[bB]([01xz]+)\s+(\S+)$', line)
                if m:
                    val, sid = m.groups()
                    if sid in self.id_to_name:
                        name = self.id_to_name[sid]
                        if states.get(name) != val and 'x' not in val:
                            toggles[name] = toggles.get(name, 0) + 1
                            states[name] = val
        return toggles

class DesignStatsExtractor:
    def __init__(self, synth_log: str):
        self.path = Path(synth_log)
    
    def extract(self) -> Dict:
        res = {'logic_cells': 0, 'flip_flops': 0, 'io_cells': 0, 'global_buffers': 1}
        if not self.path.exists(): return res
        txt = self.path.read_text()
        # Busca no sumário do Yosys (estatísticas de células)
        res['logic_cells'] = sum(int(n) for n in re.findall(r'SB_LUT4\s*[:\.]*\s*(\d+)', txt))
        res['flip_flops'] = sum(int(n) for n in re.findall(r'SB_DFF\w*\s*[:\.]*\s*(\d+)', txt))
        res['io_cells'] = sum(int(n) for n in re.findall(r'SB_IO\s*[:\.]*\s*(\d+)', txt))
        # Se falhou, tenta buscar pelo reporte de recursos final
        if res['logic_cells'] == 0:
            m = re.search(r'LCs\s*[:\.]*\s*(\d+)', txt)
            if m: res['logic_cells'] = int(m.group(1))
        return res

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--vcd')
    parser.add_argument('--synth')
    parser.add_argument('--device', default='up5k')
    parser.add_argument('--temp', type=float, default=25)
    parser.add_argument('--freq', type=float, default=0)
    args = parser.parse_args()

    stats = DesignStatsExtractor(args.synth).extract()
    vcd = VCDSwitchingAnalyzer(args.vcd)
    toggles = vcd.parse()
    sim_t = vcd.total_time * vcd.timescale
    
    # Se freq não informada, usa 100MHz como fallback ou tenta detectar
    freq = args.freq if args.freq > 0 else 100.0
    model = ICE40PowerModel(device=args.device, temp_c=args.temp)
    
    # Cálculos
    static = model.static_power_mw
    clk_pwr = model.clock_tree_mw_per_mhz * freq * stats['global_buffers']
    
    breakdown = {'logic': 0.0, 'flip_flops': 0.0, 'io': 0.0, 'routing': 0.0}
    for sig, count in toggles.items():
        rate = count / sim_t
        sig_l = sig.lower()
        # Melhoria na heurística: Só considera IO se for pino real do top level (ex: led, pino, etc)
        if any(x in sig_l for x in ['pino', 'pad', 'io_', 'port_']):
            breakdown['io'] += rate * model.io_dynamic_nj * 1e-9
        elif 'reg' in sig_l or 'ff' in sig_l:
            breakdown['flip_flops'] += rate * model.ff_dynamic_nj * 1e-9
        else:
            breakdown['logic'] += rate * model.lc_dynamic_nj * 1e-9
    
    breakdown['routing'] = (breakdown['logic'] + breakdown['flip_flops']) * 0.4
    dyn = sum(breakdown.values()) * 1000
    total = static + clk_pwr + dyn

    print("="*70)
    print(f"DEVICE: {args.device.upper()} | FREQ: {freq} MHz | TEMP: {args.temp} C")
    print("-"*70)
    print(f"Logic Cells: {stats['logic_cells']} | FFs: {stats['flip_flops']}")
    print(f"Static Power:  {static:8.2f} mW")
    print(f"Clock Power:   {clk_pwr:8.2f} mW")
    print(f"Dynamic Power: {dyn:8.2f} mW")
    print(f"TOTAL POWER:   {total:8.2f} mW")
    print("="*70)

if __name__ == "__main__":
    main()
