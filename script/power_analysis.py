#!/usr/bin/env python3
"""
Generic FPGA Power Analysis Tool for iCE40
===========================================
Analisa consumo de potência de qualquer design sintetizado para iCE40
através de switching activity extraído de simulação VCD.

Uso:
    python3 power_analysis.py [opções]
"""

import re
import sys
import json
import argparse
from pathlib import Path
from dataclasses import dataclass
from typing import Dict, List, Tuple, Optional
from collections import defaultdict

@dataclass
class ICE40PowerModel:
    """Modelo de potência parametrizado por dispositivo e condições"""
    
    device: str = 'hx8k'
    temp_c: float = 25.0
    voltage_v: float = 1.2
    
    # Tabela de potência estática base (mW @ 25°C, 1.2V)
    STATIC_POWER = {
        'hx1k': 15.0, 'hx4k': 25.0, 'hx8k': 35.0,
        'lp1k': 8.0,  'lp4k': 12.0, 'lp8k': 18.0,
        'up5k': 10.0,
    }
    
    # Capacidades de cada dispositivo (Logic Cells)
    DEVICE_CAPACITY = {
        'hx1k': 1280, 'hx4k': 3520, 'hx8k': 7680,
        'lp1k': 1280, 'lp4k': 3520, 'lp8k': 7680,
        'up5k': 5280,
    }
    
    def __post_init__(self):
        self.device = self.device.lower()
        if self.device not in self.STATIC_POWER:
            print(f"⚠️  Dispositivo '{self.device}' desconhecido, usando hx8k como base")
            self.device = 'hx8k'
    
    @property
    def static_power_mw(self) -> float:
        """Potência estática com correção de temperatura e tensão"""
        base = self.STATIC_POWER[self.device]
        temp_factor = 2.0 ** ((self.temp_c - 25.0) / 12.0)
        voltage_factor = (self.voltage_v / 1.2) ** 2
        return base * temp_factor * voltage_factor
    
    @property
    def lc_dynamic_nj(self) -> float:
        """Energia por toggle de Logic Cell (nJ)"""
        base = 0.12 if self.device.startswith('lp') else 0.15
        return base * (self.voltage_v / 1.2) ** 2
    
    @property
    def ff_dynamic_nj(self) -> float:
        """Energia por toggle de Flip-Flop (nJ)"""
        base = 0.08 if self.device.startswith('lp') else 0.10
        return base * (self.voltage_v / 1.2) ** 2
    
    @property
    def io_dynamic_nj(self) -> float:
        """Energia por toggle de I/O (nJ) - Estimativa para carga de 10pF"""
        return 2.5 * (self.voltage_v / 1.2) ** 2
    
    @property
    def clock_tree_mw_per_mhz(self) -> float:
        """Potência da árvore de clock por MHz"""
        base = 0.06 if self.device.startswith('lp') else 0.08
        return base * (self.voltage_v / 1.2) ** 2
    
    @property
    def total_capacity(self) -> int:
        return self.DEVICE_CAPACITY.get(self.device, 7680)


class VCDSwitchingAnalyzer:
    """Analisa arquivo VCD para extrair switching activity"""
    
    def __init__(self, vcd_path: str, verbose: bool = False):
        self.vcd_path = Path(vcd_path)
        self.verbose = verbose
        self.timescale = 1e-9
        self.total_time = 0
        self.clock_period = 0
        self.id_to_name: Dict[str, str] = {}
        
    def parse_vcd(self) -> Dict[str, int]:
        if not self.vcd_path.exists():
            print(f"❌ Arquivo VCD não encontrado: {self.vcd_path}")
            return {}
        
        print(f"📂 Lendo VCD: {self.vcd_path}")
        with open(self.vcd_path, 'r') as f:
            content = f.read()
        
        # Timescale
        ts_match = re.search(r'\$timescale\s+(\d+)(\w+)', content)
        if ts_match:
            value, unit = int(ts_match.group(1)), ts_match.group(2)
            units = {'s': 1, 'ms': 1e-3, 'us': 1e-6, 'ns': 1e-9, 'ps': 1e-12}
            self.timescale = value * units.get(unit, 1e-9)
        
        # Signal Map
        for match in re.finditer(r'\$var\s+\w+\s+\d+\s+(\S+)\s+(\S+)\s+\$end', content):
            var_id, name = match.group(1), match.group(2)
            self.id_to_name[var_id] = name
        
        self.clock_period = self._detect_clock_period(content)
        return self._count_toggles(content)
    
    def _detect_clock_period(self, content: str) -> float:
        clock_ids = [vid for vid, name in self.id_to_name.items() 
                     if re.match(r'^(clk|clock|sys_clk)$', name, re.IGNORECASE)]
        if not clock_ids: return 0.0
        
        cid = clock_ids[0]
        times = [int(m.group(1)) for m in re.finditer(rf'#(\d+)\s*\n[01]{re.escape(cid)}', content)]
        if len(times) >= 3:
            periods = [times[i+2] - times[i] for i in range(len(times)-2)]
            avg_p = (sum(periods) / len(periods)) * self.timescale
            if self.verbose: print(f"   Clock detectado: {1e-6/avg_p:.2f} MHz")
            return avg_p
        return 0.0

    def _count_toggles(self, content: str) -> Dict[str, int]:
        toggles = {}
        states = {}
        current_time = 0
        
        for line in content.splitlines():
            line = line.strip()
            if not line: continue
            if line.startswith('#'):
                current_time = int(line[1:])
                self.total_time = max(self.total_time, current_time)
                continue
            
            # Formatos: "0!" ou "b1101 !" ou "x!"
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
    def __init__(self, synth_log: Optional[str] = None):
        self.synth_log = Path(synth_log) if synth_log else None
    
    def extract(self) -> Dict:
        if not self.synth_log or not self.synth_log.exists():
            return {'logic_cells': 100, 'flip_flops': 100, 'io_cells': 10, 'gb': 1}
        
        print(f"📊 Analisando síntese: {self.synth_log}")
        content = self.synth_log.read_text()
        return {
            'logic_cells': sum(int(n) for n in re.findall(r'SB_LUT4:\s+(\d+)', content)),
            'flip_flops': sum(int(n) for n in re.findall(r'SB_DFF\w*:\s+(\d+)', content)),
            'io_cells': sum(int(n) for n in re.findall(r'SB_IO:\s+(\d+)', content)),
            'global_buffers': sum(int(n) for n in re.findall(r'SB_GB:\s+(\d+)', content)) or 1
        }

class GenericPowerEstimator:
    def __init__(self, clock_mhz: float, stats: Dict, model: ICE40PowerModel, verbose: bool):
        self.clock_mhz = clock_mhz
        self.stats = stats
        self.model = model
        self.verbose = verbose

    def calculate(self, vcd_toggles: Dict[str, int], sim_time_s: float) -> str:
        if self.clock_mhz == 0 and sim_time_s > 0:
            self.clock_mhz = 1e-6 / (sim_time_s / max(1, sum(vcd_toggles.values())/len(vcd_toggles) if vcd_toggles else 1))
        
        static = self.model.static_power_mw
        clock_tree = self.model.clock_tree_mw_per_mhz * self.clock_mhz * self.stats.get('global_buffers', 1)
        
        breakdown = {'logic': 0.0, 'flip_flops': 0.0, 'io': 0.0, 'routing': 0.0}
        
        if not vcd_toggles:
            # Estimativa estatística (sem VCD)
            freq_hz = self.clock_mhz * 1e6
            activity = 0.15 # 15% toggle rate padrão
            breakdown['logic'] = self.stats['logic_cells'] * freq_hz * activity * self.model.lc_dynamic_nj * 1e-9
            breakdown['flip_flops'] = self.stats['flip_flops'] * freq_hz * activity * self.model.ff_dynamic_nj * 1e-9
            breakdown['io'] = self.stats['io_cells'] * freq_hz * activity * self.model.io_dynamic_nj * 1e-9
        else:
            for sig, count in vcd_toggles.items():
                rate = count / sim_time_s
                if any(x in sig.lower() for x in ['reg', 'ff', 'dff']):
                    breakdown['flip_flops'] += rate * self.model.ff_dynamic_nj * 1e-9
                elif len(sig) <= 3 or 'pin' in sig.lower():
                    breakdown['io'] += rate * self.model.io_dynamic_nj * 1e-9
                else:
                    breakdown['logic'] += rate * self.model.lc_dynamic_nj * 1e-9
        
        breakdown['routing'] = (breakdown['logic'] + breakdown['flip_flops']) * 0.4
        dynamic_mw = sum(breakdown.values()) * 1000
        total_mw = static + clock_tree + dynamic_mw
        
        return self._format_report(static, clock_tree, dynamic_mw, total_mw, breakdown, vcd_toggles, sim_time_s)

    def _format_report(self, static, clk, dyn, total, breakdown, vcd, sim_t):
        r = [
            "="*70, "GENERIC FPGA POWER ANALYSIS - Lattice iCE40", "="*70,
            f"Device:             {self.model.device.upper()}",
            f"Temperature:        {self.model.temp_c}°C",
            f"Core Voltage:       {self.model.voltage_v} V",
            f"Clock Frequency:    {self.clock_mhz:.2f} MHz", "",
            "Design Utilization:",
            f"  Logic Cells:      {self.stats['logic_cells']:4d} / {self.model.total_capacity}",
            f"  Flip-Flops:       {self.stats['flip_flops']:4d}",
            f"  I/O Cells:        {self.stats['io_cells']:4d}", "",
            f"📍 Static Power:            {static:6.2f} mW",
            f"🕐 Clock Tree Power:        {clk:6.2f} mW"
        ]
        
        if vcd:
            r.append(f"📊 VCD Analysis:            {len(vcd)} signals, {sim_t*1e6:.2f} µs")
        else:
            r.append("⚠️  VCD Analysis:            Not available (conservative estimate)")
            
        r.extend(["", "⚡ Dynamic Power Breakdown:"])
        for k, v in sorted(breakdown.items(), key=lambda x: -x[1]):
            val = v * 1000
            pct = (val/dyn*100) if dyn > 0 else 0
            r.append(f"   {k.replace('_',' ').title():15s} {val:8.2f} mW ({pct:5.1f}%)")
        
        r.extend(["-"*70, f"🔋 TOTAL POWER:             {total:6.2f} mW", "-"*70])
        return "\n".join(r)

def main():
    parser = argparse.ArgumentParser(description='Generic iCE40 Power Analysis Tool')
    parser.add_argument('--vcd', type=str, help='VCD file')
    parser.add_argument('--synth', type=str, help='Synthesis log')
    parser.add_argument('--freq', type=float, default=0, help='Freq MHz')
    parser.add_argument('--device', type=str, default='hx8k', help='Device (up5k, hx8k...)')
    parser.add_argument('--temp', type=float, default=25.0, help='Temp C')
    parser.add_argument('--voltage', type=float, default=1.2, help='Voltage V')
    parser.add_argument('--output', type=str, default='power_report.txt', help='Output file')
    parser.add_argument('--verbose', action='store_true')
    
    args = parser.parse_args()
    
    print("🔌 Generic iCE40 Power Analysis Tool\n" + "="*70 + "\n")
    
    # Auto-detect
    vcd_f = args.vcd or next(Path('.').rglob('*.vcd'), None)
    synth_f = args.synth or next(Path('.').rglob('*.log'), None)
    
    stats = DesignStatsExtractor(str(synth_f) if synth_f else None).extract()
    model = ICE40PowerModel(device=args.device, temp_c=args.temp, voltage_v=args.voltage)
    
    toggles = {}
    sim_time = 0
    if vcd_f:
        analyzer = VCDSwitchingAnalyzer(str(vcd_f), args.verbose)
        toggles = analyzer.parse_vcd()
        sim_time = analyzer.total_time * analyzer.timescale
        if args.freq == 0 and analyzer.clock_period > 0:
            args.freq = 1e-6 / analyzer.clock_period

    estimator = GenericPowerEstimator(args.freq, stats, model, args.verbose)
    report = estimator.calculate(toggles, sim_time)
    
    print(report)
    with open(args.output, 'w') as f:
        f.write(report)
    print(f"\n📝 Relatório salvo em: {args.output}")

if __name__ == "__main__":
    main()
