# _paths.ps1 — dot-sourced by every Windows build script; resolves locations independent of CWD.
#
# Layout inside a project (the project's setup.sh copies scripts\ and tools\ of this repo into build\):
#   <project>\                  $ProjectRoot  (.ino, Config.h, src\)
#   <project>\build\            $BuildRoot = $ToolchainRoot
#                               committed:  .gitignore, release_matrix.csv, required_libraries.txt, version_state
#                               installed:  scripts\, tools\
#                               generated:  libraries\, builds\, .venv\, build_config.ps1
#
# Override for other layouts with $env:XEWE_BUILD_ROOT and $env:XEWE_PROJECT_ROOT.

$ToolchainRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$BuildRoot     = if ($env:XEWE_BUILD_ROOT)   { (Resolve-Path $env:XEWE_BUILD_ROOT).Path }   else { $ToolchainRoot }
$ProjectRoot   = if ($env:XEWE_PROJECT_ROOT) { (Resolve-Path $env:XEWE_PROJECT_ROOT).Path } else { Split-Path $BuildRoot -Parent }
