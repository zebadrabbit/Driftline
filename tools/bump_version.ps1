param(
	[ValidateSet('major','minor','revision','rev')]
	[string]$Part = 'revision'
)

$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$versionPath = Join-Path $root 'VERSION'

if (-not (Test-Path $versionPath)) {
	throw "VERSION file not found at: $versionPath"
}

$raw = (Get-Content $versionPath -Raw).Trim()
if (-not ($raw -match '^(\d+)\.(\d+)\.(\d+)$')) {
	throw "Invalid VERSION format '$raw' (expected MAJOR.MINOR.REVISION)"
}

[int]$major = $Matches[1]
[int]$minor = $Matches[2]
[int]$revision = $Matches[3]

switch ($Part) {
	'major' {
		$major += 1
		$minor = 0
		$revision = 0
	}
	'minor' {
		$minor += 1
		$revision = 0
	}
	'revision' { $revision += 1 }
	'rev' { $revision += 1 }
}

$new = "$major.$minor.$revision"
Set-Content -Path $versionPath -Value "$new`n" -NoNewline
Write-Host $new
