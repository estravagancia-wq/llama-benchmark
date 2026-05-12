@echo off
REM ============================================================================
REM llama.cpp Benchmark Tracker - Plan de Pruebas
REM ============================================================================
REM 
REM INSTRUCCIONES:
REM   1. Ejecuta cada test en orden
REM   2. Copia el resultado de monitor.ps1 (Ctrl+C para detener)
REM   3. Guarda el resultado en logs/ con nombre descriptivo
REM   4. Rellena los campos de la tabla al final de este archivo
REM   5. Ejecuta este archivo con "benchmark-tracker" en el monitor
REM ============================================================================

echo.
echo ===============================================================
echo   llama.cpp Benchmark Tracker
echo   Qwen3.6-35B-A3B | RX 9070 XT 16GB | 9800X3D
echo ===============================================================
echo.

REM Create logs directory
if not exist "logs" mkdir logs

echo CONFIGURACION BASE (fija):
echo   Modelo: Qwen3.6-35B-A3B-Q4_K_M
echo   -c 65536 | -ngl 99 | --threads 8
echo   --ubatch-size 512 | -b 1024
echo   --cache-type-k q8_0 | --cache-type-v q8_0
echo   --cont-batching | --flash-attn auto
echo   --no-mmap
echo.

echo PRUEBAS PENDIENTES:
echo   [4] --n-cpu-moe 12  -> Entre 8 y 16
echo   [5] --n-cpu-moe 14  -> Afinar alrededor del sweet spot
echo   [6] --n-cpu-moe 18  -> Ver si 16->20 mejora o empeora
echo   [7] --ubatch-size 256 -> Reducir batch -> menor cliff
echo   [8] --ubatch-size 1024 -> Aumentar batch -> mas throughput
echo   [9] -b 2048 -> Mayor batch size -> mas tokens concurrentes
echo   [10] --threads 16 -> Mas threads -> mejor procesamiento CPU
echo   [11] --cache-type-k/v f16 -> Mayor precision
echo   [12] --n-cpu-moe 24 -> Extender mas alla de 20
echo.

echo HISTORIAL DE PRUEBAS:
echo   # | Fecha       | Parametro     | Valor | TPS | RAM max | Tokens pico | Notas
echo   ---|-------------|---------------|-------|-----|---------|-------------|------------------
echo    1 | ~17:07      | --n-cpu-moe   |     8 | 16  |  26.7GB |        2791 | Degradacion fuerte
echo    2 | ~17:24      | --n-cpu-moe   |    20 | 20  |  18.6GB |        2171 | Estable, buen equilibrio
echo    3 | ~18:17      | --n-cpu-moe   |    16 | 23  |  19.7GB |        2237 | Sweet spot - mejor TPS
echo    4 | [FECHA]     | --n-cpu-moe   |    12 | [ ] |   [ ]GB |         [ ] | 
echo    5 | [FECHA]     | --n-cpu-moe   |    14 | [ ] |   [ ]GB |         [ ] | 
echo    6 | [FECHA]     | --n-cpu-moe   |    18 | [ ] |   [ ]GB |         [ ] | 
echo    7 | [FECHA]     | --ubatch-size |   256 | [ ] |   [ ]GB |         [ ] | 
echo    8 | [FECHA]     | --ubatch-size |  1024 | [ ] |   [ ]GB |         [ ] | 
echo    9 | [FECHA]     | -b            |  2048 | [ ] |   [ ]GB |         [ ] | 
echo   10 | [FECHA]     | --threads     |    16 | [ ] |   [ ]GB |         [ ] | 
echo   11 | [FECHA]     | --cache-type  |   f16 | [ ] |   [ ]GB |         [ ] | 
echo   12 | [FECHA]     | --n-cpu-moe   |    24 | [ ] |   [ ]GB |         [ ] | 
echo.

echo Para ejecutar un test, edita estravagancia-server.bat con el valor deseado,
echo luego ejecuta monitor.ps1 y copia el resultado en logs/
echo.

REM Save current config
set TIMESTAMP=%date:~-4,4%-%date:~-7,2%-%date:~-10,2%
set TIMESTAMP=%TIMESTAMP:/=-%

echo Presiona Enter para cerrar...
pause >nul
