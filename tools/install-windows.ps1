$ErrorActionPreference = 'Stop'
try {
    if ($env:OS -ne 'Windows_NT') { throw 'install.cmd requires Windows.' }
    if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) { throw 'Git is required on PATH.' }
    $root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $runtimeName = if ($env:LUAUXTX_BIN) { $env:LUAUXTX_BIN } else { 'luauxtx' }
    $runtime = (Get-Command $runtimeName -CommandType Application -ErrorAction Stop).Source
    if ([IO.Path]::GetExtension($runtime) -in @('.cmd', '.bat')) {
        # Resolve launchers once; the installed command invokes native LuauXTX
        # directly and avoids CALL's second expansion of carets and percent signs.
        $probe = Join-Path $env:TEMP ('xtpkg-runtime-' + [guid]::NewGuid() + '.luau')
        try {
            [IO.File]::WriteAllText($probe, 'print(process.argv[1])', (New-Object Text.UTF8Encoding($false)))
            $resolved = & $runtime $probe
            if ($LASTEXITCODE -ne 0) { throw 'LuauXTX launcher probe failed.' }
            $runtime = ([string]($resolved -join "`n")).Trim()
        } finally { if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe } }
    }
    if (-not [IO.Path]::IsPathRooted($runtime) -or [IO.Path]::GetExtension($runtime) -ne '.exe' -or -not (Test-Path -LiteralPath $runtime -PathType Leaf)) { throw 'Set LUAUXTX_BIN to the native LuauXTX .exe.' }
    & $runtime (Join-Path $root 'src\setup\main.luau') @args
    exit $LASTEXITCODE
} catch {
    [Console]::Error.WriteLine('error: ' + $_.Exception.Message)
    exit 1
}
