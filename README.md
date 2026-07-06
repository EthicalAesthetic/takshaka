# Takshaka

**Takshaka** is a compact, high-performance **3-stage pipelined RV32IMAC**
processor core. It executes instructions in a classic in-order
fetch / execute / memory-writeback pipeline with full result forwarding, a
load-use interlock, and a dynamic branch predictor — delivering strong
per-clock throughput while staying small and easy to reason about.

The core targets embedded and control-plane roles that want more performance
than a minimal multi-cycle core without the area of an application processor:
microcontrollers, real-time controllers, smart peripherals, and FPGA soft
cores.

---

## Highlights

- **ISA:** RV32IMAC — base integer, `M` multiply/divide, `A` atomics,
  and `C` compressed — plus the **`B` bit-manipulation** set
  (`Zba`, `Zbb`, `Zbc`, `Zbs`) and **`Zcb`** code-size instructions, with the
  `Zicsr` control-and-status extension.
- **Microarchitecture:** 3-stage in-order pipeline
  (**IF → EX → MEM/WB**) with a full forwarding network — load data produced in
  the memory stage forwards to a dependent instruction with **no load-use
  stall**; only multi-cycle operations (multiply/divide, misaligned access,
  atomics) stall. One instruction retires per cycle in the common case.
- **Branch prediction:** dynamic **gshare + BTB + RAS** (return-address stack)
  front end with a halfword-granular, RVC-safe target buffer — mispredicts
  flush and redirect, everything else flows.
- **Privilege:** Machine mode always; the **`SECURE`** configuration adds a
  full **M / U / N** privilege split (including `N` user-level traps).
- **Memory protection:** optional **8-region PMP** with TOR / NA4 / NAPOT
  matching, R/W/X permissions, locking, and **ePMP** (`mseccfg`) semantics
  (`SECURE`).
- **Debug triggers:** optional hardware **breakpoint / watchpoint** triggers
  (`mcontrol6`: execute PC-match and load/store address-match) (`SECURE`).
- **Traps & interrupts:** precise exceptions, `ECALL` / `EBREAK` / illegal-
  instruction handling, `MRET` / `URET`, and timer / software / external
  interrupt lines.
- **Misaligned access:** hardware support for misaligned loads and stores
  (handled as a two-beat memory sequence).
- **Debug:** RISC-V External Debug — a JTAG Transport Module plus a Debug
  Module (halt / resume, single-step, GPR & CSR access).
- **Buses:** a minimal native memory interface, plus an **AXI4-Lite** wrapper
  for drop-in integration into standard SoC fabrics.
- **RTOS:** a ready-to-run **FreeRTOS** port (preemptive multitasking driven
  by the SoC timer, with a UART console).
- **Verification:** self-checking tests, cycle-accurate **co-simulation
  against a golden RV32IM ISA model**, an **RVFI** (RISC-V Formal Interface)
  port, a Debug-Module self-check, and a constrained-random test flow.
- **Performance:** ~**3.16 CoreMark/MHz** (measured on RTL, no caches).

---

## Repository layout

```
takshaka/
├── rtl/                 core RTL
│   ├── takshaka_core.sv   3-stage pipeline + predictor + forwarding
│   ├── takshaka_soc.sv    minimal SoC (IMEM/DRAM, CLINT, UART, tohost)
│   ├── takshaka_debug.sv  JTAG DTM + RISC-V Debug Module
│   ├── takshaka_axi_lite.sv  AXI4-Lite master bridge
│   ├── takshaka_uart.sv   UART console peripheral
│   └── common/            shared, pre-verified datapath leaf cells
│                          (ALU, multiply/divide, register file, CSR file,
│                           immediate/branch units, decoder, RVC, PMP)
├── tb/                  testbenches (smoke, RVFI, debug, priv, AXI-Lite, RTOS)
├── tools/              golden ISA model + co-simulation driver
├── programs/           test-program builders
├── sw/                 assembly test programs & bring-up firmware
├── rtos/               FreeRTOS port (kernel, BSP, demo app)
├── fpga/               FPGA SoC + Arty A7 / ZCU102 constraints
├── docs/               documentation site (MkDocs)
├── build.sh            Linux/macOS build & test driver
└── build.ps1           Windows (PowerShell) build & test driver
```

## Requirements

- **Icarus Verilog 12+** (`iverilog` / `vvp`) for simulation
- **Python 3.10+** for the test-program builders and co-simulation
- *(optional)* a RISC-V GCC toolchain to rebuild the assembly test programs
- *(optional)* Vivado for the Arty A7 / ZCU102 FPGA flows

## Build & test

Linux / macOS:

```bash
./build.sh          # compile + self-checking smoke test
./build.sh cosim    # + co-simulate against the golden ISA model
./build.sh rvfi     # RVFI (formal interface) self-check
./build.sh debug    # JTAG / Debug-Module self-check
./build.sh priv     # SECURE config: M/U/N + PMP + trigger tests
./build.sh axi      # AXI4-Lite master BFM test
./build.sh rtos     # FreeRTOS preemptive multitasking demo
./build.sh clean
```

Windows (PowerShell):

```powershell
.\build.ps1          # compile + smoke
.\build.ps1 cosim    # + golden co-simulation
.\build.ps1 rvfi
.\build.ps1 debug
```

Expected output for the default build:

```
[TB] PASS
[cosim] MATCH — retires identical. RTL is ISA-correct.
```

## Configurations

Takshaka ships in two build-time configurations, selected by a parameter /
define:

| Configuration | Privilege | Memory protection | Debug triggers | Use case |
|---------------|-----------|-------------------|----------------|----------|
| **Default**   | Machine only | — | — | smallest footprint |
| **`SECURE`**  | Machine + User + N | 8-region PMP + ePMP | breakpoint / watchpoint | isolation & introspection |

Enable the secure configuration with the `SECURE` RTL parameter, or at compile
time with `-DTAKSHAKA_SECURE`.

## Documentation

Full documentation — architecture, ISA, memory map, CSRs, branch prediction,
security model, debug, bus integration, FPGA bring-up, and verification —
lives in [`docs/`](docs) and builds into a browsable site with
[MkDocs](https://www.mkdocs.org/):

```bash
pip install -r docs/requirements.txt
mkdocs serve      # http://127.0.0.1:8000
```

## License

Released under the [MIT License](LICENSE).
