# lab.ps1 - Windows version of lab.sh. Start it with lab.cmd:
#
#   .\lab.cmd [lab|strace|step|step_strace]      (default: lab)
#
# Finds a working container engine, Docker or Podman. For each one it checks
# that it is installed, running, can run a container ("hello-world") and has
# "compose", then runs:   <engine> compose run --rm <mode>
#
# Set LAB_ENGINE=podman to use only Podman.
# Written for Windows PowerShell 5.1, which every Windows 10/11 has.

param([string]$Mode = "lab")

Set-Location -LiteralPath $PSScriptRoot

$modes = @("lab", "strace", "step", "step_strace")
if ($modes -notcontains $Mode) {
    Write-Host "Unknown mode: $Mode"
    Write-Host ("Usage: .\lab.cmd [" + ($modes -join "|") + "]")
    exit 2
}

# Hide podman's "Executing external compose provider" warning.
$env:PODMAN_COMPOSE_WARNING_LOGS = "false"

function Ok($text)   { Write-Host "  OK    $text" -ForegroundColor Green }
function Fail($text) { Write-Host "  FAIL  $text" -ForegroundColor Red }

function NotRunningHint($engine) {
    if ($engine -eq "docker") {
        return "Start Docker Desktop and wait until it says 'Engine running'."
    }
    return "Start the Podman machine:  podman machine start   (the very first time: podman machine init, then podman machine start)"
}

# Returns the compose command (an array) if the engine works, else a string: the reason.
function Check($engine) {
    Write-Host "Checking $engine..."

    if (-not (Get-Command $engine -ErrorAction SilentlyContinue)) {
        Fail "$engine is not installed"
        return "$engine is not installed."
    }
    Ok "installed"

    & $engine info *> $null
    if ($LASTEXITCODE -ne 0) {
        Fail "$engine is installed but not running"
        return "$engine is installed but not running. " + (NotRunningHint $engine)
    }
    Ok "running"

    # "$_" turns each line into plain text. (Windows PowerShell 5.1 wraps the
    # program's error output in error records, which print as several lines.)
    $out = @(& $engine run --rm docker.io/library/hello-world 2>&1 | ForEach-Object { "$_" } | Where-Object { $_.Trim() })
    if ($LASTEXITCODE -ne 0) {
        Fail "$engine cannot run a container"
        return "$engine cannot run a container. The error was: " + $out[-1]
    }
    Ok "can run containers"

    # Podman: prefer podman-compose. "podman compose" may hand over to docker-compose.
    $compose = $null
    if ($engine -eq "podman" -and (Get-Command podman-compose -ErrorAction SilentlyContinue)) {
        $compose = @("podman-compose")
    } else {
        & $engine compose version *> $null
        if ($LASTEXITCODE -eq 0) {
            $compose = @($engine, "compose")
        } elseif ($engine -eq "docker" -and (Get-Command docker-compose -ErrorAction SilentlyContinue)) {
            $compose = @("docker-compose")
        }
    }
    if ($null -eq $compose) {
        Fail "compose is missing"
        if ($engine -eq "docker") {
            return "docker works, but compose is missing. Update Docker Desktop, it includes compose."
        }
        return "podman works, but compose is missing. Install podman-compose (for example: pip install podman-compose), or use Podman Desktop, which can install it."
    }
    Ok ("compose (" + ($compose -join " ") + ")")
    return ,$compose
}

if ($env:LAB_ENGINE) { $engines = $env:LAB_ENGINE -split "\s+" } else { $engines = @("docker", "podman") }

$reasons = @()
foreach ($engine in $engines) {
    $result = Check $engine
    if ($result -is [array]) {
        Write-Host ""
        Write-Host ("Starting:  " + ($result -join " ") + " run --rm $Mode")
        Write-Host "(The first start builds the lab image, which takes a few minutes.)" -ForegroundColor DarkGray
        Write-Host "(To quit the lab: press Ctrl-b, release, then press d.)" -ForegroundColor DarkGray
        $rest = @()
        if ($result.Count -gt 1) { $rest = $result[1..($result.Count - 1)] }
        & $result[0] @rest run --rm $Mode
        exit $LASTEXITCODE
    }
    $reasons += $result
    Write-Host ""
}

Write-Host "No working container engine found. You need Docker or Podman:" -ForegroundColor Red
foreach ($reason in $reasons) { Write-Host "  - $reason" }
Write-Host "See the Troubleshooting section in README.md."
exit 1
