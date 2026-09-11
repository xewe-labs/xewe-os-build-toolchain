# _paths.ps1 — dot-sourced by every Windows build script; resolves locations independent of CWD.
#
# Layout inside a project:
#   <project>\                  $ProjectRoot   (.ino, Config.h, src\)
#   <project>\build\            $BuildRoot     (project data: release_matrix.csv, libraries\, builds\, build_config.ps1, .venv)
#   <project>\build\toolchain\  $ToolchainRoot (this repo, vendored via git subtree)
#
# Override for other layouts with $env:XEWE_BUILD_ROOT and $env:XEWE_PROJECT_ROOT.

$ToolchainRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$BuildRoot     = if ($env:XEWE_BUILD_ROOT)   { (Resolve-Path $env:XEWE_BUILD_ROOT).Path }   else { Split-Path $ToolchainRoot -Parent }
$ProjectRoot   = if ($env:XEWE_PROJECT_ROOT) { (Resolve-Path $env:XEWE_PROJECT_ROOT).Path } else { Split-Path $BuildRoot -Parent }
