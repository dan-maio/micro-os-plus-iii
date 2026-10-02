#!/usr/bin/env python3
"""
Generates publication-quality SVG diagrams for the micro-os-plus-iii technical architecture document.
"""

import os
import sys

DIAGRAMS_DIR = "/home/dan/Documents/Work/micro-os-plus/micro-os-plus-iii/docs/diagrams"
os.makedirs(DIAGRAMS_DIR, exist_ok=True)

def generate_repo_topology():
    svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 360" width="100%" height="100%">
  <defs>
    <style>
      .title { font-family: 'Source Sans 3', 'Segoe UI', sans-serif; font-weight: 700; font-size: 14px; fill: #0f172a; }
      .subtitle { font-family: 'Source Sans 3', 'Segoe UI', sans-serif; font-size: 11.5px; fill: #475569; }
      .tag { font-family: 'Hack Nerd Font', monospace; font-size: 10px; font-weight: 600; fill: #0284c7; }
      .box { rx: 8; stroke-width: 1.5; filter: drop-shadow(0 2px 4px rgba(0,0,0,0.04)); }
      .arrow { stroke: #0284c7; stroke-width: 1.8; fill: none; }
      .arrow-shared { stroke: #64748b; stroke-width: 1.8; fill: none; stroke-dasharray: 4 3; }
    </style>
    <marker id="arrowhead" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto">
      <polygon points="0 0, 8 3, 0 6" fill="#0284c7" />
    </marker>
    <marker id="arrowhead-gray" markerWidth="8" markerHeight="6" refX="7" refY="3" orient="auto">
      <polygon points="0 0, 8 3, 0 6" fill="#64748b" />
    </marker>
  </defs>

  <!-- Background Canvas -->
  <rect width="100%" height="100%" fill="#ffffff" />

  <!-- Top: Kernel -->
  <g transform="translate(240, 20)">
    <rect width="320" height="75" fill="#f0f9ff" stroke="#0284c7" class="box" />
    <text x="160" y="28" text-anchor="middle" class="title">micro-os-plus-iii-smp</text>
    <text x="160" y="46" text-anchor="middle" class="subtitle">Portable C++ Kernel &amp; Common Tests</text>
    <rect x="75" y="54" width="170" height="15" rx="3" fill="#e0f2fe" />
    <text x="160" y="65" text-anchor="middle" class="tag">ZERO MACHINE INSTRUCTIONS</text>
  </g>

  <!-- Connectors from Kernel to Ports -->
  <path d="M 400 95 L 400 130 M 400 130 L 90 130 L 90 160" class="arrow" marker-end="url(#arrowhead)" />
  <path d="M 400 95 L 400 130 M 400 130 L 245 130 L 245 160" class="arrow" marker-end="url(#arrowhead)" />
  <path d="M 400 95 L 400 130 M 400 130 L 400 160" class="arrow" marker-end="url(#arrowhead)" />
  <path d="M 400 95 L 400 130 M 400 130 L 555 130 L 555 160" class="arrow" marker-end="url(#arrowhead)" />
  <path d="M 400 95 L 400 130 M 400 130 L 710 130 L 710 160" class="arrow" marker-end="url(#arrowhead)" />

  <!-- Mid: 5 Architecture Ports -->
  <!-- Port 1: POSIX -->
  <g transform="translate(20, 160)">
    <rect width="140" height="70" fill="#f8fafc" stroke="#cbd5e1" class="box" />
    <text x="70" y="25" text-anchor="middle" class="title" font-size="12.5">...-posix-arch</text>
    <text x="70" y="42" text-anchor="middle" class="subtitle" font-size="10.5">POSIX Host</text>
    <text x="70" y="58" text-anchor="middle" class="tag" font-size="9.5">pthread = CPU</text>
  </g>

  <!-- Port 2: Cortex-M -->
  <g transform="translate(175, 160)">
    <rect width="140" height="70" fill="#f8fafc" stroke="#cbd5e1" class="box" />
    <text x="70" y="25" text-anchor="middle" class="title" font-size="12.5">...-cortexm</text>
    <text x="70" y="42" text-anchor="middle" class="subtitle" font-size="10.5">M0 / M3 / M4 / M33</text>
    <text x="70" y="58" text-anchor="middle" class="tag" font-size="9.5">RP2350 SIO</text>
  </g>

  <!-- Port 3: AArch32 -->
  <g transform="translate(330, 160)">
    <rect width="140" height="70" fill="#f8fafc" stroke="#cbd5e1" class="box" />
    <text x="70" y="25" text-anchor="middle" class="title" font-size="12.5">...-aarch32</text>
    <text x="70" y="42" text-anchor="middle" class="subtitle" font-size="10.5">ARMv7-A / 32-bit</text>
    <text x="70" y="58" text-anchor="middle" class="tag" font-size="9.5">BCM2837 / RK3506</text>
  </g>

  <!-- Port 4: AArch64 -->
  <g transform="translate(485, 160)">
    <rect width="140" height="70" fill="#f8fafc" stroke="#cbd5e1" class="box" />
    <text x="70" y="25" text-anchor="middle" class="title" font-size="12.5">...-aarch64</text>
    <text x="70" y="42" text-anchor="middle" class="subtitle" font-size="10.5">ARMv8-A / 64-bit</text>
    <text x="70" y="58" text-anchor="middle" class="tag" font-size="9.5">RPi 3B / Zero 2W</text>
  </g>

  <!-- Port 5: RISC-V -->
  <g transform="translate(640, 160)">
    <rect width="140" height="70" fill="#f8fafc" stroke="#cbd5e1" class="box" />
    <text x="70" y="25" text-anchor="middle" class="title" font-size="12.5">...-riscv</text>
    <text x="70" y="42" text-anchor="middle" class="subtitle" font-size="10.5">RV32 / RV64</text>
    <text x="70" y="58" text-anchor="middle" class="tag" font-size="9.5">Hart / CLINT</text>
  </g>

  <!-- Connector to Devices -->
  <path d="M 400 230 L 400 270 M 555 230 L 555 270 M 400 270 L 475 270 L 475 285" class="arrow-shared" marker-end="url(#arrowhead-gray)" />

  <!-- Bottom: Devices -->
  <g transform="translate(325, 285)">
    <rect width="300" height="55" fill="#fefce8" stroke="#eab308" class="box" />
    <text x="150" y="23" text-anchor="middle" class="title" font-size="13">micro-os-plus-iii-devices</text>
    <text x="150" y="41" text-anchor="middle" class="subtitle" font-size="10.5">Shared Drivers (DWC2 USB, SD/MMC, FatFs, SoC Mailbox)</text>
  </g>
</svg>'''
    with open(os.path.join(DIAGRAMS_DIR, "repo_topology.svg"), "w") as f:
        f.write(svg)

def generate_smp_hazard():
    svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 260" width="100%" height="100%">
  <defs>
    <style>
      .h-title { font-family: 'Source Sans 3', 'Segoe UI', sans-serif; font-weight: 700; font-size: 13.5px; }
      .code { font-family: 'Hack Nerd Font', monospace; font-size: 11px; fill: #1e293b; }
      .comment { font-family: 'Hack Nerd Font', monospace; font-size: 10px; font-style: italic; fill: #64748b; }
      .alert { font-family: 'Source Sans 3', 'Segoe UI', sans-serif; font-weight: 700; font-size: 12px; fill: #dc2626; }
      .box { rx: 6; stroke-width: 1.5; }
    </style>
  </defs>

  <rect width="100%" height="100%" fill="#ffffff" />

  <!-- Core 0 Block -->
  <g transform="translate(30, 20)">
    <rect width="340" height="150" fill="#f8fafc" stroke="#0284c7" class="box" />
    <rect width="340" height="28" fill="#e0f2fe" rx="6" />
    <text x="170" y="19" text-anchor="middle" class="h-title" fill="#0369a1">CPU Core 0 (Interrupts Disabled via CPSID)</text>
    <text x="15" y="55" class="code">thread_list.link(node_A);</text>
    <text x="15" y="75" class="code">node_A-&gt;next = head;</text>
    <text x="15" y="95" class="comment">// Preempted across bus by Core 1!</text>
    <text x="15" y="115" class="code">head-&gt;prev = node_A; <tspan class="alert">&lt;-- CORRUPTS MEMORY</tspan></text>
    <text x="15" y="140" class="comment">CPSID only protects Core 0 from local ISRs!</text>
  </g>

  <!-- Core 1 Block -->
  <g transform="translate(430, 20)">
    <rect width="340" height="150" fill="#f8fafc" stroke="#ea580c" class="box" />
    <rect width="340" height="28" fill="#ffedd5" rx="6" />
    <text x="170" y="19" text-anchor="middle" class="h-title" fill="#c2410c">CPU Core 1 (Interrupts Active &amp; Running)</text>
    <text x="15" y="55" class="code">thread_list.unlink_head();</text>
    <text x="15" y="75" class="code">auto item = head;</text>
    <text x="15" y="95" class="code">head = item-&gt;next; <tspan class="alert">&lt;-- READS PARTIAL WRITE</tspan></text>
    <text x="15" y="115" class="comment">// Deletes node_A while Core 0 is writing!</text>
    <text x="15" y="140" class="comment">Core 1 ignores Core 0's interrupt mask!</text>
  </g>

  <!-- Shared Memory Interconnect -->
  <g transform="translate(180, 195)">
    <rect width="440" height="45" fill="#fef2f2" stroke="#dc2626" stroke-dasharray="4 2" class="box" />
    <text x="220" y="22" text-anchor="middle" class="alert">💥 CONCURRENT CROSS-CORE RACE ON SHARED SYSTEM RAM</text>
    <text x="220" y="37" text-anchor="middle" font-family="'Source Sans 3', sans-serif" font-size="10.5" fill="#991b1b">Result: Pointer corruption, invalid linked lists, and kernel hard panic.</text>
  </g>

  <!-- Flash Lines connecting to Memory -->
  <line x1="200" y1="170" x2="260" y2="195" stroke="#dc2626" stroke-width="1.8" />
  <line x1="600" y1="170" x2="540" y2="195" stroke="#dc2626" stroke-width="1.8" />
</svg>'''
    with open(os.path.join(DIAGRAMS_DIR, "smp_hazard.svg"), "w") as f:
        f.write(svg)

def generate_context_switch_protocol():
    svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 820 400" width="100%" height="100%">
  <defs>
    <style>
      .step-num { font-family: 'Hack Nerd Font', monospace; font-size: 11px; font-weight: bold; fill: #ffffff; }
      .step-title { font-family: 'Source Sans 3', sans-serif; font-size: 12px; font-weight: 700; fill: #0f172a; }
      .step-desc { font-family: 'Hack Nerd Font', monospace; font-size: 10px; fill: #334155; }
      .box-core0 { fill: #f0fdf4; stroke: #16a34a; rx: 6; stroke-width: 1.5; }
      .box-core1 { fill: #f8fafc; stroke: #64748b; rx: 6; stroke-width: 1.5; }
      .gate-box { fill: #fef3c7; stroke: #d97706; rx: 6; stroke-width: 1.5; }
    </style>
    <marker id="arrow" markerWidth="7" markerHeight="5" refX="6" refY="2.5" orient="auto">
      <polygon points="0 0, 7 2.5, 0 5" fill="#0284c7" />
    </marker>
    <marker id="arrow-green" markerWidth="7" markerHeight="5" refX="6" refY="2.5" orient="auto">
      <polygon points="0 0, 7 2.5, 0 5" fill="#16a34a" />
    </marker>
  </defs>

  <rect width="100%" height="100%" fill="#ffffff" />

  <!-- Left Column: Core 0 Timeline -->
  <text x="210" y="25" text-anchor="middle" font-family="'Source Sans 3', sans-serif" font-weight="700" font-size="14" fill="#15803d">Core 0 (Switching Out Old Thread 'OldT' to 'NT')</text>

  <!-- Step 1 -->
  <g transform="translate(30, 45)">
    <rect width="360" height="52" class="box-core0" />
    <circle cx="20" cy="26" r="11" fill="#16a34a" />
    <text x="20" y="30" text-anchor="middle" class="step-num">1</text>
    <text x="40" y="20" class="step-title">Select Next Thread (NT) &amp; Claim</text>
    <text x="40" y="38" class="step-desc">Under _smp_klock: NT-&gt;stack_ptr = nullptr (CLAIMED)</text>
  </g>

  <!-- Step 2 -->
  <g transform="translate(30, 110)">
    <rect width="360" height="52" class="box-core0" />
    <circle cx="20" cy="26" r="11" fill="#16a34a" />
    <text x="20" y="30" class="step-num">2</text>
    <text x="40" y="20" class="step-title">Stage Outgoing Context</text>
    <text x="40" y="38" class="step-desc">_port_ctx_pending[0] = OldT</text>
  </g>

  <!-- Step 3 -->
  <g transform="translate(30, 175)">
    <rect width="360" height="52" class="box-core0" />
    <circle cx="20" cy="26" r="11" fill="#16a34a" />
    <text x="20" y="30" class="step-num">3</text>
    <text x="40" y="20" class="step-title">Save Hardware Registers to OldT Stack</text>
    <text x="40" y="38" class="step-desc">Push {r4-r11, s16-s31} to OldT Stack Memory</text>
  </g>

  <!-- Step 4 -->
  <g transform="translate(30, 240)">
    <rect width="360" height="52" class="box-core0" />
    <circle cx="20" cy="26" r="11" fill="#16a34a" />
    <text x="20" y="30" class="step-num">4</text>
    <text x="40" y="20" class="step-title">Hardware Stack Pointer Switch</text>
    <text x="40" y="38" class="step-desc">SP moves from OldT to NT Stack; Release _smp_klock</text>
  </g>

  <!-- Step 5 -->
  <g transform="translate(30, 305)">
    <rect width="360" height="65" fill="#f0f9ff" stroke="#0284c7" rx="6" stroke-width="1.8" />
    <circle cx="20" cy="32" r="11" fill="#0284c7" />
    <text x="20" y="36" text-anchor="middle" class="step-num">5</text>
    <text x="40" y="22" class="step-title" fill="#0369a1">Publish Phase (NOW ON NT STACK!)</text>
    <text x="40" y="40" class="step-desc">OldT-&gt;stack_ptr = saved_sp (Atomic Release Store)</text>
    <text x="40" y="55" class="step-desc">_port_ctx_pending[0] = nullptr</text>
  </g>

  <!-- Vertical Connectors Core 0 -->
  <path d="M 210 97 L 210 110 M 210 162 L 210 175 M 210 227 L 210 240 M 210 292 L 210 305" stroke="#16a34a" stroke-width="1.8" marker-end="url(#arrow-green)" />

  <!-- Right Column: Core 1 Scheduler Gate -->
  <text x="610" y="25" text-anchor="middle" font-family="'Source Sans 3', sans-serif" font-weight="700" font-size="14" fill="#334155">Core 1 (Scanning Ready List for Work)</text>

  <g transform="translate(440, 85)">
    <rect width="350" height="95" class="box-core1" />
    <text x="175" y="22" text-anchor="middle" class="step-title" fill="#475569">Candidate Inspection (during Steps 1–4)</text>
    <text x="20" y="45" class="step-desc">Inspects 'OldT':</text>
    <text x="30" y="63" class="step-desc" fill="#dc2626">✗ OldT-&gt;stack_ptr == nullptr (CLAIMED!)</text>
    <text x="30" y="81" class="step-desc" fill="#b45309">Core 1 BLOCKED from dispatching OldT</text>
  </g>

  <path d="M 440 132 L 400 132" stroke="#dc2626" stroke-width="1.5" stroke-dasharray="3 3" />

  <g transform="translate(440, 275)">
    <rect width="350" height="95" class="gate-box" />
    <text x="175" y="22" text-anchor="middle" class="step-title" fill="#b45309">Safe Dispatch Gate (after Step 5 Publish)</text>
    <text x="20" y="45" class="step-desc">Inspects 'OldT':</text>
    <text x="30" y="63" class="step-desc" fill="#15803d">✓ OldT-&gt;stack_ptr != nullptr</text>
    <text x="30" y="81" class="step-desc" fill="#15803d">✓ OldT-&gt;state != running (SAFE TO DISPATCH!)</text>
  </g>

  <!-- Connect Step 5 to Gate -->
  <path d="M 390 337 L 440 337" stroke="#0284c7" stroke-width="2" marker-end="url(#arrow)" />
</svg>'''
    with open(os.path.join(DIAGRAMS_DIR, "context_switch_protocol.svg"), "w") as f:
        f.write(svg)

def generate_scheduler_topology():
    svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 300" width="100%" height="100%">
  <defs>
    <style>
      .t-header { font-family: 'Source Sans 3', sans-serif; font-weight: 700; font-size: 13.5px; fill: #0f172a; }
      .t-body { font-family: 'Hack Nerd Font', monospace; font-size: 11px; fill: #1e293b; }
      .t-desc { font-family: 'Source Sans 3', sans-serif; font-size: 10.5px; fill: #64748b; }
      .core-box { fill: #f8fafc; stroke: #0284c7; rx: 6; stroke-width: 1.5; filter: drop-shadow(0 2px 4px rgba(0,0,0,0.03)); }
      .queue-box { fill: #f0f9ff; stroke: #0369a1; rx: 8; stroke-width: 1.5; }
    </style>
    <marker id="s-arrow" markerWidth="7" markerHeight="5" refX="6" refY="2.5" orient="auto">
      <polygon points="0 0, 7 2.5, 0 5" fill="#0284c7" />
    </marker>
  </defs>

  <rect width="100%" height="100%" fill="#ffffff" />

  <!-- Global Ready List -->
  <g transform="translate(100, 20)">
    <rect width="600" height="70" class="queue-box" />
    <text x="300" y="24" text-anchor="middle" class="t-header" fill="#0369a1">Global Multi-Core Priority Ready List (os::rtos::scheduler::ready_list_)</text>
    <!-- Nodes -->
    <rect x="30" y="36" width="120" height="24" rx="4" fill="#e0f2fe" stroke="#0284c7" />
    <text x="90" y="52" text-anchor="middle" class="t-body" font-weight="bold">Prio 10: Th_A</text>

    <text x="165" y="52" text-anchor="middle" font-size="14" fill="#0284c7">→</text>

    <rect x="180" y="36" width="120" height="24" rx="4" fill="#e0f2fe" stroke="#0284c7" />
    <text x="240" y="52" text-anchor="middle" class="t-body" font-weight="bold">Prio 7: Th_B</text>

    <text x="315" y="52" text-anchor="middle" font-size="14" fill="#0284c7">→</text>

    <rect x="330" y="36" width="120" height="24" rx="4" fill="#e0f2fe" stroke="#0284c7" />
    <text x="390" y="52" text-anchor="middle" class="t-body" font-weight="bold">Prio 5: Th_C</text>

    <text x="465" y="52" text-anchor="middle" font-size="14" fill="#0284c7">→</text>

    <rect x="480" y="36" width="90" height="24" rx="4" fill="#f1f5f9" stroke="#94a3b8" />
    <text x="525" y="52" text-anchor="middle" class="t-body" fill="#64748b">nullptr</text>
  </g>

  <!-- Distribution Lines -->
  <path d="M 400 90 L 400 130 M 400 130 L 105 130 L 105 160" stroke="#0284c7" stroke-width="1.8" marker-end="url(#s-arrow)" />
  <path d="M 400 90 L 400 130 M 400 130 L 305 130 L 305 160" stroke="#0284c7" stroke-width="1.8" marker-end="url(#s-arrow)" />
  <path d="M 400 90 L 400 130 M 400 130 L 495 130 L 495 160" stroke="#0284c7" stroke-width="1.8" marker-end="url(#s-arrow)" />
  <path d="M 400 90 L 400 130 M 400 130 L 695 130 L 695 160" stroke="#0284c7" stroke-width="1.8" marker-end="url(#s-arrow)" />

  <!-- 4 Cores -->
  <!-- Core 0 -->
  <g transform="translate(25, 160)">
    <rect width="160" height="115" class="core-box" />
    <rect width="160" height="26" fill="#e0f2fe" rx="6" />
    <text x="80" y="18" text-anchor="middle" class="t-header" font-size="12">CPU Core 0</text>
    <text x="15" y="48" class="t-desc">current_thread_[0]:</text>
    <rect x="15" y="56" width="130" height="22" rx="3" fill="#ecfdf5" stroke="#10b981" />
    <text x="80" y="71" text-anchor="middle" class="t-body" font-weight="bold" fill="#047857">Th_A (Prio 10)</text>
    <text x="80" y="98" text-anchor="middle" class="t-desc">idle: idle_core[0]</text>
  </g>

  <!-- Core 1 -->
  <g transform="translate(225, 160)">
    <rect width="160" height="115" class="core-box" />
    <rect width="160" height="26" fill="#e0f2fe" rx="6" />
    <text x="80" y="18" text-anchor="middle" class="t-header" font-size="12">CPU Core 1</text>
    <text x="15" y="48" class="t-desc">current_thread_[1]:</text>
    <rect x="15" y="56" width="130" height="22" rx="3" fill="#ecfdf5" stroke="#10b981" />
    <text x="80" y="71" text-anchor="middle" class="t-body" font-weight="bold" fill="#047857">Th_B (Prio 7)</text>
    <text x="80" y="98" text-anchor="middle" class="t-desc">idle: idle_core[1]</text>
  </g>

  <!-- Core 2 -->
  <g transform="translate(415, 160)">
    <rect width="160" height="115" class="core-box" />
    <rect width="160" height="26" fill="#e0f2fe" rx="6" />
    <text x="80" y="18" text-anchor="middle" class="t-header" font-size="12">CPU Core 2</text>
    <text x="15" y="48" class="t-desc">current_thread_[2]:</text>
    <rect x="15" y="56" width="130" height="22" rx="3" fill="#ecfdf5" stroke="#10b981" />
    <text x="80" y="71" text-anchor="middle" class="t-body" font-weight="bold" fill="#047857">Th_C (Prio 5)</text>
    <text x="80" y="98" text-anchor="middle" class="t-desc">idle: idle_core[2]</text>
  </g>

  <!-- Core 3 -->
  <g transform="translate(615, 160)">
    <rect width="160" height="115" class="core-box" />
    <rect width="160" height="26" fill="#f1f5f9" rx="6" />
    <text x="80" y="18" text-anchor="middle" class="t-header" font-size="12" fill="#64748b">CPU Core 3</text>
    <text x="15" y="48" class="t-desc">current_thread_[3]:</text>
    <rect x="15" y="56" width="130" height="22" rx="3" fill="#f8fafc" stroke="#94a3b8" />
    <text x="80" y="71" text-anchor="middle" class="t-body" fill="#64748b">idle_core[3]</text>
    <text x="80" y="98" text-anchor="middle" class="t-desc" fill="#d97706">WFI / Sigsuspend</text>
  </g>
</svg>'''
    with open(os.path.join(DIAGRAMS_DIR, "scheduler_topology.svg"), "w") as f:
        f.write(svg)

def generate_intrusive_comparison():
    svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 280" width="100%" height="100%">
  <defs>
    <style>
      .h-main { font-family: 'Source Sans 3', sans-serif; font-weight: 700; font-size: 13.5px; }
      .label { font-family: 'Source Sans 3', sans-serif; font-size: 11px; font-weight: 600; fill: #0f172a; }
      .field { font-family: 'Hack Nerd Font', monospace; font-size: 10px; fill: #1e293b; }
      .box-std { fill: #fef2f2; stroke: #ef4444; rx: 5; stroke-width: 1.2; }
      .box-intr { fill: #f0fdf4; stroke: #16a34a; rx: 5; stroke-width: 1.2; }
      .box-payload { fill: #f8fafc; stroke: #64748b; rx: 5; stroke-width: 1.2; }
    </style>
    <marker id="m-red" markerWidth="6" markerHeight="4" refX="5" refY="2" orient="auto">
      <polygon points="0 0, 6 2, 0 4" fill="#ef4444" />
    </marker>
    <marker id="m-green" markerWidth="6" markerHeight="4" refX="5" refY="2" orient="auto">
      <polygon points="0 0, 6 2, 0 4" fill="#16a34a" />
    </marker>
  </defs>

  <rect width="100%" height="100%" fill="#ffffff" />

  <!-- Top: Non-Intrusive -->
  <text x="20" y="25" class="h-main" fill="#dc2626">Non-Intrusive Container (std::list&lt;Thread&gt;) — Extra Dynamic Heap Allocations</text>

  <!-- Node 1 -->
  <g transform="translate(40, 40)">
    <rect width="110" height="40" class="box-std" />
    <text x="55" y="16" text-anchor="middle" class="label">std::list node</text>
    <text x="55" y="31" text-anchor="middle" class="field">[next, prev, *val]</text>
  </g>
  <path d="M 150 60 L 190 60" stroke="#ef4444" stroke-width="1.5" marker-end="url(#m-red)" />
  <path d="M 95 80 L 95 105" stroke="#64748b" stroke-width="1.5" stroke-dasharray="2 2" />

  <!-- Node 2 -->
  <g transform="translate(200, 40)">
    <rect width="110" height="40" class="box-std" />
    <text x="55" y="16" text-anchor="middle" class="label">std::list node</text>
    <text x="55" y="31" text-anchor="middle" class="field">[next, prev, *val]</text>
  </g>
  <path d="M 255 80 L 255 105" stroke="#64748b" stroke-width="1.5" stroke-dasharray="2 2" />

  <!-- Payload Objects in Heap -->
  <g transform="translate(40, 105)">
    <rect width="110" height="30" class="box-payload" />
    <text x="55" y="20" text-anchor="middle" class="field">Thread Object A</text>
  </g>
  <g transform="translate(200, 105)">
    <rect width="110" height="30" class="box-payload" />
    <text x="55" y="20" text-anchor="middle" class="field">Thread Object B</text>
  </g>
  <text x="350" y="65" font-family="'Source Sans 3', sans-serif" font-size="11" fill="#b91c1c">⚠️ Allocation failure during link() can throw or panic in ISR</text>

  <!-- Divider -->
  <line x1="20" y1="155" x2="780" y2="155" stroke="#e2e8f0" stroke-width="1" />

  <!-- Bottom: Intrusive -->
  <text x="20" y="180" class="h-main" fill="#15803d">Intrusive Container (os::utils::double_list) — Zero Dynamic Memory Allocations</text>

  <!-- Intrusive Thread A -->
  <g transform="translate(40, 195)">
    <rect width="210" height="65" class="box-intr" />
    <text x="105" y="18" text-anchor="middle" class="label" fill="#15803d">rtos::thread 'Thread A'</text>
    <rect x="15" y="28" width="180" height="26" rx="3" fill="#ffffff" stroke="#16a34a" />
    <text x="105" y="45" text-anchor="middle" class="field">double_list_links [next, prev]</text>
  </g>

  <!-- Connector -->
  <path d="M 250 227 L 310 227" stroke="#16a34a" stroke-width="1.8" marker-end="url(#m-green)" />

  <!-- Intrusive Thread B -->
  <g transform="translate(320, 195)">
    <rect width="210" height="65" class="box-intr" />
    <text x="105" y="18" text-anchor="middle" class="label" fill="#15803d">rtos::thread 'Thread B'</text>
    <rect x="15" y="28" width="180" height="26" rx="3" fill="#ffffff" stroke="#16a34a" />
    <text x="105" y="45" text-anchor="middle" class="field">double_list_links [next, prev]</text>
  </g>

  <text x="560" y="222" font-family="'Source Sans 3', sans-serif" font-size="11" fill="#15803d">✓ Guaranteed O(1) insertion &amp; removal</text>
  <text x="560" y="238" font-family="'Source Sans 3', sans-serif" font-size="11" fill="#15803d">✓ Zero dynamic memory allocation</text>
</svg>'''
    with open(os.path.join(DIAGRAMS_DIR, "intrusive_comparison.svg"), "w") as f:
        f.write(svg)

def generate_ports_matrix():
    svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 290" width="100%" height="100%">
  <defs>
    <style>
      .p-title { font-family: 'Source Sans 3', sans-serif; font-weight: 700; font-size: 12.5px; fill: #0f172a; }
      .p-cat { font-family: 'Source Sans 3', sans-serif; font-weight: 600; font-size: 10px; fill: #64748b; }
      .p-val { font-family: 'Hack Nerd Font', monospace; font-size: 10px; fill: #0369a1; }
      .port-card { rx: 6; stroke-width: 1.2; filter: drop-shadow(0 2px 4px rgba(0,0,0,0.03)); }
    </style>
  </defs>

  <rect width="100%" height="100%" fill="#ffffff" />

  <!-- Column 1: POSIX -->
  <g transform="translate(15, 20)">
    <rect width="145" height="250" fill="#f8fafc" stroke="#0284c7" class="port-card" />
    <rect width="145" height="28" fill="#e0f2fe" rx="6" />
    <text x="72.5" y="19" text-anchor="middle" class="p-title" fill="#0369a1">POSIX Host</text>
    
    <text x="10" y="48" class="p-cat">CPU MODEL</text>
    <text x="10" y="63" class="p-val">1 pthread = 1 CPU</text>

    <text x="10" y="88" class="p-cat">INTERRUPTS</text>
    <text x="10" y="103" class="p-val">pthread_sigmask</text>

    <text x="10" y="128" class="p-cat">TICK TIMER</text>
    <text x="10" y="143" class="p-val">timer_create TID</text>

    <text x="10" y="168" class="p-cat">IPI SIGNAL</text>
    <text x="10" y="183" class="p-val">pthread_kill</text>

    <text x="10" y="208" class="p-cat">CONTEXT</text>
    <text x="10" y="223" class="p-val">ucontext_t</text>
  </g>

  <!-- Column 2: Cortex-M -->
  <g transform="translate(170, 20)">
    <rect width="145" height="250" fill="#f8fafc" stroke="#0284c7" class="port-card" />
    <rect width="145" height="28" fill="#e0f2fe" rx="6" />
    <text x="72.5" y="19" text-anchor="middle" class="p-title" fill="#0369a1">Cortex-M (RP2350)</text>

    <text x="10" y="48" class="p-cat">CPU MODEL</text>
    <text x="10" y="63" class="p-val">2x Cortex-M33</text>

    <text x="10" y="88" class="p-cat">INTERRUPTS</text>
    <text x="10" y="103" class="p-val">PRIMASK / BASEPRI</text>

    <text x="10" y="128" class="p-cat">LOCK MECHANISM</text>
    <text x="10" y="143" class="p-val">SIO Spinlock 0</text>

    <text x="10" y="168" class="p-cat">IPI SIGNAL</text>
    <text x="10" y="183" class="p-val">SIO FIFO IRQ 25</text>

    <text x="10" y="208" class="p-cat">CONTEXT</text>
    <text x="10" y="223" class="p-val">PendSV + Lazy FP</text>
  </g>

  <!-- Column 3: AArch32 -->
  <g transform="translate(325, 20)">
    <rect width="145" height="250" fill="#f8fafc" stroke="#0284c7" class="port-card" />
    <rect width="145" height="28" fill="#e0f2fe" rx="6" />
    <text x="72.5" y="19" text-anchor="middle" class="p-title" fill="#0369a1">ARMv7-A / A32</text>

    <text x="10" y="48" class="p-cat">CPU MODEL</text>
    <text x="10" y="63" class="p-val">BCM2837 / RK3506</text>

    <text x="10" y="88" class="p-cat">INTERRUPTS</text>
    <text x="10" y="103" class="p-val">CPSID / CPSIE</text>

    <text x="10" y="128" class="p-cat">LOCK MECHANISM</text>
    <text x="10" y="143" class="p-val">LDREX / STREX</text>

    <text x="10" y="168" class="p-cat">IPI SIGNAL</text>
    <text x="10" y="183" class="p-val">GIC SGI / Mailbox</text>

    <text x="10" y="208" class="p-cat">CONTEXT</text>
    <text x="10" y="223" class="p-val">Software Frame</text>
  </g>

  <!-- Column 4: AArch64 -->
  <g transform="translate(480, 20)">
    <rect width="145" height="250" fill="#f8fafc" stroke="#0284c7" class="port-card" />
    <rect width="145" height="28" fill="#e0f2fe" rx="6" />
    <text x="72.5" y="19" text-anchor="middle" class="p-title" fill="#0369a1">ARMv8-A / A64</text>

    <text x="10" y="48" class="p-cat">CPU MODEL</text>
    <text x="10" y="63" class="p-val">64-bit BCM2837</text>

    <text x="10" y="88" class="p-cat">INTERRUPTS</text>
    <text x="10" y="103" class="p-val">MSR DAIFSET/CLR</text>

    <text x="10" y="128" class="p-cat">LOCK MECHANISM</text>
    <text x="10" y="143" class="p-val">LDAXR / STLXR</text>

    <text x="10" y="168" class="p-cat">IPI SIGNAL</text>
    <text x="10" y="183" class="p-val">GIC SGI / Mailbox</text>

    <text x="10" y="208" class="p-cat">CONTEXT</text>
    <text x="10" y="223" class="p-val">64-bit x0-x30, Q</text>
  </g>

  <!-- Column 5: RISC-V -->
  <g transform="translate(635, 20)">
    <rect width="145" height="250" fill="#f8fafc" stroke="#0284c7" class="port-card" />
    <rect width="145" height="28" fill="#e0f2fe" rx="6" />
    <text x="72.5" y="19" text-anchor="middle" class="p-title" fill="#0369a1">RISC-V (RV32/64)</text>

    <text x="10" y="48" class="p-cat">CPU MODEL</text>
    <text x="10" y="63" class="p-val">Hart ID (mhartid)</text>

    <text x="10" y="88" class="p-cat">INTERRUPTS</text>
    <text x="10" y="103" class="p-val">CSR mstatus.MIE</text>

    <text x="10" y="128" class="p-cat">LOCK MECHANISM</text>
    <text x="10" y="143" class="p-val">AMO.SWAP / LR/SC</text>

    <text x="10" y="168" class="p-cat">IPI SIGNAL</text>
    <text x="10" y="183" class="p-val">CLINT (msip)</text>

    <text x="10" y="208" class="p-cat">CONTEXT</text>
    <text x="10" y="223" class="p-val">ra, sp, CSRs</text>
  </g>
</svg>'''
    with open(os.path.join(DIAGRAMS_DIR, "ports_matrix.svg"), "w") as f:
        f.write(svg)

if __name__ == "__main__":
    generate_repo_topology()
    generate_smp_hazard()
    generate_context_switch_protocol()
    generate_scheduler_topology()
    generate_intrusive_comparison()
    generate_ports_matrix()
    print("Successfully generated all 6 vector SVG diagrams.")
