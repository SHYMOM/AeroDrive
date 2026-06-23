[Setup]
AppName=AeroDrive
AppVersion=1.0.0
AppPublisher=AeroDrive Open Source
AppPublisherURL=https://github.com/aerodrive/aerodrive
DefaultDirName={autopf}\AeroDrive
DefaultGroupName=AeroDrive
OutputDir=Output
OutputBaseFilename=AeroDrive_Setup
SetupIconFile=windows\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The main executable
Source: "build\windows\x64\runner\Release\aerodrive.exe"; DestDir: "{app}"; Flags: ignoreversion
; All other required files in the Release directory
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; IMPORTANT: Bundle tdjson.dll for TDLib FFI
Source: "build\windows\x64\runner\Release\tdjson.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\AeroDrive"; Filename: "{app}\aerodrive.exe"
Name: "{group}\{cm:UninstallProgram,AeroDrive}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\AeroDrive"; Filename: "{app}\aerodrive.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\aerodrive.exe"; Description: "{cm:LaunchProgram,AeroDrive}"; Flags: nowait postinstall skipifsilent

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
end;
