# ============================================================================
# Takshaka build & test driver (Icarus Verilog) — Windows / PowerShell.
#
#   .\build.ps1 [sim|cosim|rvfi|debug|priv|axi|rtos|clean]
#
# Takshaka is a 3-stage in-order RV32IMAC(+B, Zcb) core. The datapath leaf
# cells live in rtl/common; the core, SoC, UART, AXI4-Lite wrapper and the
# RISC-V Debug Module live in rtl/.
# ============================================================================
param([string]$Action = "sim")
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$IVL = if ($env:IVERILOG) { $env:IVERILOG } else { "iverilog" }
$VVP = if ($env:VVP) { $env:VVP } else { "vvp" }
$R = "rtl"; $C = "rtl/common"; $DBG = "rtl/takshaka_debug.sv"

$CELLS = @(
  "$C/takshaka_pkg.sv","$C/takshaka_alu.sv","$C/takshaka_regfile.sv",
  "$C/takshaka_muldiv.sv","$C/takshaka_csr.sv","$C/takshaka_rvc.sv",
  "$C/takshaka_immgen.sv","$C/takshaka_branch.sv","$C/takshaka_decode.sv",
  "$C/takshaka_pmp.sv"
)

if ($Action -eq "clean") {
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue sim, programs/build, rtos/build, *.vcd
  Write-Host "Cleaned"; exit 0
}
New-Item -ItemType Directory -Force -Path sim, programs/build | Out-Null

if ($Action -eq "axi") {
  Write-Host "Building Takshaka AXI4-Lite MASTER bridge sim..."
  & $IVL -g2012 -I $C -I $R -o sim/tb_takshaka_axi "$C/takshaka_pkg.sv" "$R/takshaka_axi_lite.sv" tb/tb_takshaka_axi.sv
  & $VVP sim/tb_takshaka_axi; exit 0
}

if ($Action -eq "debug") {
  Write-Host "Building Takshaka debug (JTAG DM) sim..."
  & $IVL -g2012 -I $C -I $R -o sim/tb_takshaka_debug @CELLS $DBG "$R/takshaka_core.sv" "$R/takshaka_uart.sv" "$R/takshaka_soc.sv" tb/tb_takshaka_debug.sv
  & $VVP sim/tb_takshaka_debug; exit 0
}

# ---- default: smoke (+ optional cosim / rvfi) ------------------------------
python programs/build_smoke.py
Write-Host "Compiling..."
& $IVL -g2012 -I $C -I $R -o sim/tb_takshaka @CELLS $DBG "$R/takshaka_core.sv" "$R/takshaka_uart.sv" "$R/takshaka_soc.sv" tb/tb_takshaka.sv
Write-Host "Running smoke..."
& $VVP sim/tb_takshaka +IMEM=programs/build/smoke.hex

if ($Action -eq "cosim") {
  Write-Host "Co-simulating against golden model..."
  $env:VVP = $VVP
  python tools/cosim.py --hex programs/build/smoke.hex --sim sim/tb_takshaka
}
if ($Action -eq "rvfi") {
  Write-Host "Building RVFI (riscv-formal interface) self-check..."
  & $IVL -g2012 -DRISCV_FORMAL -I $C -I $R -o sim/tb_takshaka_rvfi @CELLS $DBG "$R/takshaka_core.sv" "$R/takshaka_uart.sv" "$R/takshaka_soc.sv" tb/tb_takshaka_rvfi.sv
  & $VVP sim/tb_takshaka_rvfi +IMEM=programs/build/smoke.hex
}
