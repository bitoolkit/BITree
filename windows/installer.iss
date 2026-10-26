[Setup]
AppId=dev.so1ve.bitree
AppName=BITree
AppVersion={#AppVersion}
AppPublisher=BITree
AppPublisherURL=https://github.com/so1ve/bitree
DefaultDirName={localappdata}\Programs\BITree
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
WizardStyle=modern
SourceDir=..
OutputDir=dist
OutputBaseFilename={#OutputName}
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\bitree.exe
Compression=lzma2/ultra64
SolidCompression=yes

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\BITree"; Filename: "{app}\bitree.exe"
