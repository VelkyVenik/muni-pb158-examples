# lab.ps1 - Windows version of lab.sh. Start it with lab.cmd:
#
#   .\lab.cmd           shows a menu of the modes
#   .\lab.cmd <mode>    starts that mode: lab, step_strace, step, nc, plain
#
# Finds a working container engine: Podman first, then Docker. For each one it checks
# that it is installed, running, can run a container ("hello-world") and has
# "compose", then runs:   <engine> compose build lab, <engine> compose run --rm <mode>
#
# Set LAB_ENGINE=docker to use only Docker.
# Written for Windows PowerShell 5.1, which every Windows 10/11 has.

param([string]$Mode = "")

Set-Location -LiteralPath $PSScriptRoot

# The modes, in the order of the menu.
$modes = @("lab", "step_strace", "step", "nc", "plain")
$descriptions = @(
    "program output + system calls + packets, in slow motion",
    "you step through the C code, with system calls + packets",
    "you step through the C code, with packets",
    "you are the client: type messages to the server yourself",
    "program output + packets, at full speed"
)
if ($Mode -and ($modes -notcontains $Mode)) {
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

# Ask which mode to start.
function ChooseMode {
    Write-Host "Which part of the lab do you want to start?"
    Write-Host ""
    for ($i = 0; $i -lt $modes.Count; $i++) {
        Write-Host ("  {0}) {1,-12} {2}" -f ($i + 1), $modes[$i], $descriptions[$i])
    }
    Write-Host ""
    while ($true) {
        $choice = Read-Host ("Choose 1-" + $modes.Count + " (Enter = 1)")
        if (-not $choice) { $choice = "1" }
        $number = 0
        if ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le $modes.Count) {
            $picked = $modes[$number - 1]
            break
        }
        if ($modes -contains $choice) { $picked = $choice; break }
    }
    Write-Host ""
    Write-Host "(Next time you can start it directly:  .\lab.cmd $picked)" -ForegroundColor DarkGray
    Write-Host ""
    return $picked
}

if ($env:LAB_ENGINE) { $engines = $env:LAB_ENGINE -split "\s+" } else { $engines = @("podman", "docker") }

$reasons = @()
foreach ($engine in $engines) {
    $result = Check $engine
    if ($result -is [array]) {
        Write-Host ""
        if (-not $Mode) { $Mode = ChooseMode }
        $rest = @()
        if ($result.Count -gt 1) { $rest = $result[1..($result.Count - 1)] }
        Write-Host ""
        Write-Host ("Building:  " + ($result -join " ") + " build lab")
        Write-Host "(The first time this takes a few minutes, later only seconds.)" -ForegroundColor DarkGray
        & $result[0] @rest build lab
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Write-Host ""
        Write-Host ("Starting:  " + ($result -join " ") + " run --rm $Mode")
        Write-Host "(To quit the lab: press Ctrl-b, release, then press d.)" -ForegroundColor DarkGray
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
