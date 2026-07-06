#!/usr/bin/env bash
# ============================================================================
# Takshaka build & test driver (Icarus Verilog).
#
#   ./build.sh [sim|cosim|rvfi|debug|priv|axi|rtos|fpga|clean]
#
# Takshaka is a 3-stage in-order RV32IMAC(+B, Zcb) core. The datapath leaf
# cells (ALU / muldiv / regfile / CSR / RVC / immgen / branch / decoder / PMP)
# live in rtl/common; the core, SoC, UART, AXI4-Lite wrapper and the RISC-V
# Debug Module live in rtl/.
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"
IVL="${IVERILOG:-iverilog}"; VVP="${VVP:-vvp}"
ACTION="${1:-sim}"

R=rtl
C=rtl/common
DBG=rtl/takshaka_debug.sv

# Shared datapath leaf cells, in elaboration order.
CELLS=( \
  "$C/takshaka_pkg.sv" "$C/takshaka_alu.sv" "$C/takshaka_regfile.sv" \
  "$C/takshaka_muldiv.sv" "$C/takshaka_csr.sv" "$C/takshaka_rvc.sv" \
  "$C/takshaka_immgen.sv" "$C/takshaka_branch.sv" "$C/takshaka_decode.sv" \
  "$C/takshaka_pmp.sv" )

if [[ "$ACTION" == "clean" ]]; then
  rm -rf sim programs/build rtos/build *.vcd
  echo "Cleaned"; exit 0
fi
mkdir -p sim programs/build

if [[ "$ACTION" == "priv" ]]; then
  # Directed M/U + PMP + HW-trigger + N user-trap tests on a SECURE=1 core.
  echo "Building Takshaka SECURE priv/trigger/N sim..."
  python programs/build_priv.py
  python programs/build_trig.py
  python programs/build_ntrap.py
  "$IVL" -g2012 -I "$C" -I "$R" -o sim/tb_takshaka_priv \
    "${CELLS[@]}" "$R/takshaka_core.sv" tb/tb_takshaka_priv.sv 2>/dev/null
  fail=0
  for t in ustore_fault ustore_ok ecall_u ecall_m ifetch_fault ifetch_ok ucsr_u ucsr_m \
           exec_hit exec_miss store_hit store_miss udeleg nodel; do
    hex=""
    [[ -f programs/build/priv_$t.hex  ]] && hex=programs/build/priv_$t.hex
    [[ -f programs/build/trig_$t.hex  ]] && hex=programs/build/trig_$t.hex
    [[ -f programs/build/ntrap_$t.hex ]] && hex=programs/build/ntrap_$t.hex
    r=$("$VVP" sim/tb_takshaka_priv +IMEM="$hex" 2>&1 | grep RESULT)
    printf "  %-16s %s\n" "$t" "$r"
    [[ "$r" == *PASS* ]] || fail=1
  done
  [[ $fail -eq 0 ]] && echo "priv: ALL PASS" || { echo "priv: FAILURES"; exit 1; }
  exit 0
fi

if [[ "$ACTION" == "rtos" ]]; then
  # Port + run a REAL preemptive RTOS (FreeRTOS) on Takshaka. Builds the kernel
  # + RISC-V port + Takshaka BSP into an IMEM image, runs it on the SoC sim
  # (CLINT tick + UART console) and asserts the transcript plus a negative
  # control (tick disabled -> demo stalls). See rtos/run_rtos.py.
  echo "Building Takshaka FreeRTOS demo (positive + negative-control images)..."
  bash rtos/build_rtos.sh
  bash rtos/build_rtos.sh neg
  echo "Running FreeRTOS demo + assertions..."
  IVERILOG="$IVL" VVP="$VVP" python rtos/run_rtos.py
  exit $?
fi

if [[ "$ACTION" == "debug" ]]; then
  echo "Building Takshaka debug (JTAG DM) sim..."
  "$IVL" -g2012 -I "$C" -I "$R" -o sim/tb_takshaka_debug \
    "${CELLS[@]}" "$DBG" \
    "$R/takshaka_core.sv" "$R/takshaka_uart.sv" "$R/takshaka_soc.sv" \
    tb/tb_takshaka_debug.sv
  "$VVP" sim/tb_takshaka_debug
  exit 0
fi

if [[ "$ACTION" == "axi" ]]; then
  # OPTIONAL AXI4-Lite MASTER bridge — standalone leaf cell + slave-mem BFM tb.
  # The default takshaka_soc + compliance path never instantiate it (unchanged).
  echo "Building Takshaka AXI4-Lite MASTER bridge sim..."
  "$IVL" -g2012 -I "$C" -I "$R" -o sim/tb_takshaka_axi \
    "$C/takshaka_pkg.sv" "$R/takshaka_axi_lite.sv" tb/tb_takshaka_axi.sv
  "$VVP" sim/tb_takshaka_axi
  exit 0
fi

if [[ "$ACTION" == "fpga" ]]; then
  echo "Building FPGA SoC sim (UART banner + LED blink)..."
  bash sw/build_fpga_hello.sh || true
  "$IVL" -g2012 -DSIMULATION -I "$C" -I "$R" -o sim/tb_takshaka_fpga \
    "${CELLS[@]}" "$R/takshaka_core.sv" "$R/takshaka_uart.sv" \
    fpga/takshaka_fpga.sv fpga/tb_takshaka_fpga.sv
  "$VVP" sim/tb_takshaka_fpga
  exit 0
fi

# ---- default: smoke (+ optional cosim / rvfi) ------------------------------
python programs/build_smoke.py
echo "Compiling..."
"$IVL" -g2012 -I "$C" -I "$R" -o sim/tb_takshaka \
  "${CELLS[@]}" "$DBG" \
  "$R/takshaka_core.sv" "$R/takshaka_uart.sv" "$R/takshaka_soc.sv" \
  tb/tb_takshaka.sv
echo "Running smoke..."
"$VVP" sim/tb_takshaka +IMEM=programs/build/smoke.hex

if [[ "$ACTION" == "cosim" ]]; then
  echo "Co-simulating against golden model..."
  VVP="$VVP" python tools/cosim.py \
      --hex programs/build/smoke.hex --sim sim/tb_takshaka
fi

if [[ "$ACTION" == "rvfi" ]]; then
  echo "Building RVFI (riscv-formal interface) self-check..."
  "$IVL" -g2012 -DRISCV_FORMAL -I "$C" -I "$R" -o sim/tb_takshaka_rvfi \
    "${CELLS[@]}" "$DBG" \
    "$R/takshaka_core.sv" "$R/takshaka_uart.sv" "$R/takshaka_soc.sv" \
    tb/tb_takshaka_rvfi.sv
  "$VVP" sim/tb_takshaka_rvfi +IMEM=programs/build/smoke.hex
fi
