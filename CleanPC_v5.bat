@echo off
:: ============================================================================
::  Windows 11 Safe Cleanup Tool  v5
:: ============================================================================
::  New in v5
::   - App caches (/apps): new and classic Teams, Discord, Slack, Steam web
::     cache, Epic launcher, Adobe media cache and peak files, Java, OneDrive
::     logs, Office add-in cache
::   - MAXIMUM clean (/max): deep + browsers + apps behind one confirmation
::   - Advanced space options. Each one explains the trade-off and asks first:
::       hibernation file reduce / off       /hibernate:reduced, off, full
::       cap System Restore storage          /shadowcap:N
::       remove Windows.old                  /windowsold
::       component store ResetBase           menu, or /repair /resetbase
::       CompactOS                           /compactos:on or off
::       reserved storage                    /reservedstorage:off or on
::   - Quick clean adds AMD / Intel / NVIDIA compute and shader caches, the
::     Windows 11 SystemTemp folder and the WER temp folder; Deep adds the
::     update orchestrator logs
::   - Developer caches add uv, Poetry, pnpm, Bun, Deno, Yarn Berry, NuGet
::     packages, Gradle wrappers, Cargo sources, node-gyp, Electron, C++
::     IntelliSense ipch, JetBrains, Cursor / VS Code Insiders, conda and
::     dangling Docker images
::   - Recycle Bin is measured and emptied on EVERY drive; Delivery
::     Optimization is measured
::   - Disk report: all drives, largest files in your profile, old Downloads,
::     WSL / Docker virtual disks, upgrade and driver-installer leftovers,
::     folders you must NOT delete by hand, CompactOS / reserved storage /
::     hibernation state
::   - "Biggest items" summary after every run; skip / fail counters are per
::     run instead of piling up across the session
::   - /ifbelow:GB - only clean when free space is below a threshold
::   - scheduled task: quick monthly, or deep monthly only when space is low;
::     catch-up for missed runs is set through the Task Scheduler API
::   - Disk Cleanup only touches handlers that exist on this PC
::   - Opera's newer profile layout, Edge Dev / Canary, Chrome Dev, DawnCache
::
::  Rules kept from 4.1 - break them and cmd misparses the script:
::   - no "::" comment inside a ( ... ) block
::   - no "echo !var! | findstr": a pipe loses delayed expansion
::   - text passed to :Say never contains redirection, pipe, ampersand
::     or percent characters
::
::  Known limitation: a path containing an exclamation mark is displayed and
::  logged with the mark stripped - a cmd delayed-expansion artefact. The
::  delete itself is unaffected.
:: ============================================================================

setlocal EnableExtensions EnableDelayedExpansion
title Windows 11 Safe Cleanup Tool v5

:: PATH hardening: with Git-Bash / Cygwin / custom tools on PATH, a bare
:: "find", "sort" or "timeout" can resolve to a foreign binary and break every
:: pipe in this script. Put the Windows folders first and use full paths.
set "PATH=%SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\Wbem;%SystemRoot%\System32\WindowsPowerShell\v1.0;%PATH%"
set "FINDSTR=%SystemRoot%\System32\findstr.exe"
set "ROBO=%SystemRoot%\System32\robocopy.exe"
set "TASKLIST=%SystemRoot%\System32\tasklist.exe"
set "SCHTASKS=%SystemRoot%\System32\schtasks.exe"
set "PS=powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command"

:: ============================== CONFIG ======================================
set "VERSION=5.0"
set "SCRIPT=%~f0"
set "DRV=%SystemDrive:~0,1%"
set "TASKNAME=CleanPC Monthly"
set "OLDTASKNAME=CleanPC Quick Monthly"
set "SVCLIST=wuauserv bits dosvc"
set "SVCPS='wuauserv','bits','dosvc'"
set "VCK=HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
set "VCKFULL=HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
:: two private Disk Cleanup profiles: the deep-clean whitelist, and one that
:: holds nothing but "Previous Installations" for the Windows.old option
set "SAGEDEEP=0099"
set "SAGEOLD=0098"
set "BROWSERPROCS=chrome.exe msedge.exe brave.exe firefox.exe opera.exe vivaldi.exe browser.exe"
set "APPPROCS=Discord.exe slack.exe Teams.exe ms-teams.exe steam.exe EpicGamesLauncher.exe AfterFX.exe "Adobe Premiere Pro.exe" "Adobe Media Encoder.exe""

:: Age-filtered walk used for temp folders. Kept in a variable so the quoting
:: stays in one place. It must contain no ! % ^ | & < > characters, because
:: cmd would eat them on the way to PowerShell.
::   - reparse points are skipped outright, so a junction dropped into %TEMP%
::     can never lead the delete outside the folder
::   - only files last written before the cutoff are removed
::   - empty sub-folders created before the cutoff are removed afterwards
::   - the byte total is returned, so temp targets report a real figure even
::     when per-item sizing is switched off
set "WALK=$ErrorActionPreference='SilentlyContinue';$r=$env:CP_PATH;$c=(Get-Date).AddDays(-1*[int]$env:CP_AGE);$d=($env:CP_DRY -eq '1');$b=[int64]0;$st=New-Object System.Collections.Stack;$st.Push($r);$dl=New-Object System.Collections.ArrayList;while($st.Count -gt 0){$p=$st.Pop();[void]$dl.Add($p);foreach($i in @(Get-ChildItem -LiteralPath $p -Force)){if($i.Attributes -band [IO.FileAttributes]::ReparsePoint){continue};if($i.PSIsContainer){$st.Push($i.FullName)}elseif($i.LastWriteTime -lt $c){$b=$b+$i.Length;if(-not $d){Remove-Item -LiteralPath $i.FullName -Force}}}};if(-not $d){for($k=$dl.Count-1;$k -ge 1;$k--){$o=Get-Item -LiteralPath $dl[$k] -Force;if($o -and -not ($o.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $o.CreationTime -lt $c -and @(Get-ChildItem -LiteralPath $dl[$k] -Force).Count -eq 0){Remove-Item -LiteralPath $dl[$k] -Force}}};[int64]($b/1MB)"

set "DRYRUN=0"
set "QUIET=0"
set "ALLUSERS=0"
set "DOPREFETCH=0"
set "RESETBASE=0"
set "MKRESTORE=0"
set "DESKTOPLOG=0"
set "SIZES=1"
set "AGE=1"
set "TASK="
set "CLI=0"
set "INVOKER="
set "BADARG="
set "UERR="
set "IFBELOW="
set "HIBMODE="
set "SHADOWCAP="
set "COMPACTMODE="
set "RESMODE="
set "ISADMIN=0"
set "EST=0"
set "FAILS=0"
set "SKIPPED=0"
set "FAILS0=0"
set "SKIPPED0=0"
set "RUNNO=0"
set "RC=0"
set "BEFORE="
set "AFTER="
set "CURACT=startup"
set "BACK=menu"

:: ============================== ARGUMENTS ===================================
:: A shift loop, not "for %%A in (%*)": FOR glob-expands any token containing
:: * or ?, which is why /? never worked in v3, and it also splits on , ; =
:parseargs
if "%~1"=="" goto :argsdone
set "A=%~1"
set "MATCH=0"
if /i "!A!"=="/dryrun"       ( set "DRYRUN=1"     & set "MATCH=1" )
if /i "!A!"=="/quiet"        ( set "QUIET=1"      & set "MATCH=1" )
if /i "!A!"=="/allusers"     ( set "ALLUSERS=1"   & set "MATCH=1" )
if /i "!A!"=="/prefetch"     ( set "DOPREFETCH=1" & set "MATCH=1" )
if /i "!A!"=="/resetbase"    ( set "RESETBASE=1"  & set "MATCH=1" )
if /i "!A!"=="/restorepoint" ( set "MKRESTORE=1"  & set "MATCH=1" )
if /i "!A!"=="/desktoplog"   ( set "DESKTOPLOG=1" & set "MATCH=1" )
if /i "!A!"=="/sizes"        ( set "SIZES=1"      & set "MATCH=1" )
if /i "!A!"=="/nosizes"      ( set "SIZES=0"      & set "MATCH=1" )
if /i "!A!"=="/quick"        ( set "TASK=quick"      & set "CLI=1" & set "MATCH=1" )
if /i "!A!"=="/deep"         ( set "TASK=deep"       & set "CLI=1" & set "MATCH=1" )
if /i "!A!"=="/browser"      ( set "TASK=browser"    & set "CLI=1" & set "MATCH=1" )
if /i "!A!"=="/apps"         ( set "TASK=apps"       & set "CLI=1" & set "MATCH=1" )
if /i "!A!"=="/devcaches"    ( set "TASK=devcache"   & set "CLI=1" & set "MATCH=1" )
if /i "!A!"=="/max"          ( set "TASK=max"        & set "CLI=1" & set "MATCH=1" )
if /i "!A!"=="/repair"       ( set "TASK=repair"     & set "CLI=1" & set "MATCH=1" )
if /i "!A!"=="/recycle"      ( set "TASK=recycle"    & set "CLI=1" & set "MATCH=1" )
if /i "!A!"=="/report"       ( set "TASK=report"     & set "CLI=1" & set "MATCH=1" )
if /i "!A!"=="/windowsold"   ( set "TASK=windowsold" & set "CLI=1" & set "MATCH=1" )
if /i "!A!"=="/help"         ( set "TASK=help"    & set "MATCH=1" )
if /i "!A!"=="/?"            ( set "TASK=help"    & set "MATCH=1" )
if /i "!A:~0,11!"=="/olderthan:"       ( set "AGE=!A:~11!"         & set "MATCH=1" )
if /i "!A:~0,9!"=="/ifbelow:"          ( set "IFBELOW=!A:~9!"      & set "MATCH=1" )
if /i "!A:~0,9!"=="/invoker:"          ( set "INVOKER=!A:~9!"      & set "MATCH=1" )
if /i "!A:~0,11!"=="/hibernate:"       ( set "HIBMODE=!A:~11!"     & set "TASK=hiber"     & set "CLI=1" & set "MATCH=1" )
if /i "!A:~0,11!"=="/shadowcap:"       ( set "SHADOWCAP=!A:~11!"   & set "TASK=shadowcap" & set "CLI=1" & set "MATCH=1" )
if /i "!A:~0,11!"=="/compactos:"       ( set "COMPACTMODE=!A:~11!" & set "TASK=compactos" & set "CLI=1" & set "MATCH=1" )
if /i "!A:~0,17!"=="/reservedstorage:" ( set "RESMODE=!A:~17!"     & set "TASK=reserved"  & set "CLI=1" & set "MATCH=1" )
if "!MATCH!"=="0" set "BADARG=!A!"
shift
goto :parseargs
:argsdone

if "%TASK%"=="help" goto :help

if defined BADARG (
    echo.
    echo  [ERROR] Unknown option: !BADARG!
    echo.
    set "RC=3"
    goto :help
)

call :IsNum "%AGE%"
if errorlevel 1 (set "UERR=/olderthan: needs a whole number of days" & goto :usageerror)

if defined IFBELOW (
    call :IsNum "!IFBELOW!"
    if errorlevel 1 (set "UERR=/ifbelow: needs a whole number of GB" & goto :usageerror)
)

if "%TASK%"=="hiber" (
    set "OK=0"
    for %%M in (off reduced full) do if /i "!HIBMODE!"=="%%M" set "OK=1"
    if "!OK!"=="0" (set "UERR=/hibernate: must be off, reduced or full" & goto :usageerror)
)

if "%TASK%"=="shadowcap" (
    call :IsNum "!SHADOWCAP!"
    if errorlevel 1 (set "UERR=/shadowcap: needs a number from 2 to 50" & goto :usageerror)
    if !SHADOWCAP! LSS 2 (set "UERR=/shadowcap: needs a number from 2 to 50" & goto :usageerror)
    if !SHADOWCAP! GTR 50 (set "UERR=/shadowcap: needs a number from 2 to 50" & goto :usageerror)
)

if "%TASK%"=="compactos" (
    set "OK=0"
    for %%M in (on off) do if /i "!COMPACTMODE!"=="%%M" set "OK=1"
    if "!OK!"=="0" (set "UERR=/compactos: must be on or off" & goto :usageerror)
)

if "%TASK%"=="reserved" (
    set "OK=0"
    for %%M in (on off) do if /i "!RESMODE!"=="%%M" set "OK=1"
    if "!OK!"=="0" (set "UERR=/reservedstorage: must be off or on" & goto :usageerror)
)

:: The interactive menu waits for key presses, so it cannot run unattended.
if "%QUIET%"=="1" if not defined TASK (set "UERR=/quiet needs an action such as /quick - the menu cannot run unattended" & goto :usageerror)

if "%QUIET%"=="0" color 0B

:: ============================== ADMIN / ELEVATE =============================
:: fltmc is the reliable probe; "net session" fails when the Server service
:: is disabled.
fltmc >nul 2>&1
if not errorlevel 1 (
    set "ISADMIN=1"
    goto :isadmin
)

if "%DRYRUN%"=="1" (
    echo  [i] Not elevated - dry run continues, some folders will be unreadable.
    goto :isadmin
)

echo  [i] Administrator rights required - requesting elevation...
:: The invoking user is carried across: if UAC is satisfied by a DIFFERENT
:: admin account, every %%TEMP%% / %%LOCALAPPDATA%% path would resolve to that
:: account and the wrong profile would be cleaned. The child warns instead.
:: Path and arguments reach PowerShell through environment variables, so a
:: username with a space or a path with an apostrophe cannot break the call.
set "CP_SELF=%SCRIPT%"
set "CP_ARGS=%* "/invoker:%USERNAME%""
%PS% "try{Start-Process -Verb RunAs -FilePath $env:CP_SELF -ArgumentList $env:CP_ARGS -ErrorAction Stop}catch{exit 1}" >nul 2>&1
if errorlevel 1 (
    echo  [ERROR] Elevation was refused or failed.
    if "%QUIET%"=="0" pause
    endlocal & exit /b 1
)
endlocal & exit /b 0
:isadmin

:: ============================== WORKING FOLDER ==============================
set "APPDIR=%LOCALAPPDATA%\CleanPC"
if not exist "%APPDIR%\" md "%APPDIR%" >nul 2>&1
if not exist "%APPDIR%\" set "APPDIR=%TEMP%\CleanPC"
if not exist "%APPDIR%\" md "%APPDIR%" >nul 2>&1

:: Empty source folder for the robocopy /MIR purge. Force it empty every run:
:: if anything ever landed in here it would be COPIED INTO every purge target.
set "EMPTYDIR=%APPDIR%\empty"
if not exist "%EMPTYDIR%\" md "%EMPTYDIR%" >nul 2>&1
del /f /q /a "%EMPTYDIR%\*" >nul 2>&1
for /d %%d in ("%EMPTYDIR%\*") do rd /s /q "%%d" >nul 2>&1

:: ============================== LOG PATHS ===================================
set "LOGDIR=%APPDIR%"
if "%DESKTOPLOG%"=="1" call :ResolveDesktop
set "LOG=%LOGDIR%\Cleanup_Log.txt"
set "CSV=%LOGDIR%\Cleanup_Log.csv"

if exist "%LOG%" for %%F in ("%LOG%") do if %%~zF GTR 1048576 move /y "%LOG%" "%LOG%.old" >nul 2>&1
if exist "%CSV%" for %%F in ("%CSV%") do if %%~zF GTR 1048576 move /y "%CSV%" "%CSV%.old" >nul 2>&1
if not exist "%CSV%" >"%CSV%" echo "session","time","mode","action","target","megabytes","result"

for /f "usebackq delims=" %%T in (`%PS% "(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')"`) do set "SESSION=%%T"
if not defined SESSION set "SESSION=unknown"

>>"%LOG%" echo.
>>"%LOG%" echo ==========================================================
>>"%LOG%" echo  Session start: %SESSION%  v%VERSION%  dryrun=%DRYRUN% quiet=%QUIET% task=%TASK% olderthan=%AGE% sizes=%SIZES% admin=%ISADMIN%
>>"%LOG%" echo ==========================================================

if defined INVOKER if /i not "%INVOKER%"=="%USERNAME%" (
    call :Say "  [W] Elevated as '%USERNAME%' but launched by '%INVOKER%'."
    call :Say "  [W] Per-user targets such as temp and browser caches belong to '%USERNAME%'."
    call :Say "  [W] Run the script from an admin account of '%INVOKER%' to clean that profile."
    if "%QUIET%"=="0" call :Sleep 3
)

:: /ifbelow:GB - for schedules: do nothing while there is plenty of space.
if defined IFBELOW (
    %PS% "if(((Get-PSDrive %DRV%).Free/1GB) -lt [double]$env:IFBELOW){exit 0}else{exit 1}"
    if errorlevel 1 (
        echo  [i] %SystemDrive% has at least %IFBELOW% GB free - nothing to do.
        call :Log "free space is at least %IFBELOW% GB - skipped because of /ifbelow"
        goto :end
    )
)

:: ============================== DISPATCH ====================================
if "%TASK%"=="quick"      goto :quick
if "%TASK%"=="deep"       goto :deep
if "%TASK%"=="browser"    goto :browser
if "%TASK%"=="apps"       goto :apps
if "%TASK%"=="devcache"   goto :devcache
if "%TASK%"=="max"        goto :max
if "%TASK%"=="repair"     goto :repair
if "%TASK%"=="recycle"    goto :recycle
if "%TASK%"=="report"     goto :report
if "%TASK%"=="windowsold" goto :windowsold
if "%TASK%"=="hiber"      goto :hiber
if "%TASK%"=="shadowcap"  goto :shadowcap
if "%TASK%"=="compactos"  goto :compactos
if "%TASK%"=="reserved"   goto :reserved

:: ============================== MAIN MENU ===================================
:menu
set "BACK=menu"
cls
echo ==========================================================
echo        Windows 11 Safe Cleanup Tool  v5
echo ==========================================================
echo.
call :ShowSpace
echo.
if "%DRYRUN%"=="1" (echo   MODE: DRY RUN - nothing will be deleted) else (echo   MODE: LIVE - files will be deleted)
echo   Temp files younger than %AGE% day^(s^) are left alone.
echo.
echo   [1] Quick clean        temp, crash dumps, error reports, shader caches
echo   [2] Deep clean         quick + update cache + logs + Disk Cleanup + bin
echo   [3] Browser caches     every profile - cookies, logins, history kept
echo   [4] App caches         Teams, Discord, Slack, Steam, Epic, Adobe ...
echo   [5] Developer caches   pip, npm, NuGet, Gradle, Cargo, Docker ...
echo   [6] MAXIMUM clean      deep + browsers + apps in one go
echo   [7] Advanced space     hibernation, restore points, Windows.old ...
echo   [8] System repair      DISM + SFC
echo   [9] Empty Recycle Bin  all drives
echo   [R] Disk report        where the space went, what else can be freed
echo   [D] Toggle DRY RUN
echo   [L] View log
echo   [S] Create the monthly scheduled task     [U] Remove it
echo   [0] Exit
echo.
choice /c 123456789RDLSU0 /n /m "   Select an option: "
set "SEL=%errorlevel%"
if "%SEL%"=="1"  goto :quick
if "%SEL%"=="2"  goto :deep
if "%SEL%"=="3"  goto :browser
if "%SEL%"=="4"  goto :apps
if "%SEL%"=="5"  goto :devcache
if "%SEL%"=="6"  goto :max
if "%SEL%"=="7"  goto :advanced
if "%SEL%"=="8"  goto :repair
if "%SEL%"=="9"  goto :recycle
if "%SEL%"=="10" goto :report
if "%SEL%"=="11" goto :toggledry
if "%SEL%"=="12" goto :viewlog
if "%SEL%"=="13" goto :schedule
if "%SEL%"=="14" goto :unschedule
if "%SEL%"=="15" goto :end
goto :menu

:toggledry
if "%DRYRUN%"=="1" (set "DRYRUN=0") else (set "DRYRUN=1")
goto :menu

:: ============================== ADVANCED MENU ===============================
:advanced
set "BACK=advanced"
set "HIBMODE="
set "SHADOWCAP="
set "COMPACTMODE="
set "RESMODE="
cls
echo ==========================================================
echo   Advanced space options - each one explains itself and asks
echo ==========================================================
echo.
call :ShowSpace
echo.
call :FileMB "%SystemDrive%\hiberfil.sys" HSZ
set "WOLD=not present"
if exist "%SystemDrive%\Windows.old\" set "WOLD=PRESENT - can be removed"
echo   [1] Hibernation file     hiberfil.sys is currently !HSZ! MB
echo   [2] System Restore cap   limit how much disk restore points may use
echo   [3] Remove Windows.old   !WOLD!
echo   [4] Component store      DISM ResetBase - drops superseded updates
echo   [5] CompactOS            compress Windows files, often 2-4 GB
echo   [6] Reserved storage     the ~7 GB Windows keeps back for updates
echo   [0] Back
echo.
if "%DRYRUN%"=="1" echo   DRY RUN is on - these only describe what they would do.
choice /c 1234560 /n /m "   Select an option: "
set "SEL=%errorlevel%"
if "%SEL%"=="1" goto :hiber
if "%SEL%"=="2" goto :shadowcap
if "%SEL%"=="3" goto :windowsold
if "%SEL%"=="4" goto :resetbase
if "%SEL%"=="5" goto :compactos
if "%SEL%"=="6" goto :reserved
if "%SEL%"=="7" goto :menu
goto :advanced

:: ============================== QUICK =======================================
:quick
call :Banner "Quick clean"
call :GetFree BEFORE
call :Log "--- quick clean ---"
call :QuickTargets
call :Finish
goto :after

:: ============================== DEEP ========================================
:deep
call :Banner "Deep clean"
call :DescribeDeep
echo.
call :ConfirmYN "Continue?" || goto :afterorexit
call :RestorePoint
call :GetFree BEFORE
call :Log "--- deep clean ---"
call :DeepTargets
call :Finish
goto :after

:: ============================== BROWSERS ====================================
:browser
call :Banner "Browser cache cleanup"
set "PROCS=%BROWSERPROCS%"
call :CheckRunning
if defined RUNNING (
    call :Say "  [W] Running:!RUNNING!"
    call :Say "  [W] Their locked cache files will be skipped. Close them for best results."
    echo.
)
call :ConfirmYN "Clear browser caches now?" || goto :afterorexit
call :GetFree BEFORE
call :Log "--- browser caches ---"
call :BrowserTargets
call :Finish
goto :after

:: ============================== APPS ========================================
:apps
call :Banner "App caches"
echo   Cache folders of Teams, Discord, Slack, Steam, Epic, Adobe, Java,
echo   OneDrive logs and Office add-ins. Chats, settings, logins and game files
echo   are not touched. The apps rebuild these caches as needed.
echo.
set "PROCS=%APPPROCS%"
call :CheckRunning
if defined RUNNING (
    call :Say "  [W] Running:!RUNNING!"
    call :Say "  [W] Their locked files will be skipped. Close them for best results."
    echo.
)
call :ConfirmYN "Clear app caches now?" || goto :afterorexit
call :GetFree BEFORE
call :Log "--- app caches ---"
call :AppTargets
call :Finish
goto :after

:: ============================== DEV CACHES ==================================
:devcache
call :Banner "Developer caches"
echo   Everything below is safe to delete but is downloaded or rebuilt again
echo   on the next build, which costs time and bandwidth. That is why it is
echo   opt-in and never part of Quick, Deep or MAXIMUM clean.
echo.
call :ConfirmYN "Continue?" || goto :afterorexit
call :GetFree BEFORE
call :Log "--- developer caches ---"
call :DevTargets
call :Finish
goto :after

:: ============================== MAXIMUM =====================================
:max
call :Banner "Maximum clean"
echo   Runs in one go:
echo     - Deep clean: temp, dumps, error reports, shader caches, update cache,
echo       Delivery Optimization, old Windows logs, Disk Cleanup, Recycle Bin
echo     - Browser caches of every profile - cookies, logins, history kept
echo     - App caches: Teams, Discord, Slack, Steam, Epic, Adobe, OneDrive logs
echo.
echo   Not included: developer caches and the Advanced options. Those cost
echo   rebuild time or change how Windows behaves, so they stay separate.
echo.
set "PROCS=%BROWSERPROCS% %APPPROCS%"
call :CheckRunning
if defined RUNNING (
    call :Say "  [W] Running:!RUNNING!"
    call :Say "  [W] Their locked files will be skipped. Close them for best results."
    echo.
)
call :ConfirmYN "Start the maximum clean?" || goto :afterorexit
call :RestorePoint
call :GetFree BEFORE
call :Log "--- maximum clean ---"
call :DeepTargets
call :BrowserTargets
call :AppTargets
call :Finish
goto :after

:: ============================== REPAIR ======================================
:repair
call :Banner "System repair"
echo   Order used: DISM ScanHealth -^> RestoreHealth -^> SFC -^> component store
echo   DISM goes first: SFC cannot repair from a broken component store.
echo   This can take 15-40 minutes. Do not interrupt.
if "%RESETBASE%"=="1" echo   /resetbase given: superseded updates become NON-uninstallable.
echo.
call :ConfirmYN "Continue?" || goto :afterorexit
if "%DRYRUN%"=="1" (
    call :Say "  [DRY] would run DISM ScanHealth, RestoreHealth, SFC, StartComponentCleanup"
    if "%ISADMIN%"=="1" DISM /Online /Cleanup-Image /AnalyzeComponentStore
    goto :after
)
call :RestorePoint
call :GetFree BEFORE
call :Log "--- system repair ---"

call :Say "  [*] DISM /ScanHealth ..."
DISM /Online /Cleanup-Image /ScanHealth
call :Log "DISM ScanHealth exit=!errorlevel!"

call :Say "  [*] DISM /RestoreHealth ..."
DISM /Online /Cleanup-Image /RestoreHealth
set "RCD=!errorlevel!"
call :Log "DISM RestoreHealth exit=!RCD!"
if not "!RCD!"=="0" (
    set /a FAILS+=1
    call :Say "  [W] RestoreHealth returned !RCD! - if 0x800f081f, add /Source:WIM:X:\sources\install.wim:1 /LimitAccess"
)

call :Say "  [*] SFC /scannow ..."
sfc /scannow
set "RCS=!errorlevel!"
call :Log "SFC exit=!RCS!  details: %SystemRoot%\Logs\CBS\CBS.log"
if not "!RCS!"=="0" set /a FAILS+=1

call :Say "  [*] DISM /StartComponentCleanup ..."
if "%RESETBASE%"=="1" (
    DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase
) else (
    DISM /Online /Cleanup-Image /StartComponentCleanup
)
call :Log "StartComponentCleanup exit=!errorlevel!"
call :Finish
call :Say "  [i] A restart is recommended."
goto :after

:: ============================== RECYCLE BIN =================================
:recycle
call :Banner "Empty Recycle Bin"
call :GetFree BEFORE
call :EmptyBin
call :Finish
goto :after

:: ============================== ADVANCED: HIBERNATION =======================
:hiber
call :Banner "Hibernation file"
call :FileMB "%SystemDrive%\hiberfil.sys" HSZ
echo   hiberfil.sys currently uses !HSZ! MB. Its size follows your RAM.
echo.
echo   reduced - roughly halves the file. Fast Startup keeps working; only the
echo             Hibernate power option goes away. Good choice for desktops.
echo   off     - deletes the file. Also turns off Fast Startup and Hibernate;
echo             a laptop can then no longer hibernate on low battery.
echo   full    - restores normal hibernation.
echo.
if defined HIBMODE goto :hiber_go
choice /c ROFC /n /m "   [R]educed, [O]ff, [F]ull or [C]ancel: "
set "CHO=%errorlevel%"
if "%CHO%"=="1" set "HIBMODE=reduced"
if "%CHO%"=="2" set "HIBMODE=off"
if "%CHO%"=="3" set "HIBMODE=full"
if "%CHO%"=="4" goto :afterorexit
:hiber_go
if "%DRYRUN%"=="1" (
    call :Say "  [DRY] would set hibernation to: !HIBMODE!"
    goto :after
)
call :GetFree BEFORE
call :Log "--- hibernation %HIBMODE% ---"
if /i "%HIBMODE%"=="off" powercfg /h off
if /i "%HIBMODE%"=="reduced" (
    powercfg /h on
    powercfg /h /type reduced
)
if /i "%HIBMODE%"=="full" (
    powercfg /h on
    powercfg /h /type full
)
if errorlevel 1 (
    call :Say "  [W] powercfg reported an error - see the message above."
    set /a FAILS+=1
) else (
    call :Say "  [OK] Hibernation set to: %HIBMODE%"
)
call :FileMB "%SystemDrive%\hiberfil.sys" HSZ2
call :Say "  [i] hiberfil.sys is now !HSZ2! MB"
call :Finish
goto :after

:: ============================== ADVANCED: RESTORE CAP =======================
:shadowcap
call :Banner "Cap System Restore storage"
echo   Restore-point storage on %SystemDrive% right now:
vssadmin list shadowstorage /for=%SystemDrive% 2>nul | "%FINDSTR%" /i "Used Allocated Maximum"
if errorlevel 1 echo     none reported - System Restore is probably off for this drive.
echo.
echo   A lower cap makes Windows delete the OLDEST restore points until the
echo   rest fits. Newer points are kept. 5 to 10 percent is a sensible cap.
echo.
if defined SHADOWCAP goto :shadow_go
choice /c 12345C /n /m "   Cap at [1] 3, [2] 5, [3] 8, [4] 10, [5] 15 percent, or [C]ancel: "
set "CHO=%errorlevel%"
if "%CHO%"=="1" set "SHADOWCAP=3"
if "%CHO%"=="2" set "SHADOWCAP=5"
if "%CHO%"=="3" set "SHADOWCAP=8"
if "%CHO%"=="4" set "SHADOWCAP=10"
if "%CHO%"=="5" set "SHADOWCAP=15"
if "%CHO%"=="6" goto :afterorexit
:shadow_go
if "%DRYRUN%"=="1" (
    call :Say "  [DRY] would cap restore-point storage at !SHADOWCAP! percent"
    goto :after
)
call :GetFree BEFORE
call :Log "--- restore-point storage cap %SHADOWCAP% percent ---"
vssadmin resize shadowstorage /for=%SystemDrive% /on=%SystemDrive% /maxsize=%SHADOWCAP%%%
if errorlevel 1 (
    call :Say "  [W] vssadmin could not resize - System Restore may be off for %SystemDrive%"
    set /a FAILS+=1
) else (
    call :Say "  [OK] Restore-point storage capped at %SHADOWCAP% percent"
)
call :Finish
goto :after

:: ============================== ADVANCED: WINDOWS.OLD =======================
:windowsold
call :Banner "Remove the previous Windows installation"
if not exist "%SystemDrive%\Windows.old\" (
    call :Say "  [~] There is no Windows.old folder - nothing to remove."
    goto :after
)
echo   Measuring Windows.old ...
call :DirSize "%SystemDrive%\Windows.old" WOSZ
echo   Windows.old holds about !WOSZ! MB.
echo.
echo   Removing it means you can NO LONGER go back to the previous Windows
echo   version from Settings - System - Recovery. Windows deletes it on its
echo   own about 10 days after an upgrade anyway.
echo.
call :ConfirmYN "Remove Windows.old now?" || goto :afterorexit
if "%DRYRUN%"=="1" (
    call :Say "  [DRY] !WOSZ! MB  Windows.old - would be removed through Disk Cleanup"
    call :Csv "%SystemDrive%\Windows.old" "!WOSZ!" "dryrun"
    goto :after
)
call :GetFree BEFORE
call :Log "--- remove Windows.old ---"
call :SageReset %SAGEOLD%
call :SageEnable %SAGEOLD% "Previous Installations"
call :RunSage %SAGEOLD%
set /a EST+=WOSZ
if exist "%SystemDrive%\Windows.old\" (
    call :Say "  [W] Windows.old is still there - Disk Cleanup could not remove all of it."
    set /a FAILS+=1
    call :Csv "%SystemDrive%\Windows.old" "!WOSZ!" "partial"
) else (
    call :Csv "%SystemDrive%\Windows.old" "!WOSZ!" "cleaned"
)
call :Finish
goto :after

:: ============================== ADVANCED: RESETBASE =========================
:resetbase
call :Banner "Component store cleanup with ResetBase"
echo   Removes every superseded version of every Windows component from
echo   WinSxS. Installed updates can NO LONGER be uninstalled afterwards.
echo   Takes 5-30 minutes.
echo.
if "%ISADMIN%"=="1" DISM /Online /Cleanup-Image /AnalyzeComponentStore
echo.
call :ConfirmYN "Run StartComponentCleanup /ResetBase now?" || goto :afterorexit
if "%DRYRUN%"=="1" (
    call :Say "  [DRY] would run DISM /StartComponentCleanup /ResetBase"
    goto :after
)
call :GetFree BEFORE
call :Log "--- component store ResetBase ---"
DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase
set "RCD=!errorlevel!"
call :Log "StartComponentCleanup ResetBase exit=!RCD!"
if not "!RCD!"=="0" (
    call :Say "  [W] DISM returned !RCD! - a pending update or restart can block this."
    set /a FAILS+=1
)
call :Finish
goto :after

:: ============================== ADVANCED: COMPACTOS =========================
:compactos
call :Banner "CompactOS"
compact /compactos:query
echo.
echo   on  - compresses the Windows system files, usually freeing 2 to 4 GB.
echo         Takes 10-20 minutes. The CPU cost is negligible on modern PCs and
echo         it is well worth it on small SSDs and eMMC laptops.
echo   off - decompresses them again and needs that space back.
echo.
if defined COMPACTMODE goto :compact_go
choice /c EDC /n /m "   [E]nable, [D]isable or [C]ancel: "
set "CHO=%errorlevel%"
if "%CHO%"=="1" set "COMPACTMODE=on"
if "%CHO%"=="2" set "COMPACTMODE=off"
if "%CHO%"=="3" goto :afterorexit
:compact_go
if "%DRYRUN%"=="1" (
    call :Say "  [DRY] would switch CompactOS !COMPACTMODE!"
    goto :after
)
call :GetFree BEFORE
call :Log "--- CompactOS %COMPACTMODE% ---"
if /i "%COMPACTMODE%"=="on" (compact /compactos:always) else (compact /compactos:never)
if errorlevel 1 (
    call :Say "  [W] compact reported an error - see the message above."
    set /a FAILS+=1
) else (
    call :Say "  [OK] CompactOS switched %COMPACTMODE%"
)
call :Finish
goto :after

:: ============================== ADVANCED: RESERVED STORAGE ==================
:reserved
call :Banner "Reserved storage"
if "%ISADMIN%"=="1" DISM /Online /Get-ReservedStorageState
echo.
echo   Windows keeps about 7 GB reserved so updates always have room.
echo   off - gives that space back. Big updates may then fail on a full disk.
echo   on  - restores the reservation. Recommended unless space is very tight.
echo   Changing it fails while an update is pending - restart first if so.
echo.
if defined RESMODE goto :res_go
choice /c DEC /n /m "   [D]isable, [E]nable or [C]ancel: "
set "CHO=%errorlevel%"
if "%CHO%"=="1" set "RESMODE=off"
if "%CHO%"=="2" set "RESMODE=on"
if "%CHO%"=="3" goto :afterorexit
:res_go
if "%DRYRUN%"=="1" (
    call :Say "  [DRY] would switch reserved storage !RESMODE!"
    goto :after
)
call :GetFree BEFORE
call :Log "--- reserved storage %RESMODE% ---"
if /i "%RESMODE%"=="off" (DISM /Online /Set-ReservedStorageState /State:Disabled) else (DISM /Online /Set-ReservedStorageState /State:Enabled)
if errorlevel 1 (
    call :Say "  [W] DISM could not change reserved storage - restart and try again."
    set /a FAILS+=1
) else (
    call :Say "  [OK] Reserved storage switched %RESMODE%"
)
call :Finish
goto :after

:: ============================== DISK REPORT =================================
:report
call :Banner "Disk report"
set "SIZESAVE=%SIZES%"
set "SIZES=1"
echo   Drives
%PS% "foreach($d in @(Get-PSDrive -PSProvider FileSystem)){if($d.Used -ne $null){$t=$d.Used+$d.Free; if($t -gt 0){'  {0}:  {1,8:N1} GB free of {2,8:N1} GB  - {3:N0} percent free' -f $d.Name,($d.Free/1GB),($t/1GB),($d.Free*100/$t)}}}"
echo.
echo   Areas this tool cleans - sizes in MB
for %%D in (
    "%TEMP%" "%SystemRoot%\Temp" "%SystemRoot%\SystemTemp" "%SystemRoot%\Prefetch"
    "%SystemRoot%\Logs" "%SystemRoot%\SoftwareDistribution\Download"
    "%LOCALAPPDATA%\CrashDumps" "%ProgramData%\Microsoft\Windows\WER"
    "%LOCALAPPDATA%\D3DSCache" "%LOCALAPPDATA%\NVIDIA" "%LOCALAPPDATA%\AMD"
    "%LOCALAPPDATA%\Microsoft\Windows\Explorer"
    "%LOCALAPPDATA%\Google\Chrome\User Data" "%LOCALAPPDATA%\Microsoft\Edge\User Data"
    "%APPDATA%\discord" "%APPDATA%\Slack" "%APPDATA%\Microsoft\Teams"
    "%APPDATA%\Adobe\Common" "%LOCALAPPDATA%\pip\cache" "%LOCALAPPDATA%\npm-cache"
    "%USERPROFILE%\.nuget\packages" "%USERPROFILE%\.gradle\caches"
) do call :Report1 "%%~D" ""
echo.
echo   Big system files
%PS% "foreach($n in 'hiberfil.sys','pagefile.sys','swapfile.sys'){$i=Get-Item -LiteralPath (Join-Path $env:SystemDrive $n) -Force -ErrorAction SilentlyContinue; if($i){'  {0,-52}{1,9:N0} MB' -f $i.FullName,($i.Length/1MB)}}"
call :BinSize BSZ
echo   Recycle Bin on all drives                           !BSZ! MB
echo   hiberfil.sys can be shrunk with Advanced option 1.
echo.
echo   Upgrade and driver-installer leftovers
for %%D in (
    "%SystemDrive%\Windows.old" "%SystemDrive%\$WINDOWS.~BT" "%SystemDrive%\$Windows.~WS"
    "%SystemDrive%\ESD" "%SystemDrive%\NVIDIA" "%SystemDrive%\AMD"
) do call :Report1 "%%~D" ""
echo   Windows.old: Advanced option 3. $WINDOWS.~BT and ~WS: Deep clean.
echo   NVIDIA and AMD folders hold unpacked driver installers - safe to delete
echo   by hand once the driver is installed.
echo.
echo   Do NOT delete these by hand
call :Report1 "%SystemRoot%\Installer"                          "msi repair data - never delete"
call :Report1 "%ProgramData%\Package Cache"                     "installer cache - breaks repair and uninstall"
call :Report1 "%SystemRoot%\System32\DriverStore\FileRepository" "drivers - remove only with pnputil"
call :Report1 "%ProgramData%\Microsoft\Search\Data"             "search index - rebuild via Indexing Options"
call :Report1 "%USERPROFILE%\.m2\repository"                    "Maven repo - may hold artifacts built here"
echo.
echo   WSL and Docker virtual disks
%PS% "$found=0; foreach($r in @((Join-Path $env:LOCALAPPDATA 'Packages'),(Join-Path $env:LOCALAPPDATA 'Docker'),(Join-Path $env:LOCALAPPDATA 'wsl'))){ if(Test-Path -LiteralPath $r){ foreach($v in @(Get-ChildItem -LiteralPath $r -Recurse -Depth 3 -Filter *.vhdx -File -Force -ErrorAction SilentlyContinue)){ $found++; '  {0,9:N0} MB  {1}' -f ($v.Length/1MB),$v.FullName } } }; if($found -eq 0){'  none found'}"
echo   These virtual disks never shrink by themselves. To compact one: run
echo   wsl --shutdown, then in diskpart: select vdisk file=PATH, attach vdisk
echo   readonly, compact vdisk, detach vdisk.
echo.
echo   Largest files in your profile - over 100 MB, cloud-only files ignored
echo   This can take a minute ...
%PS% "$x=0x441000; Get-ChildItem -LiteralPath $env:USERPROFILE -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 100MB -and -not ([int]$_.Attributes -band $x) } | Sort-Object Length -Descending | Select-Object -First 15 | ForEach-Object { '  {0,9:N0} MB  {1}' -f ($_.Length/1MB),$_.FullName }"
echo.
%PS% "$p=(New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path; if($p -and (Test-Path -LiteralPath $p)){$c=(Get-Date).AddDays(-90); $f=@(Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $c }); $s=[int64]0; foreach($i in $f){$s=$s+$i.Length}; '  Downloads: {0} files older than 90 days, {1:N0} MB in total.' -f $f.Count,($s/1MB); '  Review them by hand - this tool never deletes anything in Downloads.'}"
echo.
echo   Windows settings that affect disk use
compact /compactos:query
if "%ISADMIN%"=="1" DISM /Online /Get-ReservedStorageState
echo.
echo   System Restore usage
vssadmin list shadowstorage /for=%SystemDrive% 2>nul | "%FINDSTR%" /i "Used Allocated Maximum"
echo.
if "%ISADMIN%"=="1" (
    echo   Component store analysis - takes a moment
    DISM /Online /Cleanup-Image /AnalyzeComponentStore
    echo.
)
where docker >nul 2>&1 && docker system df 2>nul
echo.
echo   [i] For a full visual map use WizTree or TreeSize Free.
set "SIZES=%SIZESAVE%"
goto :after

:: ============================== SCHEDULED TASK ==============================
:schedule
call :Banner "Create the monthly scheduled task"
echo   Task name : %TASKNAME%
echo   Schedule  : day 1 of every month at 12:00, caught up later if the PC
echo               was off at that time
echo   Privileges: highest available, not started on battery
echo.
echo   [Q] Quick clean every month - recommended
echo   [D] Deep clean every month, but only while %SystemDrive% has under 30 GB free
echo   [C] Cancel
echo.
choice /c QDC /n /m "   Choose: "
set "CHO=%errorlevel%"
if "%CHO%"=="3" goto :afterorexit
set "TARGS=/quick /quiet /nosizes"
if "%CHO%"=="2" set "TARGS=/deep /quiet /nosizes /ifbelow:30"
"%SCHTASKS%" /query /tn "%OLDTASKNAME%" >nul 2>&1
if not errorlevel 1 (
    "%SCHTASKS%" /delete /tn "%OLDTASKNAME%" /f >nul 2>&1
    call :Say "  [i] Removed the old v4 task '%OLDTASKNAME%' - replaced by this one."
)
"%SCHTASKS%" /create /tn "%TASKNAME%" /tr "\"%SCRIPT%\" %TARGS%" /sc monthly /d 1 /st 12:00 /rl highest /f
if errorlevel 1 (
    call :Say "  [W] Task creation failed."
    set /a FAILS+=1
    goto :after
)
%PS% "try{$t=Get-ScheduledTask -TaskName $env:TASKNAME -ErrorAction Stop; $t.Settings.StartWhenAvailable=$true; $t.Settings.DisallowStartIfOnBatteries=$true; $t.Settings.StopIfGoingOnBatteries=$true; $t.Settings.ExecutionTimeLimit='PT2H'; Set-ScheduledTask -InputObject $t -ErrorAction Stop | Out-Null; exit 0}catch{exit 1}" >nul 2>&1
if errorlevel 1 (
    call :Say "  [W] Task created, but catch-up for missed runs could not be switched on."
) else (
    call :Say "  [OK] Task created with catch-up: !TARGS!"
)
goto :after

:unschedule
call :Banner "Remove the scheduled task"
call :ConfirmYN "Delete the task '%TASKNAME%'?" || goto :afterorexit
"%SCHTASKS%" /delete /tn "%OLDTASKNAME%" /f >nul 2>&1
"%SCHTASKS%" /delete /tn "%TASKNAME%" /f
if errorlevel 1 (call :Say "  [W] Task not found or could not be deleted.") else (call :Say "  [OK] Task removed.")
goto :after

:: ============================== VIEW LOG ====================================
:viewlog
if exist "%LOG%" (start "" notepad "%LOG%") else (echo   [i] No log yet. & call :Sleep 2)
goto :menu

:: ============================== AFTER AN ACTION =============================
:afterorexit
if "%CLI%"=="1" goto :end
goto :%BACK%

:after
echo.
:: A command-line action exits when it is finished.
if "%CLI%"=="1" goto :end
if "%QUIET%"=="1" goto :end
pause
goto :%BACK%

:: ############################################################################
:: #                              SUBROUTINES                                 #
:: ############################################################################

:Sleep
:: %1 = seconds. ping, not timeout: timeout fails when stdin is redirected,
:: which is exactly the case under Task Scheduler.
set /a SLP=%~1+1
ping -n !SLP! 127.0.0.1 >nul 2>&1
exit /b 0

:Banner
:: Every run gets its own number so the CSV summary and the skip / fail
:: counters only cover this run.
set /a RUNNO+=1
set "CURACT=%~1 #!RUNNO!"
set /a FAILS0=FAILS
set /a SKIPPED0=SKIPPED
cls
echo ==========================================================
echo   %~1
if "%DRYRUN%"=="1" echo   *** DRY RUN - nothing is deleted ***
echo ==========================================================
echo.
exit /b 0

:Say
echo %~1
>>"%LOG%" echo [%TIME%] %~1
exit /b 0

:Log
>>"%LOG%" echo [%TIME%] %~1
exit /b 0

:Csv
:: %1 = target, %2 = megabytes (or "-"), %3 = result. Every field is quoted
:: because %TIME% uses a comma as the decimal separator in many locales.
set "CMODE=live"
if "%DRYRUN%"=="1" set "CMODE=dry"
>>"%CSV%" echo "%SESSION%","%TIME%","%CMODE%","%CURACT%","%~1","%~2","%~3"
exit /b 0

:ConfirmYN
if "%QUIET%"=="1" exit /b 0
choice /c YN /n /m "   %~1 [Y/N]: "
if errorlevel 2 (
    echo    Cancelled.
    call :Sleep 1
    exit /b 1
)
exit /b 0

:IsNum
:: errorlevel 0 when %1 is a non-empty string of digits. No pipe: a pipe
:: would lose delayed expansion.
set "NV=%~1"
if not defined NV exit /b 1
for /f "delims=0123456789" %%X in ("!NV!") do exit /b 1
exit /b 0

:ResolveDesktop
:: %USERPROFILE%\Desktop does not exist when the Desktop is redirected to
:: OneDrive, so read the real location from the shell folder registry.
set "DESKTOP="
for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" /v Desktop 2^>nul ^| "%FINDSTR%" /i "REG_SZ"') do set "DESKTOP=%%B"
if defined DESKTOP for /f "tokens=* delims= " %%D in ("!DESKTOP!") do set "DESKTOP=%%D"
if not defined DESKTOP set "DESKTOP=%USERPROFILE%\Desktop"
if exist "!DESKTOP!\" set "LOGDIR=!DESKTOP!"
exit /b 0

:GetFree
:: %1 = variable name to receive free bytes. [int64] forces plain digits:
:: PowerShell can otherwise render a large double as 1.2345E+11.
set "%~1="
for /f "usebackq delims=" %%A in (`%PS% "[int64](Get-PSDrive %DRV%).Free"`) do set "%~1=%%A"
if not defined %~1 set "%~1=0"
exit /b 0

:ShowSpace
%PS% "$d=Get-PSDrive %DRV%; $t=$d.Used+$d.Free; Write-Host '   Drive %DRV%:' -ForegroundColor Cyan; Write-Host ('   Free : {0,8:N2} GB  ({1,4:N1}%%)' -f ($d.Free/1GB),(($d.Free/$t)*100)) -ForegroundColor Green; Write-Host ('   Used : {0,8:N2} GB  ({1,4:N1}%%)' -f ($d.Used/1GB),(($d.Used/$t)*100)) -ForegroundColor Yellow; Write-Host ('   Total: {0,8:N2} GB' -f ($t/1GB))"
exit /b 0

:BytesToMB
:: %1 = byte count as a string, %2 = out var. SET /A is 32-bit signed, so
:: for long values drop the last six digits first and scale by the exact
:: ratio 1000000/1048576 = 15625/16384, which keeps every step in range.
setlocal EnableExtensions DisableDelayedExpansion
set "B=%~1"
if not defined B set "B=0"
if "%B:~9%"=="" (
    set /a MBOUT=B/1048576
) else (
    set "HI=%B:~0,-6%"
    set /a MBOUT=HI*15625/16384
)
endlocal & set "%~2=%MBOUT%"
exit /b 0

:FileMB
:: %1 = file, %2 = out var (MB). 0 when the file does not exist.
set "%~2=0"
if not exist "%~1" exit /b 0
for %%F in ("%~1") do call :BytesToMB "%%~zF" %~2
exit /b 0

:DirSize
:: %1 = path, %2 = out var (integer MB). The path travels through an
:: environment variable: inside for /f backticks both quotes and | get mangled.
set "%~2=0"
if not exist "%~1\" exit /b 0
set "DSPATH=%~1"
for /f "usebackq delims=" %%S in (`%PS% "$ErrorActionPreference='SilentlyContinue';$s=[int64]0;foreach($f in (Get-ChildItem -LiteralPath $env:DSPATH -Recurse -Force -File)){$s=$s+$f.Length};[int64]($s/1MB)"`) do set "%~2=%%S"
if not defined %~2 set "%~2=0"
exit /b 0

:BinSize
:: %1 = out var: MB in the Recycle Bin across ALL drives, or "-" if unknown.
set "%~1=-"
set "BTMP="
for /f "usebackq delims=" %%B in (`%PS% "$s=[int64]0;foreach($i in @((New-Object -ComObject Shell.Application).NameSpace(10).Items())){$s=$s+[int64]$i.Size};[int64]($s/1MB)"`) do set "BTMP=%%B"
if not defined BTMP exit /b 0
for /f "delims=0123456789" %%X in ("!BTMP!") do exit /b 0
set "%~1=!BTMP!"
exit /b 0

:GuardPath
:: Refuse wildcards, traversal, shallow paths and a hard list of roots.
set "G=%~1"
if not defined G exit /b 1
echo "%G%"| "%FINDSTR%" /l /c:"*"  >nul && exit /b 1
echo "%G%"| "%FINDSTR%" /l /c:"?"  >nul && exit /b 1
echo "%G%"| "%FINDSTR%" /l /c:".." >nul && exit /b 1
:: Require at least two backslashes, i.e. "C:\Windows\Temp" passes but
:: "C:\Windows" does not. Counting backslashes rather than using a fixed
:: offset keeps this correct on non-C installs and renamed Windows folders.
set "BS=0"
set "REST=%G%"
:countbs
for /f "tokens=1* delims=\" %%A in ("!REST!") do set "REST=%%B"
if defined REST (
    set /a BS+=1
    goto :countbs
)
if %BS% LSS 2 exit /b 1
for %%B in (
    "%SystemDrive%\" "%SystemRoot%" "%SystemRoot%\System32" "%SystemRoot%\SysWOW64"
    "%SystemRoot%\WinSxS" "%SystemRoot%\Installer" "%SystemRoot%\System32\DriverStore"
    "%ProgramFiles%" "%ProgramFiles(x86)%" "%SystemDrive%\Users" "%USERPROFILE%"
    "%LOCALAPPDATA%" "%APPDATA%" "%ProgramData%" "%APPDIR%" "%LOGDIR%"
    "%USERPROFILE%\Downloads" "%USERPROFILE%\Documents" "%USERPROFILE%\Desktop"
    "%USERPROFILE%\Pictures" "%USERPROFILE%\Videos" "%USERPROFILE%\Music"
    "%USERPROFILE%\OneDrive" "%LOCALAPPDATA%\Packages" "%USERPROFILE%\AppData\LocalLow"
) do if /i "%G%"=="%%~B" exit /b 1
exit /b 0

:Purge
:: %1 = label, %2 = folder whose CONTENTS are removed, with no age filter.
:: robocopy /MIR from an empty folder instead of "del /s + rd /s":
::   /XJ  - junction points are skipped, not followed (del /s followed them
::          and could delete files outside the target entirely)
::   long paths over 260 characters are handled, which del and rd are not
::   hidden and system files are removed, which plain del silently skips
:: Locked files are routine - Explorer holds the icon cache, a browser holds
:: its own - so they count as skipped, not as a failure. Otherwise every
:: scheduled run would report a non-zero exit code.
set "PLBL=%~1"
set "PDIR=%~2"
if not exist "%PDIR%\" exit /b 0
call :GuardPath "%PDIR%"
if errorlevel 1 (
    call :Say "  [W] refused unsafe path: %PDIR%"
    call :Csv "%PDIR%" "0" "refused"
    set /a FAILS+=1
    exit /b 1
)
set "PSZ=-"
if "%SIZES%"=="1" call :DirSize "%PDIR%" PSZ
if "%DRYRUN%"=="1" (
    call :Say "  [DRY] %PSZ% MB  %PLBL%"
    call :Csv "%PDIR%" "%PSZ%" "dryrun"
    if not "%PSZ%"=="-" set /a EST+=PSZ
    exit /b 0
)
call :Say "  [*] %PSZ% MB  %PLBL%"
set "PRES=cleaned"
if exist "%ROBO%" (
    "%ROBO%" "%EMPTYDIR%" "%PDIR%" /MIR /XJ /NFL /NDL /NJH /NJS /NP /R:0 /W:0 /MT:8 >nul 2>&1
    if errorlevel 8 set "PRES=partial"
) else (
    del /f /q /s /a "%PDIR%\*" >nul 2>&1
    for /d %%d in ("%PDIR%\*") do rd /s /q "%%d" >nul 2>&1
)
if "!PRES!"=="partial" (
    call :Say "  [~] some items were locked or in use: %PLBL%"
    set /a SKIPPED+=1
)
call :Csv "%PDIR%" "%PSZ%" "!PRES!"
if not "%PSZ%"=="-" set /a EST+=PSZ
exit /b 0

:PurgeAged
:: %1 = label, %2 = folder. Only files last written more than %AGE% days ago
:: are removed, so an installer or an app that is mid-write keeps its working
:: set. The walk skips reparse points explicitly and returns the MB it counted,
:: so temp folders report a real figure even when /nosizes is in effect.
set "PLBL=%~1"
set "PDIR=%~2"
if not exist "%PDIR%\" exit /b 0
call :GuardPath "%PDIR%"
if errorlevel 1 (
    call :Say "  [W] refused unsafe path: %PDIR%"
    call :Csv "%PDIR%" "0" "refused"
    set /a FAILS+=1
    exit /b 1
)
set "CP_PATH=%PDIR%"
set "CP_AGE=%AGE%"
set "CP_DRY=%DRYRUN%"
set "ASZ=0"
for /f "usebackq delims=" %%M in (`%PS% "%WALK%"`) do set "ASZ=%%M"
if not defined ASZ set "ASZ=0"
:: keep only a plain number - pipe-free, see the header
for /f "delims=0123456789" %%X in ("!ASZ!") do set "ASZ=0"
set /a EST+=ASZ
if "%DRYRUN%"=="1" (
    call :Say "  [DRY] !ASZ! MB  %PLBL% [older than %AGE% days]"
    call :Csv "%PDIR%" "!ASZ!" "dryrun"
    exit /b 0
)
call :Say "  [*] !ASZ! MB  %PLBL% [older than %AGE% days]"
call :Csv "%PDIR%" "!ASZ!" "cleaned"
exit /b 0

:PurgeFile
set "FLBL=%~1"
set "FTGT=%~2"
if not exist "%FTGT%" exit /b 0
call :FileMB "%FTGT%" FSZ
set /a EST+=FSZ
if "%DRYRUN%"=="1" (
    call :Say "  [DRY] !FSZ! MB  %FLBL%"
    call :Csv "%FTGT%" "!FSZ!" "dryrun"
    exit /b 0
)
call :Say "  [*] !FSZ! MB  %FLBL%"
del /f /q /a "%FTGT%" >nul 2>&1
if exist "%FTGT%" (
    call :Csv "%FTGT%" "!FSZ!" "locked"
    set /a SKIPPED+=1
) else (
    call :Csv "%FTGT%" "!FSZ!" "cleaned"
)
exit /b 0

:PurgeElectron
:: %1 = label, %2 = data folder of an Electron app. Only cache sub-folders are
:: removed; settings, Local Storage, IndexedDB and logins are left alone.
if not exist "%~2\" exit /b 0
for %%C in (
    "Cache" "Code Cache" "GPUCache" "DawnCache" "DawnGraphiteCache"
    "DawnWebGPUCache" "Service Worker\CacheStorage" "Service Worker\ScriptCache"
    "Application Cache" "Crashpad\reports"
) do call :Purge "%~1 - %%~C" "%~2\%%~C"
exit /b 0

:Report1
:: %1 = folder, %2 = optional note
if not exist "%~1\" exit /b 0
set "R1PATH=%~1"
set "R1NOTE=%~2"
set "RSZ=0"
call :DirSize "%~1" RSZ
%PS% "'  {0,-52}{1,9:N0} MB  {2}' -f $env:R1PATH,[int64]$env:RSZ,$env:R1NOTE"
exit /b 0

:DescribeDeep
echo   This will clean:
echo     - everything from Quick clean
echo     - Windows Update download cache - services stopped and restored
echo     - Delivery Optimization cache
echo     - old Windows logs: CBS, DISM, Panther, LiveKernelReports, USO
echo     - Disk Cleanup with a vetted handler list
echo     - Recycle Bin on every drive
if "%ALLUSERS%"=="1"   echo     - temp folders of ALL user profiles
if "%DOPREFETCH%"=="1" echo     - Prefetch - not recommended, gains under 5 MB
exit /b 0

:QuickTargets
:: One shared list so Quick, Deep and MAXIMUM can never drift apart.
call :PurgeAged "User temp"            "%TEMP%"
call :PurgeAged "Windows temp"         "%SystemRoot%\Temp"
call :PurgeAged "System temp"          "%SystemRoot%\SystemTemp"
call :Purge "Crash dumps"              "%LOCALAPPDATA%\CrashDumps"
call :Purge "WER user"                 "%LOCALAPPDATA%\Microsoft\Windows\WER"
call :Purge "WER system queue"         "%ProgramData%\Microsoft\Windows\WER\ReportQueue"
call :Purge "WER system archive"       "%ProgramData%\Microsoft\Windows\WER\ReportArchive"
call :Purge "WER system temp"          "%ProgramData%\Microsoft\Windows\WER\Temp"
call :Purge "DirectX shader cache"     "%LOCALAPPDATA%\D3DSCache"
call :Purge "NVIDIA DX shader cache"   "%LOCALAPPDATA%\NVIDIA\DXCache"
call :Purge "NVIDIA GL shader cache"   "%LOCALAPPDATA%\NVIDIA\GLCache"
call :Purge "NVIDIA OptiX cache"       "%LOCALAPPDATA%\NVIDIA\OptixCache"
call :Purge "NVIDIA compute cache"     "%ProgramData%\NVIDIA Corporation\NV_Cache"
call :Purge "AMD DX shader cache"      "%LOCALAPPDATA%\AMD\DxCache"
call :Purge "AMD DXC shader cache"     "%LOCALAPPDATA%\AMD\DxcCache"
call :Purge "AMD GL shader cache"      "%LOCALAPPDATA%\AMD\GLCache"
call :Purge "AMD Vulkan shader cache"  "%LOCALAPPDATA%\AMD\VkCache"
call :Purge "Intel shader cache"       "%LOCALAPPDATA%\Intel\ShaderCache"
call :Purge "INetCache"                "%LOCALAPPDATA%\Microsoft\Windows\INetCache\IE"
:: thumbnail and icon DBs are locked while Explorer runs - locked files are
:: skipped, and the Disk Cleanup "Thumbnail Cache" handler in Deep finishes it
call :Purge "Thumbnail and icon cache" "%LOCALAPPDATA%\Microsoft\Windows\Explorer"
call :Purge "Windows minidumps"        "%SystemRoot%\Minidump"
exit /b 0

:DeepTargets
call :QuickTargets
if "%ALLUSERS%"=="1" call :CleanTempAllUsers
call :Purge "CBS logs"                     "%SystemRoot%\Logs\CBS"
call :Purge "DISM logs"                    "%SystemRoot%\Logs\DISM"
call :Purge "LiveKernelReports"            "%SystemRoot%\LiveKernelReports"
call :Purge "Setup logs - Panther"         "%SystemRoot%\Panther"
call :PurgeAged "Update orchestrator logs" "%ProgramData%\USOShared\Logs"
call :PurgeFile "Kernel memory dump"       "%SystemRoot%\MEMORY.DMP"
if "%DOPREFETCH%"=="1" (
    call :Purge "Prefetch" "%SystemRoot%\Prefetch"
) else (
    call :Say "  [~] Prefetch skipped on purpose - it rebuilds itself and clearing it slows app launches. Use /prefetch to force."
)
call :UpdateCache
call :DOCache
call :EmptyBin
call :CleanMgrDeep
exit /b 0

:CleanTempAllUsers
for /d %%U in ("%SystemDrive%\Users\*") do (
    if /i not "%%~nxU"=="Public" if /i not "%%~nxU"=="Default" if /i not "%%~nxU"=="All Users" (
        call :PurgeAged "Temp [%%~nxU]" "%%~U\AppData\Local\Temp"
    )
)
exit /b 0

:BrowserTargets
for %%R in (
    "%LOCALAPPDATA%\Google\Chrome\User Data"
    "%LOCALAPPDATA%\Google\Chrome Beta\User Data"
    "%LOCALAPPDATA%\Google\Chrome Dev\User Data"
    "%LOCALAPPDATA%\Google\Chrome SxS\User Data"
    "%LOCALAPPDATA%\Microsoft\Edge\User Data"
    "%LOCALAPPDATA%\Microsoft\Edge Beta\User Data"
    "%LOCALAPPDATA%\Microsoft\Edge Dev\User Data"
    "%LOCALAPPDATA%\Microsoft\Edge SxS\User Data"
    "%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data"
    "%LOCALAPPDATA%\Vivaldi\User Data"
    "%LOCALAPPDATA%\Chromium\User Data"
    "%LOCALAPPDATA%\Yandex\YandexBrowser\User Data"
) do call :ChromiumRoot %%R

:: Opera keeps its profile in the profile folder itself (older builds) or in
:: a Default sub-folder (newer builds), split across Roaming and Local.
call :OperaRoot "Opera"    "%APPDATA%\Opera Software\Opera Stable"
call :OperaRoot "Opera"    "%LOCALAPPDATA%\Opera Software\Opera Stable"
call :OperaRoot "Opera GX" "%APPDATA%\Opera Software\Opera GX Stable"
call :OperaRoot "Opera GX" "%LOCALAPPDATA%\Opera Software\Opera GX Stable"

:: Firefox cache2 lives under LOCALAPPDATA, not APPDATA
for %%B in ("%LOCALAPPDATA%\Mozilla\Firefox\Profiles" "%APPDATA%\Mozilla\Firefox\Profiles") do (
    if exist "%%~B\" for /d %%P in ("%%~B\*") do (
        call :Purge "Firefox cache2 [%%~nxP]"       "%%~P\cache2"
        call :Purge "Firefox startupCache [%%~nxP]" "%%~P\startupCache"
    )
)
exit /b 0

:ChromiumRoot
set "ROOT=%~1"
if not exist "%ROOT%\" exit /b 0
:: brand name = the folder above "User Data" (Chrome / Edge / Brave-Browser)
for %%X in ("%ROOT%") do set "PP=%%~dpX"
set "PP=%PP:~0,-1%"
for %%X in ("%PP%") do set "BRAND=%%~nxX"
if not defined BRAND set "BRAND=browser"
:: profile folders are Default, Guest Profile, System Profile and "Profile N";
:: the name test uses a substring instead of a findstr pipe
for /d %%P in ("%ROOT%\*") do (
    set "PN=%%~nxP"
    if /i "!PN!"=="Default"        call :ChromiumProfile "%%~P"
    if /i "!PN!"=="Guest Profile"  call :ChromiumProfile "%%~P"
    if /i "!PN!"=="System Profile" call :ChromiumProfile "%%~P"
    if /i "!PN:~0,8!"=="Profile "  call :ChromiumProfile "%%~P"
)
call :Purge "%BRAND% ShaderCache"   "%ROOT%\ShaderCache\GPUCache"
call :Purge "%BRAND% GrShaderCache" "%ROOT%\GrShaderCache\GPUCache"
exit /b 0

:ChromiumProfile
:: cache-only subfolders. Cookies, Login Data, Local Storage, IndexedDB,
:: history and the password store are NOT touched.
set "PR=%~1"
for %%C in (
    "Cache\Cache_Data" "Code Cache\js" "Code Cache\wasm" "GPUCache"
    "DawnCache" "DawnGraphiteCache" "DawnWebGPUCache" "GrShaderCache" "ShaderCache"
    "Service Worker\CacheStorage" "Service Worker\ScriptCache" "Media Cache"
) do call :Purge "%BRAND%/%~nx1 - %%~C" "%PR%\%%~C"
exit /b 0

:OperaRoot
:: %1 = brand label, %2 = Opera profile folder
set "BRAND=%~1"
if exist "%~2\" call :ChromiumProfile "%~2"
if exist "%~2\Default\" call :ChromiumProfile "%~2\Default"
if exist "%~2\Cache\" call :Purge "%~1 cache" "%~2\Cache"
exit /b 0

:AppTargets
call :PurgeElectron "Discord"            "%APPDATA%\discord"
call :PurgeElectron "Slack"              "%APPDATA%\Slack"
call :PurgeElectron "Teams classic"      "%APPDATA%\Microsoft\Teams"
:: the new Teams is a WebView2 app - same layout as a Chromium "User Data"
call :ChromiumRoot "%LOCALAPPDATA%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView"
call :Purge "Steam web cache"            "%LOCALAPPDATA%\Steam\htmlcache"
for /d %%W in ("%LOCALAPPDATA%\EpicGamesLauncher\Saved\webcache*") do call :Purge "Epic launcher %%~nxW" "%%~W"
call :Purge "Adobe media cache files"    "%APPDATA%\Adobe\Common\Media Cache Files"
call :Purge "Adobe media cache database" "%APPDATA%\Adobe\Common\Media Cache"
call :Purge "Adobe audio peak files"     "%APPDATA%\Adobe\Common\Peak Files"
call :Purge "Java applet cache"          "%USERPROFILE%\AppData\LocalLow\Sun\Java\Deployment\cache"
call :PurgeAged "OneDrive logs"          "%LOCALAPPDATA%\Microsoft\OneDrive\logs"
call :Purge "Office add-in cache"        "%LOCALAPPDATA%\Microsoft\Office\16.0\Wef"
exit /b 0

:DevTargets
call :Purge "pip cache"                "%LOCALAPPDATA%\pip\cache"
call :Purge "uv cache"                 "%LOCALAPPDATA%\uv\cache"
call :Purge "Poetry cache"             "%LOCALAPPDATA%\pypoetry\Cache"
call :Purge "npm cache"                "%LOCALAPPDATA%\npm-cache\_cacache"
call :Purge "npm cache roaming"        "%APPDATA%\npm-cache\_cacache"
call :Purge "Yarn cache"               "%LOCALAPPDATA%\Yarn\Cache"
call :Purge "Yarn Berry cache"         "%LOCALAPPDATA%\Yarn\Berry\cache"
call :Purge "pnpm store"               "%LOCALAPPDATA%\pnpm\store"
call :Purge "pnpm store - old path"    "%LOCALAPPDATA%\pnpm-store"
call :Purge "Bun cache"                "%USERPROFILE%\.bun\install\cache"
call :Purge "Deno cache"               "%LOCALAPPDATA%\deno"
call :Purge "node-gyp headers"         "%LOCALAPPDATA%\node-gyp\Cache"
call :Purge "Electron downloads"       "%LOCALAPPDATA%\electron\Cache"
call :Purge "electron-builder cache"   "%LOCALAPPDATA%\electron-builder\Cache"
call :Purge "NuGet http cache"         "%LOCALAPPDATA%\NuGet\v3-cache"
call :Purge "NuGet plugins cache"      "%LOCALAPPDATA%\NuGet\plugins-cache"
call :Purge "NuGet packages"           "%USERPROFILE%\.nuget\packages"
call :Purge "Gradle caches"            "%USERPROFILE%\.gradle\caches"
call :Purge "Gradle wrapper downloads" "%USERPROFILE%\.gradle\wrapper\dists"
call :Purge "Cargo registry cache"     "%USERPROFILE%\.cargo\registry\cache"
call :Purge "Cargo registry sources"   "%USERPROFILE%\.cargo\registry\src"
call :Purge "Go build cache"           "%LOCALAPPDATA%\go-build"
call :Purge "C++ IntelliSense ipch"    "%LOCALAPPDATA%\Microsoft\vscode-cpptools\ipch"
for %%E in ("Code" "Code - Insiders" "Cursor") do (
    call :PurgeElectron "%%~E" "%APPDATA%\%%~E"
    call :Purge "%%~E CachedData"          "%APPDATA%\%%~E\CachedData"
    call :Purge "%%~E extension downloads" "%APPDATA%\%%~E\CachedExtensionVSIXs"
)
for /d %%J in ("%LOCALAPPDATA%\JetBrains\*") do call :Purge "JetBrains %%~nxJ caches" "%%~J\caches"
call :CondaClean
call :DockerPrune
exit /b 0

:CondaClean
where conda >nul 2>&1 || exit /b 0
if "%DRYRUN%"=="1" (
    call :Say "  [DRY] would run: conda clean --all --yes"
    exit /b 0
)
call :ConfirmYN "conda found - remove its package and index caches as well?" || exit /b 0
call :Say "  [*] conda clean --all --yes"
:: conda is a .bat - without CALL it would end this script
call conda clean --all --yes
call :Log "conda clean exit=!errorlevel!"
exit /b 0

:DockerPrune
where docker >nul 2>&1 || exit /b 0
docker info >nul 2>&1
if errorlevel 1 (
    call :Say "  [~] Docker is installed but not running - its caches were skipped"
    exit /b 0
)
if "%DRYRUN%"=="1" (
    call :Say "  [DRY] would run: docker builder prune -f, then docker image prune -f"
    docker system df
    exit /b 0
)
call :ConfirmYN "Docker found - prune its build cache and dangling images?" || exit /b 0
call :Say "  [*] docker builder prune -f"
docker builder prune -f
call :Log "docker builder prune exit=!errorlevel!"
call :Say "  [*] docker image prune -f - untagged, unused images only"
docker image prune -f
call :Log "docker image prune exit=!errorlevel!"
call :Say "  [i] Docker frees space inside its virtual disk - see the disk report to shrink that file."
exit /b 0

:EmptyBin
set "BSZ=-"
if "%SIZES%"=="1" call :BinSize BSZ
if "%DRYRUN%"=="1" (
    call :Say "  [DRY] !BSZ! MB  Recycle Bin, all drives"
    call :Csv "Recycle Bin" "!BSZ!" "dryrun"
    if not "!BSZ!"=="-" set /a EST+=BSZ
    exit /b 0
)
call :Say "  [*] !BSZ! MB  Recycle Bin, all drives"
%PS% "Clear-RecycleBin -Force -ErrorAction SilentlyContinue" >nul 2>&1
call :Csv "Recycle Bin" "!BSZ!" "cleaned"
if not "!BSZ!"=="-" set /a EST+=BSZ
exit /b 0

:UpdateCache
set "UD=%SystemRoot%\SoftwareDistribution\Download"
if not exist "%UD%\" (
    call :Say "  [~] Update cache folder not present"
    exit /b 0
)
if "%DRYRUN%"=="1" (
    set "USZ=-"
    if "%SIZES%"=="1" call :DirSize "%UD%" USZ
    call :Say "  [DRY] !USZ! MB  Windows Update download cache"
    call :Csv "%UD%" "!USZ!" "dryrun"
    if not "!USZ!"=="-" set /a EST+=USZ
    exit /b 0
)

:: Only touch services that actually exist on this machine, and read their
:: state through Get-Service - "sc query" prints localised state names.
set "WASRUN="
for /f "usebackq delims=" %%R in (`%PS% "$n=@();foreach($s in @(%SVCPS%)){$o=Get-Service $s -ErrorAction SilentlyContinue;if($o -and $o.Status -eq 'Running'){$n=$n+$s}};$n -join ' '"`) do set "WASRUN=%%R"

call :Say "  [*] Stopping update services: %SVCLIST%"
for %%S in (%SVCLIST%) do net stop %%S /y >nul 2>&1

:: Wait for a real STOPPED, not merely "no longer STOP_PENDING".
set "W=0"
:waitstop
%PS% "$r=0;foreach($s in @(%SVCPS%)){$o=Get-Service $s -ErrorAction SilentlyContinue;if($o -and $o.Status -ne 'Stopped'){$r=1}};exit $r"
if errorlevel 1 if !W! LSS 20 (
    set /a W+=1
    call :Sleep 1
    goto :waitstop
)
if errorlevel 1 (
    call :Say "  [W] Some update services would not stop - locked files will be skipped."
    set /a FAILS+=1
)

call :Purge "Windows Update download cache" "%UD%"

if defined WASRUN (
    call :Say "  [*] Restarting the services that were running: !WASRUN!"
    for %%S in (!WASRUN!) do net start %%S >nul 2>&1
)
exit /b 0

:DOCache
:: The cache folder moved between Windows builds - measure whichever exists.
set "DOD=%SystemRoot%\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
if not exist "%DOD%\" set "DOD=%SystemRoot%\SoftwareDistribution\DeliveryOptimization"
set "DOSZ=-"
if "%SIZES%"=="1" call :DirSize "%DOD%" DOSZ
if "%DRYRUN%"=="1" (
    call :Say "  [DRY] !DOSZ! MB  Delivery Optimization cache"
    call :Csv "Delivery Optimization" "!DOSZ!" "dryrun"
    if not "!DOSZ!"=="-" set /a EST+=DOSZ
    exit /b 0
)
call :Say "  [*] !DOSZ! MB  Delivery Optimization cache"
%PS% "try{ Delete-DeliveryOptimizationCache -Force -ErrorAction Stop }catch{ '  DO cache: '+$_.Exception.Message }" 2>&1
call :Csv "Delivery Optimization" "!DOSZ!" "cleaned"
if not "!DOSZ!"=="-" set /a EST+=DOSZ
exit /b 0

:CleanMgrDeep
:: A vetted whitelist under one private sageset id. /verylowdisk would run
:: every handler unattended, including the one that empties Downloads.
if "%DRYRUN%"=="1" (
    call :Say "  [DRY] would run Disk Cleanup with the safe handler list"
    exit /b 0
)
call :Say "  [*] Configuring the Disk Cleanup handler list"
call :SageReset %SAGEDEEP%
for %%H in (
    "Active Setup Temp Folders" "BranchCache" "D3D Shader Cache"
    "Delivery Optimization Files" "Diagnostic Data Viewer database files"
    "Downloaded Program Files" "Feedback Hub Archive log files"
    "Internet Cache Files" "Offline Pages Files" "Old ChkDsk Files"
    "RetailDemo Offline Content" "Setup Log Files"
    "System error memory dump files" "System error minidump files"
    "Temporary Files" "Temporary Setup Files" "Thumbnail Cache"
    "Update Cleanup" "Upgrade Discarded Files" "Windows Defender"
    "Windows Error Reporting Files" "Windows Reset Log Files"
    "Windows Upgrade Log Files"
) do call :SageEnable %SAGEDEEP% "%%~H"
call :Say "  [i] Excluded on purpose: DownloadsFolder, Previous Installations, Windows ESD installation files, Device Driver Packages, User file versions, Language Pack"
call :RunSage %SAGEDEEP%
exit /b 0

:SageReset
:: %1 = zero-padded sageset id. Clears that id on every handler.
for /f "tokens=*" %%K in ('reg query "%VCK%" 2^>nul') do (
    if /i not "%%K"=="%VCKFULL%" reg add "%%K" /v StateFlags%~1 /t REG_DWORD /d 0 /f >nul 2>&1
)
exit /b 0

:SageEnable
:: %1 = sageset id, %2 = handler name. Handlers missing on this PC are
:: skipped instead of being created as empty registry keys.
reg query "%VCK%\%~2" >nul 2>&1 || exit /b 0
reg add "%VCK%\%~2" /v StateFlags%~1 /t REG_DWORD /d 2 /f >nul 2>&1
exit /b 0

:RunSage
:: %1 = zero-padded sageset id. cleanmgr's registry values are zero-padded
:: (StateFlags0099) but /sagerun wants the number WITHOUT leading zeros.
:: cleanmgr also relaunches itself, so "start /wait" returns long before the
:: work is done. Poll the process instead, with a 60 minute ceiling.
set "SN=%~1"
call :StripZeros SN
call :Say "  [*] Running Disk Cleanup /sagerun:!SN! - this can take a while, do not close its window"
start "" cleanmgr /sagerun:!SN!
set "CMW=0"
:cmwait
call :Sleep 3
"%TASKLIST%" /fi "imagename eq cleanmgr.exe" 2>nul | "%FINDSTR%" /i /c:"cleanmgr.exe" >nul
if not errorlevel 1 (
    set /a CMW+=1
    if !CMW! LSS 1200 goto :cmwait
    call :Say "  [W] Disk Cleanup is still running after 60 minutes - leaving it to finish."
)
call :Log "cleanmgr /sagerun:!SN! finished - polled"
call :Csv "cleanmgr sagerun:!SN!" "-" "cleaned"
exit /b 0

:StripZeros
:: %1 = NAME of a variable holding a zero-padded number; strips only the
:: leading zeros ("%%X:0=%%" would strip every zero in the string).
:stripz
if "!%~1:~0,1!"=="0" if not "!%~1!"=="0" (
    set "%~1=!%~1:~1!"
    goto :stripz
)
exit /b 0

:CheckRunning
:: PROCS = list of image names, quoted when they contain spaces
set "RUNNING="
for %%P in (%PROCS%) do (
    "%TASKLIST%" /fi "imagename eq %%~P" /nh 2>nul | "%FINDSTR%" /i /c:"%%~P" >nul && set "RUNNING=!RUNNING! %%~P"
)
exit /b 0

:RestorePoint
if "%DRYRUN%"=="1" exit /b 0
:: v3 auto-answered YES here, so every unattended run created a restore
:: point and filled shadow storage. In quiet mode it needs /restorepoint.
if "%QUIET%"=="1" (
    if not "%MKRESTORE%"=="1" (
        call :Log "restore point skipped - quiet mode, /restorepoint not given"
        exit /b 0
    )
) else (
    call :ConfirmYN "Create a System Restore point first?" || exit /b 0
)
call :Say "  [*] Creating restore point"
%PS% "try{ Checkpoint-Computer -Description 'CleanPC v5' -RestorePointCreationFrequency 0 -ErrorAction Stop; '  restore point created' }catch{ '  restore point NOT created: '+$_.Exception.Message }" 2>&1
exit /b 0

:Finish
call :GetFree AFTER
%PS% "$b=[double]'%BEFORE%'; $a=[double]'%AFTER%'; $g=[math]::Round(($a-$b)/1GB,3); Write-Host ''; Write-Host ('   Measured free-space change: {0} GB' -f $g) -ForegroundColor $(if($g -gt 0){'Green'}else{'Yellow'}); Write-Host ('   Sum of cleaned targets    : {0} MB' -f %EST%) -ForegroundColor Cyan"
set /a DS=SKIPPED-SKIPPED0
set /a DF=FAILS-FAILS0
if not "%DS%"=="0" echo    Targets with locked items : %DS%
if not "%DF%"=="0" echo    Failures                  : %DF% - see the log
:: the five biggest targets of THIS run, read back from the CSV log
%PS% "$rows=@(Import-Csv -LiteralPath $env:CSV -ErrorAction SilentlyContinue | Where-Object { $_.action -eq $env:CURACT -and $_.session -eq $env:SESSION -and ($_.megabytes -as [int]) -gt 0 } | Sort-Object { [int]$_.megabytes } -Descending | Select-Object -First 5); if($rows.Count -gt 0){ Write-Host ''; Write-Host '   Biggest items:' -ForegroundColor Cyan; foreach($r in $rows){ Write-Host ('   {0,8:N0} MB  {1}' -f [int]$r.megabytes,$r.target) } }"
call :Log "%CURACT% done. before=%BEFORE% after=%AFTER% est_targets_MB=%EST% skipped=%DS% fails=%DF% dryrun=%DRYRUN%"
echo.
call :ShowSpace
set "EST=0"
exit /b 0

:: ============================== HELP ========================================
:help
echo.
echo  Windows 11 Safe Cleanup Tool v5
echo.
echo  Usage: CleanPC_v5.bat [action] [options]
echo.
echo  Cleaning actions - omit them for the interactive menu:
echo    /quick        temp, crash dumps, error reports, GPU shader caches
echo    /deep         quick + update cache + Windows logs + Disk Cleanup + bin
echo    /browser      cache folders of every browser profile
echo    /apps         Teams, Discord, Slack, Steam, Epic, Adobe, Java, OneDrive
echo    /devcaches    pip, uv, npm, yarn, pnpm, NuGet, Gradle, Cargo, Go,
echo                  VS Code, JetBrains, conda, Docker - rebuildable, opt-in
echo    /max          deep + browser + apps in one run
echo    /recycle      empty the Recycle Bin on every drive
echo    /repair       DISM ScanHealth, RestoreHealth, SFC, component cleanup
echo    /report       where the space went and what else could be freed
echo.
echo  Advanced space actions - each one changes a Windows setting:
echo    /hibernate:reduced^|off^|full    shrink or remove hiberfil.sys
echo    /shadowcap:N                  cap System Restore at N percent, 2-50
echo    /windowsold                   remove the previous Windows installation
echo    /compactos:on^|off             compress the Windows system files
echo    /reservedstorage:off^|on       release or restore the update reservation
echo.
echo  Options:
echo    /dryrun         report only, delete nothing - works without admin
echo    /quiet          no prompts, no pause - for Task Scheduler
echo    /ifbelow:GB     do nothing unless free space is below GB
echo    /olderthan:N    keep temp files newer than N days, default 1
echo    /nosizes        skip per-item size measurement - much faster
echo    /allusers       also clean temp of every user profile - deep
echo    /prefetch       also clear Prefetch - not recommended
echo    /resetbase      with /repair: StartComponentCleanup /ResetBase
echo    /restorepoint   create a restore point even in /quiet mode
echo    /desktoplog     write the log to the Desktop instead of AppData
echo    /help           this text - /^? works too
echo.
echo  Logs: %%LOCALAPPDATA%%\CleanPC\Cleanup_Log.txt  - appended, rotated at 1 MB
echo        %%LOCALAPPDATA%%\CleanPC\Cleanup_Log.csv  - one row per target
echo.
echo  Exit codes: 0 ok, 1 elevation failed, 2 a step failed, 3 bad usage.
echo.
if "%QUIET%"=="0" if "%CLI%"=="0" pause
endlocal & exit /b %RC%

:usageerror
echo.
echo  [ERROR] !UERR!
echo  Run CleanPC_v5.bat /help for the list of options.
echo.
endlocal & exit /b 3

:: ============================== EXIT ========================================
:end
echo.
echo   Log: %LOG%
call :Log "Session end. skipped=%SKIPPED% fails=%FAILS%"
if not "%FAILS%"=="0" set "RC=2"
echo.
if "%QUIET%"=="0" if "%CLI%"=="0" pause
endlocal & exit /b %RC%
