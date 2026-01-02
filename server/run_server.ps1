param(
	[string]$GodotPath = "",
	[string]$ProjectRoot = "",
	[string]$QuitFlag = "res://.server.quit"
)

$ErrorActionPreference = "Stop"

# Startup banner (printed before any other logs).
Write-Host '#    _________      ___________________________             '
Write-Host '#    ______  /_________(_)__  __/_  /___  /__(_)___________ '
Write-Host '#    _  __  /__  ___/_  /__  /_ _  __/_  /__  /__  __ \  _ \' 
Write-Host '#    / /_/ / _  /   _  / _  __/ / /_ _  / _  / _  / / /  __/'
Write-Host '#    \__,_/  /_/    /_/  /_/    \__/ /_/  /_/  /_/ /_/\___/ '
Write-Host '#'

function Resolve-ProjectRoot {
	if ($ProjectRoot -and $ProjectRoot.Trim() -ne "") {
		return (Resolve-Path $ProjectRoot).Path
	}
	return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Resolve-GodotExe([string]$root) {
	if ($GodotPath -and $GodotPath.Trim() -ne "") {
		return $GodotPath
	}
	if ($env:GODOT4 -and $env:GODOT4.Trim() -ne "") {
		return $env:GODOT4
	}

	$settingsPath = Join-Path $root ".vscode\settings.json"
	if (Test-Path $settingsPath) {
		try {
			$json = Get-Content $settingsPath -Raw | ConvertFrom-Json
			$pathFromSettings = $json."godotTools.editorPath.godot4"
			if ($pathFromSettings -and $pathFromSettings.Trim() -ne "") {
				return $pathFromSettings
			}
		} catch {
			# ignore
		}
	}

	$cmd = Get-Command godot -ErrorAction SilentlyContinue
	if ($cmd -and $cmd.Source) {
		return $cmd.Source
	}

	throw "Could not find Godot. Set -GodotPath, or set GODOT4 env var, or set .vscode/settings.json godotTools.editorPath.godot4."
}

function Prefer-ConsoleGodot([string]$exePath) {
	if (-not (Test-Path $exePath)) {
		return $exePath
	}
	# If the configured exe is the GUI build, prefer the console build when present.
	# Example: Godot_v4.5.1-stable_win64.exe -> Godot_v4.5.1-stable_win64_console.exe
	if ($exePath.ToLower().EndsWith("_console.exe")) {
		return $exePath
	}
	$dir = Split-Path -Parent $exePath
	$leaf = Split-Path -Leaf $exePath
	if ($leaf.ToLower().EndsWith(".exe")) {
		$consoleLeaf = $leaf.Substring(0, $leaf.Length - 4) + "_console.exe"
		$consolePath = Join-Path $dir $consoleLeaf
		if (Test-Path $consolePath) {
			return $consolePath
		}
	}
	return $exePath
}

$root = Resolve-ProjectRoot
$godot = Resolve-GodotExe -root $root
$godot = Prefer-ConsoleGodot -exePath $godot

if (-not (Test-Path $godot)) {
	throw "Godot executable not found at: $godot"
}

# We use a quit flag in the *project folder* so this works even if the Godot exe
# is a GUI subsystem process (which typically doesn't receive Ctrl+C events on Windows).
$quitFileAbs = Join-Path $root ".server.quit"
if (Test-Path $quitFileAbs) {
	Remove-Item $quitFileAbs -Force -ErrorAction SilentlyContinue
}

$script:serverProc = $null
$script:ctrlCCount = 0

$handler = [ConsoleCancelEventHandler]{
	param($src, $e)
	$script:ctrlCCount++
	Write-Host "`n[run_server] Ctrl+C received (x$script:ctrlCCount). Requesting graceful shutdown..." -ForegroundColor Yellow
	try {
		New-Item -ItemType File -Path $quitFileAbs -Force | Out-Null
	} catch {
		Write-Host "[run_server] Failed to create quit flag: $quitFileAbs" -ForegroundColor Red
	}

	# Keep PowerShell alive while the server notices the quit flag and exits.
	$e.Cancel = $true

	# Second Ctrl+C forces termination.
	if ($script:ctrlCCount -ge 2) {
		Write-Host "[run_server] Forcing server termination..." -ForegroundColor Red
		if ($script:serverProc -and -not $script:serverProc.HasExited) {
			Stop-Process -Id $script:serverProc.Id -Force -ErrorAction SilentlyContinue
		}
	}
}

[Console]::add_CancelKeyPress($handler)

try {
	Write-Host "[run_server] Godot:   $godot"
	Write-Host "[run_server] Project: $root"
	Write-Host "[run_server] QuitFlag: $QuitFlag (creates $quitFileAbs)"
	Write-Host "[run_server] Press Ctrl+C to stop (press twice to force kill)."

	$args = @(
		"--headless",
		"--path", $root,
		"--script", "res://server/server_main.gd",
		"--",
		"--quit_flag=$QuitFlag"
	)

	# Start a child process so our Ctrl+C handler can run reliably.
	$script:serverProc = Start-Process -FilePath $godot -ArgumentList $args -PassThru -NoNewWindow
	$script:serverProc.WaitForExit()
	$exitCode = $script:serverProc.ExitCode
	Write-Host "[run_server] Server exited with code $exitCode"
	exit $exitCode
} finally {
	[Console]::remove_CancelKeyPress($handler)
	if (Test-Path $quitFileAbs) {
		Remove-Item $quitFileAbs -Force -ErrorAction SilentlyContinue
	}
}
