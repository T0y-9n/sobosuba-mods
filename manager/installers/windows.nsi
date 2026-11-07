Unicode true
!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!define APP "Sobosuba Mod Manager"
!define KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\SobosubaModManager"
Name "${APP}"
OutFile "${OUTPUT}"
InstallDir "$PROGRAMFILES32\${APP}"
RequestExecutionLevel admin
SetCompressor /SOLID lzma
SetCompressorDictSize 32
!define MUI_ICON "${ICON}"
!define MUI_UNICON "${ICON}"
!define MUI_ABORTWARNING
!define MUI_LANGDLL_ALLLANGUAGES
!define MUI_LANGDLL_WINDOWTITLE "Sobosuba Mod Manager"
!insertmacro MUI_PAGE_WELCOME
!define MUI_PAGE_CUSTOMFUNCTION_LEAVE CheckInstallDirectory
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!include "${LANGUAGES}"
Var NoShortcuts
Var ExpectedVersion
Function .onInit
  ${GetParameters} $0
  ClearErrors
  ${GetOptions} $0 "/ExpectedVersion=" $ExpectedVersion
  ${IfNot} ${Errors}
  ${AndIf} $ExpectedVersion != "${VERSION}"
    SetErrorLevel 1
    Abort
  ${EndIf}
  ReadRegDWORD $1 HKLM "${KEY}" "InstallerLanguage"
  ${If} ${Errors}
    ReadRegDWORD $1 HKCU "${KEY}" "InstallerLanguage"
  ${EndIf}
  ${IfNot} ${Errors}
    StrCpy $LANGUAGE $1
  ${EndIf}
  !insertmacro MUI_LANGDLL_DISPLAY
  ReadRegStr $0 HKLM "${KEY}" "InstallLocation"
  ${If} $0 != ""
    StrCpy $INSTDIR $0
  ${EndIf}
  ${GetParameters} $0
  ClearErrors
  ${GetOptions} $0 "/NoShortcuts" $1
  StrCpy $NoShortcuts 0
  ${IfNot} ${Errors}
    StrCpy $NoShortcuts 1
  ${EndIf}
FunctionEnd
Function CheckInstallDirectory
  ${GetParent} "$INSTDIR" $0
  ${If} $0 != $PROGRAMFILES32
  ${AndIf} $0 != $PROGRAMFILES64
    MessageBox MB_OK|MB_ICONSTOP "$PROGRAMFILES32\${APP}"
    Abort
  ${EndIf}
FunctionEnd
Section "$(SetupRequired)" Core
  SectionIn RO
  InitPluginsDir
  SetOutPath "$PLUGINSDIR"
  File /oname=SobosubaModManager.exe "${PAYLOAD}"
  File /oname=windows.ps1 "${BACKEND}"
  WriteUninstaller "$PLUGINSDIR\Uninstall.exe"
  nsExec::ExecToStack '$\"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe$\" -NoLogo -NoProfile -NonInteractive -File $\"$PLUGINSDIR\windows.ps1$\" -Prefix $\"$INSTDIR$\" -Source $\"$PLUGINSDIR$\" -Version $\"${VERSION}$\" -Language $LANGUAGE -NoShortcuts $NoShortcuts'
  Pop $0
  Pop $1
  DetailPrint "$1"
  ${If} $0 != 0
    MessageBox MB_OK|MB_ICONSTOP "$(SetupFailed)$\r$\n$\r$\n$1" /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
SectionEnd
Section /o "$(SetupDesktop)" Desktop
  ${If} $NoShortcuts = 0
    nsExec::ExecToStack '$\"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe$\" -NoLogo -NoProfile -NonInteractive -File $\"$PLUGINSDIR\windows.ps1$\" -Prefix $\"$INSTDIR$\" -DesktopOnly'
    Pop $0
    Pop $1
    DetailPrint "$1"
  ${EndIf}
SectionEnd
Function un.onInit
  ReadRegDWORD $LANGUAGE HKLM "${KEY}" "InstallerLanguage"
FunctionEnd
Section "Uninstall"
  InitPluginsDir
  SetOutPath "$PLUGINSDIR"
  File /oname=windows.ps1 "${BACKEND}"
  nsExec::ExecToStack '$\"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe$\" -NoLogo -NoProfile -NonInteractive -File $\"$PLUGINSDIR\windows.ps1$\" -Prefix $\"$INSTDIR$\" -Uninstall'
  Pop $0
  Pop $1
  DetailPrint "$1"
  ${If} $0 != 0
    MessageBox MB_OK|MB_ICONSTOP "$(SetupFailed)$\r$\n$\r$\n$1" /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
SectionEnd
