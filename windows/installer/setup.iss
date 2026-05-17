; Utility Bills Manager - InnoSetup installer script
;
; CI build:
;   ISCC.exe /DMyAppVersion=x.y.z /DMyAppSourceDir=<abs-Release-path> /DMyAppOutputDir=<abs-dir> /DMyAppOutputFilename=<name-no-ext> setup.iss
;
; User data is stored at:
;   %APPDATA%\AsanteDevs\Utility Bills Manager\

#define MyAppName        "Utility Bills Manager"
#define MyAppPublisher   "AsanteDevs"
#define MyAppExeName     "utility_bills_manager.exe"
#define MyAppID          "{DA4A79B2-5E3F-4C8A-B271-9E0F8A6C1D3E}"
; Data folder written by path_provider (CompanyName\ProductName from Runner.rc)
#define MyDataFolder     "AsanteDevs\Utility Bills Manager"

[Setup]
AppId={#MyAppID}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
; Directory page is shown — user can change this
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir={#MyAppOutputDir}
OutputBaseFilename={#MyAppOutputFilename}
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
MinVersion=10.0.17763
; Automatically close a running instance before upgrading
CloseApplications=yes
; Re-launch the app after install completes (only when user ticks "Launch" checkbox)
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}";       Filename: "{app}\{#MyAppExeName}"
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; \
  Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; \
  Flags: nowait postinstall skipifsilent

[Code]

// ── Helper: returns the two possible user-data directories ──────────────────

function AppDataPath: string;
begin
  Result := ExpandConstant('{userappdata}\{#MyDataFolder}');
end;

function LocalDataPath: string;
begin
  Result := ExpandConstant('{localappdata}\{#MyDataFolder}');
end;

// ── Upgrade detection ────────────────────────────────────────────────────────
// InnoSetup automatically detects an existing install via AppId and offers
// to update it.  The code below adds an extra guard: if the same version is
// already installed, ask the user before re-running the installer.

function InitializeSetup: Boolean;
var
  PrevVersion: string;
  RegKey: string;
begin
  Result := True;
  RegKey := 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' +
            '{#MyAppID}' + '_is1';
  if RegQueryStringValue(HKLM, RegKey, 'DisplayVersion', PrevVersion) or
     RegQueryStringValue(HKCU, RegKey, 'DisplayVersion', PrevVersion) then
  begin
    if PrevVersion = '{#MyAppVersion}' then
    begin
      if MsgBox(
        'Version {#MyAppVersion} is already installed.' + #13#10 +
        'Reinstall it anyway?',
        mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDNO then
        Result := False;
    end;
  end;
end;

// ── Uninstall: offer to remove user data ────────────────────────────────────
// Called at each stage of the uninstall process.
// usPostUninstall fires after all installed files have been removed,
// so user data (bills, database, settings) can still be found in %APPDATA%.

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  RoamPath, LocalPath: string;
  HasData: Boolean;
  Msg: string;
begin
  if CurUninstallStep <> usPostUninstall then Exit;

  RoamPath  := AppDataPath;
  LocalPath := LocalDataPath;
  HasData   := DirExists(RoamPath) or DirExists(LocalPath);

  if not HasData then Exit;

  Msg := 'Application data was found (bills history, database, settings):' + #13#10 + #13#10;
  if DirExists(RoamPath)  then Msg := Msg + '  ' + RoamPath  + #13#10;
  if DirExists(LocalPath) then Msg := Msg + '  ' + LocalPath + #13#10;
  Msg := Msg + #13#10 +
         'Remove this data?' + #13#10 + #13#10 +
         'Yes — delete everything (cannot be undone).' + #13#10 +
         'No  — keep data (safe to reinstall later without losing history).';

  if MsgBox(Msg, mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
  begin
    if DirExists(RoamPath)  then DelTree(RoamPath,  True, True, True);
    if DirExists(LocalPath) then DelTree(LocalPath, True, True, True);
  end;
end;
