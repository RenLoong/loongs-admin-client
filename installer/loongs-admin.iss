; LOONGS Admin PC installer (Inno Setup 6)
#define MyAppName "LOONGS Admin"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "RenLoong"
#define MyAppExeName "client.exe"

[Setup]
AppId={{A7C3E9F1-4B2D-4E8A-9C1F-6D5B8A0E2F34}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\LOONGS\Admin
DefaultGroupName=LOONGS
DisableProgramGroupPage=yes
OutputDir=C:\Users\unkno\p1\admin-pc-winbuild\dist
OutputBaseFilename=LOONGS-Admin-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent