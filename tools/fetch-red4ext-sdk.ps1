# Fetches RED4ext.SDK into deps/ at the commit our RED4ext plugins are built against. After a game patch that changes
# the SDK's types, raise $Commit and run this again.
$Commit = '5246e659d783e5834cc08a90e56c8932c9ed3449'
$ErrorActionPreference = 'Stop'

$target = Join-Path (Split-Path -Parent $PSScriptRoot) 'deps\RED4ext.SDK'
if (-not (Test-Path $target)) {
    git clone --quiet https://github.com/WopsS/RED4ext.SDK.git $target
    if ($LASTEXITCODE -ne 0) { throw 'git clone failed' }
}
if ((git -C $target rev-parse HEAD) -ne $Commit) {
    git -C $target fetch --quiet origin
    if ($LASTEXITCODE -ne 0) { throw 'git fetch failed' }
    git -C $target checkout --quiet $Commit
    if ($LASTEXITCODE -ne 0) { throw "git checkout $Commit failed" }
}
"RED4ext.SDK is at $Commit in $target"
