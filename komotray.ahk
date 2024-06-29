#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

#Include <JSON>

#Include "./config/komorebi.ahk"

; Set common config options
AutoStartKomorebi := true
Global IconDir := A_ScriptDir . "/assets/icons"
Global ConfigPath := A_ScriptDir . "/config/komorebi.json"

; ======================================================================
; Initialization
; ======================================================================

; Set up tray menu
A_TrayMenu.Delete()
A_TrayMenu.Add("Pause Komorebi", PauseKomorebi)
A_TrayMenu.Add("Restart Komorebi", RestartKomorebi)
A_TrayMenu.Add()
A_TrayMenu.Add("Reload Tray", ReloadTray)
A_TrayMenu.Add("Exit Tray", ExitTray)
; Define default action and activate it with single click
A_TrayMenu.Default := "Pause Komorebi"
A_TrayMenu.ClickCount := 1

; Initialize internal states
IconState := -1
Global ScreenIndex := 0

; Start the komorebi server
if (ProcessExist("komorebi.exe") == 0 && AutoStartKomorebi) {
    StartKomorebi()
}

; ======================================================================
; Event Handler
; ======================================================================

; Set up pipe
PipeName := "komotray"
PipePath := "\\.\pipe\" . PipeName
OpenMode := 0x01  ; access_inbound
PipeMode := 0x04 | 0x02 | 0x01  ; type_message | readmode_message | nowait
BufferSize := 64 * 1024

; Create named pipe instance
Pipe := DllCall(
    "CreateNamedPipe",
    "Str", PipePath,
    "UInt", OpenMode,
    "UInt", PipeMode,
    "UInt", 1,
    "UInt", BufferSize,
    "UInt", BufferSize,
    "UInt", 0,
    "Ptr", 0,
    "Ptr",
)
If (Pipe = -1) {
    MsgBox("CreateNamedPipe: " . A_LastError)
    ExitTray()
}

; Wait for Komorebi to connect
Komorebic("subscribe " . PipeName)
; set PipeMode = nowait to avoid getting stuck when paused
DllCall("ConnectNamedPipe", "Ptr", Pipe, "Ptr", 0)

; Subscribe to Komorebi events
BytesToRead := 0
Bytes := 0
Loop {
    ; Continue if buffer is empty
    ExitCode := DllCall(
        "PeekNamedPipe",
        "Ptr", Pipe,
        "Ptr", 0,
        "UInt", 1,
        "Ptr", 0,
        "UintP", &BytesToRead,
        "Ptr", 0,
    )
    If (!ExitCode || !BytesToRead) {
        Sleep 50
        Continue
    }

    ; Read the buffer
    Data := Buffer(BufferSize, 0)
    DllCall(
        "ReadFile",
        "Ptr", Pipe,
        "Ptr", Data.Ptr,
        "UInt", BufferSize,
        "UintP", &Bytes,
        "Ptr", 0,
    )

    ; Strip new lines
    If (Bytes <= 1) {
        Continue
    }

    State := JSON.Load(StrGet(Data, Bytes, "UTF-8"))["state"]
    IsPaused := State["is_paused"]
    ScreenIndex := State["monitors"]["focused"]
    ScreenQ := State["monitors"]["elements"][ScreenIndex + 1]
    WorkspaceIndex := ScreenQ["workspaces"]["focused"]
    WorkspaceQ := ScreenQ["workspaces"]["elements"][WorkspaceIndex + 1]

    ; Update tray icon
    If (IsPaused | ScreenIndex << 1 | WorkspaceIndex << 4 != IconState) {
        UpdateIcon(
            IsPaused,
            ScreenIndex,
            WorkspaceIndex,
            ScreenQ["name"],
            WorkspaceQ["name"],
        )
        ; use 3 bits for monitor (i.e. up to 8 monitors)
        IconState := IsPaused | ScreenIndex << 1 | WorkspaceIndex << 4
    }
}
Return

; ======================================================================
; Functions
; ======================================================================

StartKomorebi() {
    Global
    Komorebic("stop")
    Komorebic("start -c " . ConfigPath)
}

RestartKomorebi(*) {
    StartKomorebi()
    ReloadTray()
}

PauseKomorebi(*) {
    Komorebic("toggle-pause")
}

UpdateIcon(IsPaused, ScreenIndex, WorkspaceIndex, ScreenName, WorkspaceName) {
    A_IconTip := Format("{} on {}", WorkspaceName, ScreenName)
    IconPath := Format(
        "{}\{}-{}.ico", IconDir, WorkspaceIndex + 1, ScreenIndex + 1
    )
    If (!IsPaused && FileExist(IconPath)) {
        TraySetIcon IconPath
    } else {
        TraySetIcon Format("{}\pause.ico", IconDir)  ; also used as fallback
    }
}

ReloadTray(*) {
    DllCall("CloseHandle", "Ptr", Pipe)
    Reload
}

ExitTray(*) {
    DllCall("CloseHandle", "Ptr", Pipe)
    Komorebic("stop")
    ExitApp
}
