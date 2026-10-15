@echo off
setlocal
REM M0 自查三级关卡：导入缓存 + gdUnit4 全量单测 + 真实渲染视觉冒烟（退出码透传）
REM 注意：第 3 级需要显示环境与 GPU，会短暂开窗 2~3 秒；无头 CI 需跳过或接虚拟显示（当前不做）
cd /d "%~dp0.."

echo [1/3] godot --headless --import ...
godot --headless --import
if errorlevel 1 goto :fail

echo [2/3] gdUnit4 全量单测 ...
godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests -c
if errorlevel 1 goto :fail

echo [3/3] 视觉冒烟（短暂开窗，需 GPU）...
godot --path . --resolution 640x360 res://tests/visual/visual_smoke.tscn
if errorlevel 1 goto :fail

echo SELFCHECK ALL GREEN
exit /b 0

:fail
echo SELFCHECK FAILED
exit /b 1
