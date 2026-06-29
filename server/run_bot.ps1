param(
	[string]$GodotPath = "",
	[string]$ProjectRoot = "",
	[string]$QuitFlag = "user://bot.quit",
	[string]$ServerAddress = "127.0.0.1",
	[int]$ServerPort = 5000,
	[int]$Count = 1,
	[float]$Skill = 0.55,
	[float]$Aggression = 0.55,
	[float]$Accuracy = 0.55,
	[int]$ReactionMs = 160,
	[int]$Freq = 0,
	[int]$ShipType = 0,
	[string]$Username = "",
	[switch]$Verbose
)

$ErrorActionPreference = "Stop"

function Resolve-ProjectRoot {
	if ($ProjectRoot -and $ProjectRoot.Trim() -ne "") {
		return (Resolve-Path $ProjectRoot).Path
	}
	return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-ProjectName([string]$root) {
	$projectGodot = Join-Path $root "project.godot"
	if (Test-Path $projectGodot) {
		try {
			$lines = Get-Content $projectGodot -ErrorAction Stop
			foreach ($line in $lines) {
				if ($line -match '^\s*config/name\s*=\s*"(.+)"\s*$') {
					return $Matches[1]
				}
			}
		} catch {}
	}
	return (Split-Path -Leaf $root)
}

function Resolve-GodotPath {
	if ($GodotPath -and $GodotPath.Trim() -ne "") {
		return $GodotPath
	}
	# Search common locations.
	foreach ($name in @("godot", "godot4")) {
		$cmd = Get-Command $name -ErrorAction SilentlyContinue
		if ($cmd -and (Test-Path $cmd.Source)) { return $cmd.Source }
	}
	# Search Downloads for extracted Godot executables.
	$dl = Join-Path $env:USERPROFILE "Downloads"
	$found = Get-ChildItem $dl -Filter "Godot_v4*.exe" -ErrorAction SilentlyContinue |
		Where-Object { $_.Name -notlike "*.zip*" } |
		Sort-Object LastWriteTime -Descending |
		Select-Object -First 1
	if ($found) { return $found.FullName }
	throw "Godot executable not found. Pass -GodotPath 'C:\path\to\godot.exe'"
}

$root = Resolve-ProjectRoot
$godot = Resolve-GodotPath

if ($Count -lt 1) { $Count = 1 }
if ($Count -gt 32) {
	Write-Host "[run_bot] Clamping Count to 32 (requested $Count)" -ForegroundColor Yellow
	$Count = 32
}

$projectName = Get-ProjectName -root $root

# Resolve user:// quit flag to absolute path.
$quitFileAbs = ""
if ($QuitFlag -and $QuitFlag.StartsWith("user://")) {
	$rel = $QuitFlag.Substring("user://".Length)
	$appData = [System.Environment]::GetFolderPath("ApplicationData")
	$quitFileAbs = Join-Path $appData "Godot\app_userdata\$projectName\$rel"
}

Write-Host "[run_bot] Godot:   $godot"
Write-Host "[run_bot] Project: $root"
Write-Host "[run_bot] Server:  ${ServerAddress}:${ServerPort}"
Write-Host "[run_bot] Count:   $Count  Skill=$Skill  Aggr=$Aggression  Acc=$Accuracy  React=${ReactionMs}ms"

$botProcs = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()

# Launch each bot as a separate headless process.
for ($i = 0; $i -lt $Count; $i++) {
	$botUsername = if ($Username -ne "") { "${Username}_${i}" } else { "Bot_${i}" }
	$botQuitFlag = "user://bot_${i}.quit"
	$botSeed = Get-Random -Minimum 1 -Maximum 999999

	$args = @(
		"--headless",
		"--path", $root,
		"--script", "res://client/bot_client.gd",
		"--",
		"--server_address=$ServerAddress",
		"--server_port=$ServerPort",
		"--username=$botUsername",
		"--skill=$Skill",
		"--aggression=$Aggression",
		"--accuracy=$Accuracy",
		"--reaction_ms=$ReactionMs",
		"--seed=$botSeed",
		"--quit_flag=$botQuitFlag"
	)
	if ($Freq -gt 0) {
		$args += "--freq=$Freq"
	}
	if ($ShipType -gt 0) {
		$args += "--ship_type=$ShipType"
	}

	Write-Host "[run_bot] Launching bot $i: $botUsername" -ForegroundColor Cyan
	$proc = Start-Process -FilePath $godot -ArgumentList $args -PassThru -NoNewWindow
	$botProcs.Add($proc)

	# Stagger launches to avoid simultaneous connection bursts.
	if ($i -lt ($Count - 1)) {
		Start-Sleep -Milliseconds 300
	}
}

Write-Host "[run_bot] $($botProcs.Count) bot(s) running. Press Ctrl+C to stop all." -ForegroundColor Green

$script:stopping = $false
$handler = {
	param($sender, $e)
	$e.Cancel = $true
	if (-not $script:stopping) {
		$script:stopping = $true
		Write-Host "`n[run_bot] Stopping bots..." -ForegroundColor Yellow
		foreach ($p in $botProcs) {
			if (-not $p.HasExited) {
				Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
			}
		}
	}
}
[Console]::add_CancelKeyPress($handler)

try {
	# Wait for all bot processes to exit.
	while ($true) {
		$alive = $botProcs | Where-Object { -not $_.HasExited }
		if ($alive.Count -eq 0) { break }
		Start-Sleep -Seconds 1
	}
} finally {
	[Console]::remove_CancelKeyPress($handler)
}

Write-Host "[run_bot] All bots exited."
