@echo off
REM ==================================================================
REM  run_sim.bat  -  one-click simulation on Windows
REM  Needs: Python 3 and Icarus Verilog (iverilog, vvp) in PATH
REM  Steps: 1) assemble program  2) compile Verilog  3) run simulation
REM ==================================================================
cd /d "%~dp0"

REM Use "python" if available, otherwise the Windows launcher "py"
set PY=python
where python >nul 2>nul || set PY=py

echo [1/3] Assembling sw\program.s  -^>  program.hex
%PY% sw\asm8.py sw\program.s program.hex
if errorlevel 1 goto fail

echo [2/3] Compiling Verilog (file list in files.f)
iverilog -g2005 -o sim.vvp -c files.f
if errorlevel 1 goto fail

echo [3/3] Running simulation
vvp sim.vvp
echo.
echo Waveform saved as risc8_5stage.vcd  (open it with: gtkwave risc8_5stage.vcd)
pause
exit /b 0

:fail
echo *** A step failed - see the message above ***
pause
exit /b 1
