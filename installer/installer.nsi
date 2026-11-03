; 文析助手 (AsterLink) Windows 安装器
; 生成单文件 exe：运行时自动解压全部文件、创建桌面与开始菜单快捷方式
Unicode true
SetCompressor /SOLID lzma
SetCompressorDictSize 64

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "WordFunc.nsh"

!define APP_NAME "文析助手"
!define APP_NAME_EN "AsterLink"
!define APP_EXE "asterlink.exe"
!define APP_PUBLISHER "AsterLink"
!define APP_VERSION "2.1.0"
!define APP_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\AsterLink"

Name "${APP_NAME} ${APP_VERSION}"
OutFile "asterlink-windows-x64-setup.exe"
InstallDir "$LOCALAPPDATA\Programs\AsterLink"
InstallDirRegKey HKCU "Software\AsterLink" "InstallDir"
RequestExecutionLevel user
BrandingText "${APP_NAME} ${APP_VERSION}"

VIProductVersion "2.1.0.0"
VIAddVersionKey /LANG=2052 "ProductName" "${APP_NAME}"
VIAddVersionKey /LANG=2052 "CompanyName" "${APP_PUBLISHER}"
VIAddVersionKey /LANG=2052 "FileDescription" "${APP_NAME} 安装程序"
VIAddVersionKey /LANG=2052 "FileVersion" "${APP_VERSION}.0"
VIAddVersionKey /LANG=2052 "ProductVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=2052 "LegalCopyright" "Copyright (C) 2026 AsterLink"

!define MUI_ICON "app.ico"
!define MUI_UNICON "app.ico"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "立即运行 ${APP_NAME}"
!define MUI_FINISHPAGE_NOREBOOTSUPPORT

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "English"

; ---------- 检查是否正在运行 ----------
!macro CheckRunning UN
Function ${UN}CheckRunning
  nsExec::ExecToStack 'cmd /c tasklist /FI "IMAGENAME eq ${APP_EXE}" /NH'
  Pop $0
  Pop $1
  ${If} $1 != ""
    StrCpy $2 $1 20
    ${If} $2 == "${APP_EXE}"
      MessageBox MB_ICONEXCLAMATION|MB_YESNO "${APP_NAME} 正在运行，需要先关闭才能继续。$\r$\n是否自动关闭？" IDYES closeapp IDNO abort
      closeapp:
        nsExec::Exec 'cmd /c taskkill /F /IM ${APP_EXE}'
        Sleep 1200
        Goto done
      abort:
        Quit
    ${EndIf}
  ${EndIf}
  done:
FunctionEnd
!macroend

!insertmacro CheckRunning ""
!insertmacro CheckRunning "un."

; ---------- 安装 ----------
Section "Install"
  SetShellVarContext current
  SetOutPath "$INSTDIR"

  ; 关闭旧版本进程，避免文件占用
  Call CheckRunning

  ; 清理旧文件（保留用户数据，数据在 AppData 其他目录）
  RMDir /r "$INSTDIR\data"
  Delete "$INSTDIR\*.dll"
  Delete "$INSTDIR\*.exe"
  Delete "$INSTDIR\*.exp"
  Delete "$INSTDIR\*.lib"

  SetOutPath "$INSTDIR"
  File /r "pkg\*.*"

  ; 开始菜单
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\卸载 ${APP_NAME}.lnk" "$INSTDIR\uninstall.exe"

  ; 桌面快捷方式
  CreateShortCut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0

  ; 卸载程序
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; 注册表
  WriteRegStr HKCU "Software\AsterLink" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "${APP_UNINST_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKCU "${APP_UNINST_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKCU "${APP_UNINST_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "${APP_UNINST_KEY}" "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKCU "${APP_UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${APP_UNINST_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegDWORD HKCU "${APP_UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${APP_UNINST_KEY}" "NoRepair" 1

  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKCU "${APP_UNINST_KEY}" "EstimatedSize" "$0"
SectionEnd

; ---------- 卸载 ----------
Section "Uninstall"
  SetShellVarContext current
  Call un.CheckRunning

  Delete "$DESKTOP\${APP_NAME}.lnk"
  RMDir /r "$SMPROGRAMS\${APP_NAME}"

  RMDir /r "$INSTDIR\data"
  Delete "$INSTDIR\*.dll"
  Delete "$INSTDIR\*.exe"
  Delete "$INSTDIR\*.exp"
  Delete "$INSTDIR\*.lib"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"

  DeleteRegKey HKCU "${APP_UNINST_KEY}"
  DeleteRegKey HKCU "Software\AsterLink"
SectionEnd
