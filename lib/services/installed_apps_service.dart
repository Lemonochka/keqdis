import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class InstalledApp {
  final String name;
  final String? publisher;
  final String executableName;
  final String? executablePath;
  final String? installLocation;
  final String? iconBase64;

  InstalledApp({
    required this.name,
    this.publisher,
    required this.executableName,
    this.executablePath,
    this.installLocation,
    this.iconBase64,
  });
}

class InstalledAppsService {
  static const _skipNamePatterns = [
    'visual c++', '.net framework', '.net runtime', '.net desktop',
    'redistributable', 'hotfix', 'security update', 'service pack',
    'kb2', 'kb3', 'kb4', 'kb5', 'windows update', 'microsoft update',
    'windows sdk', 'windows driver kit', 'windows subsystem',
    'directx', 'vcredist', 'msofficemui', 'microsoft edge update',
    'microsoft edge webview', 'webview2', 'windows app runtime',
    'windows desktop runtime', 'asp.net', 'intel driver',
    'amd software installer', 'nvidia graphics driver',
    'realtek', 'driver', 'firmware',
  ];

  static const _skipExePatterns = [
    'unins', 'setup', 'install', 'update', 'repair', 'crash',
    'helper', 'redist', 'updater', 'uninstall', 'crashpad',
    'breakpad', 'sentry', 'report', 'elevate', 'maintenancetool',
    'elevatedinstaller',
  ];

  static const _skipProcessNames = [
    'system', 'registry', 'smss', 'csrss', 'wininit', 'winlogon',
    'services', 'lsass', 'svchost', 'dwm', 'conhost', 'dllhost',
    'rundll32', 'msiexec', 'sihost', 'fontdrvhost', 'spoolsv',
    'searchindexer', 'audiodg', 'ctfmon', 'dashost', 'runtimebroker',
    'shellexperiencehost', 'startmenuexperiencehost', 'searchhost',
    'textinputhost', 'applicationframehost', 'systemsettings',
    'smartscreen', 'wmiprvse', 'unsecapp', 'sppsvc', 'vssvc',
    'musnotifyicon', 'compattelrunner', 'taskhostw', 'taskhost',
    'wudfhost', 'securityhealthservice', 'securityhealthsystray',
    'useroobebroker', 'lockapp', 'logonui', 'lsaiso', 'memory compression',
    'msmpeng', 'nissrv', 'antimalware service executable',
    'device census', 'sedlauncher', 'werfault', 'wermgr',
  ];

  /// Возвращает объединённый список из реестра
  static Future<List<InstalledApp>> getInstalledApps() async {
    if (!Platform.isWindows) return [];

    final skipNamePs = _skipNamePatterns
        .map((p) => p.replaceAll("'", "''"))
        .join('|');
    final skipExePs = _skipExePatterns.join('|');

    final psScript = '''
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

\$skipName = '($skipNamePs)'
\$skipExe  = '^($skipExePs)'

\$seen   = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
\$result = [System.Collections.Generic.List[PSObject]]::new()

function Get-IconBase64(\$path) {
  try {
    if (-not \$path -or -not (Test-Path \$path -ErrorAction SilentlyContinue)) { return \$null }
    \$icon = [System.Drawing.Icon]::ExtractAssociatedIcon(\$path)
    if (-not \$icon) { return \$null }
    \$bmp = \$icon.ToBitmap()
    \$ms  = [System.IO.MemoryStream]::new()
    \$bmp.Save(\$ms, [System.Drawing.Imaging.ImageFormat]::Png)
    \$b64 = [Convert]::ToBase64String(\$ms.ToArray())
    \$ms.Dispose(); \$bmp.Dispose(); \$icon.Dispose()
    return \$b64
  } catch { return \$null }
}

function Add-App(\$name, \$publisher, \$exeName, \$exePath, \$location) {
  if (-not \$name -or -not \$exeName) { return }
  if (\$name -match \$skipName) { return }
  if (\$exeName -match \$skipExe) { return }
  if (-not \$seen.Add(\$exeName.ToLower())) { return } # дедуп без регистра
  \$icon = Get-IconBase64 \$exePath
  \$result.Add([PSCustomObject]@{
    name      = \$name
    publisher = \$publisher
    exe       = \$exeName
    exePath   = \$exePath
    location  = \$location
    icon      = \$icon
  })
}

\$regPaths = @(
  'HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
  'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*',
  'HKLM:\\Software\\Wow6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*'
)

foreach (\$regPath in \$regPaths) {
  if (-not (Test-Path \$regPath -ErrorAction SilentlyContinue)) { continue }
  \$entries = Get-ItemProperty \$regPath -ErrorAction SilentlyContinue |
    Where-Object {
      \$_.DisplayName -and
      -not [string]::IsNullOrWhiteSpace(\$_.DisplayName) -and
      \$_.SystemComponent -ne 1 -and
      \$_.ReleaseType -notin @('Update','Hotfix','Security Update')
    }

  foreach (\$e in \$entries) {
    \$exeName = \$null; \$exePath = \$null

    # Fallback 1: DisplayIcon
    if (\$e.DisplayIcon) {
      \$p = \$e.DisplayIcon -replace '"','' -replace ',\\s*-?\\d+\$','' -replace '\\s+\$',''
      if (\$p -match '\\.exe\$' -and (Test-Path \$p -ErrorAction SilentlyContinue)) {
        \$n = [IO.Path]::GetFileName(\$p)
        if (\$n -notmatch \$skipExe) { \$exeName = \$n; \$exePath = \$p }
      }
    }

    # Fallback 2: InstallLocation
    if (-not \$exeName -and \$e.InstallLocation) {
      \$loc = \$e.InstallLocation.Trim().Trim('"')
      if (\$loc -and (Test-Path \$loc -ErrorAction SilentlyContinue)) {
        \$f = Get-ChildItem -Path \$loc -Filter '*.exe' -File -ErrorAction SilentlyContinue |
          Where-Object { \$_.Name -notmatch \$skipExe } |
          Sort-Object Length -Descending | Select-Object -First 1
        if (\$f) { \$exeName = \$f.Name; \$exePath = \$f.FullName }
      }
    }

    # Fallback 3: UninstallString
    if (-not \$exeName -and \$e.UninstallString) {
      \$uDir = [IO.Path]::GetDirectoryName((\$e.UninstallString -replace '"','' -replace '\\s+/.*\$',''))
      if (\$uDir -and (Test-Path \$uDir -ErrorAction SilentlyContinue)) {
        \$f = Get-ChildItem -Path \$uDir -Filter '*.exe' -File -ErrorAction SilentlyContinue |
          Where-Object { \$_.Name -notmatch \$skipExe } |
          Sort-Object Length -Descending | Select-Object -First 1
        if (\$f) { \$exeName = \$f.Name; \$exePath = \$f.FullName }
      }
    }

    Add-App \$e.DisplayName.Trim() \$e.Publisher \$exeName \$exePath \$e.InstallLocation
  }
}

\$shell = New-Object -ComObject WScript.Shell
\$startDirs = @(
  [Environment]::GetFolderPath('CommonPrograms'),
  [Environment]::GetFolderPath('Programs')
)

foreach (\$dir in \$startDirs) {
  if (-not \$dir -or -not (Test-Path \$dir)) { continue }
  Get-ChildItem -Path \$dir -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    try {
      \$sc = \$shell.CreateShortcut(\$_.FullName)
      \$target = \$sc.TargetPath
      if (-not \$target -or \$target -notmatch '\\.exe\$') { return }
      if (-not (Test-Path \$target -ErrorAction SilentlyContinue)) { return }
      \$exeN = [IO.Path]::GetFileName(\$target)
      \$appN = [IO.Path]::GetFileNameWithoutExtension(\$_.Name)
      Add-App \$appN \$null \$exeN \$target ([IO.Path]::GetDirectoryName(\$target))
    } catch {}
  }
}
[Runtime.InteropServices.Marshal]::ReleaseComObject(\$shell) | Out-Null

\$result | Sort-Object name | ConvertTo-Json -Compress -Depth 1
''';

    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', psScript],
        runInShell: false,
      ).timeout(const Duration(seconds: 60));

      if (result.exitCode != 0) {
        debugPrint('InstalledAppsService: ${result.stderr}');
        return [];
      }
      final output = result.stdout.toString().trim();
      if (output.isEmpty || output == 'null') return [];
      return _parse(output);
    } catch (e) {
      debugPrint('InstalledAppsService error: $e');
      return [];
    }
  }

  /// Возвращает список запущенных прямо сейчас процессов с иконками
  static Future<List<InstalledApp>> getRunningProcesses() async {
    if (!Platform.isWindows) return [];

    final skipPs = _skipProcessNames
        .map((p) => "'${p.replaceAll("'", "''")}'")
        .join(',');

    final psScript = '''
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

\$skipList = @($skipPs)
\$seen     = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
\$result   = [System.Collections.Generic.List[PSObject]]::new()

function Get-IconBase64(\$path) {
  try {
    if (-not \$path -or -not (Test-Path \$path -ErrorAction SilentlyContinue)) { return \$null }
    \$icon = [System.Drawing.Icon]::ExtractAssociatedIcon(\$path)
    if (-not \$icon) { return \$null }
    \$bmp = \$icon.ToBitmap()
    \$ms  = [System.IO.MemoryStream]::new()
    \$bmp.Save(\$ms, [System.Drawing.Imaging.ImageFormat]::Png)
    \$b64 = [Convert]::ToBase64String(\$ms.ToArray())
    \$ms.Dispose(); \$bmp.Dispose(); \$icon.Dispose()
    return \$b64
  } catch { return \$null }
}

Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
  if (\$_.Name -in \$skipList) { return }
  if (\$_.Id -le 4) { return }
  try {
    \$path = \$_.MainModule.FileName
    if (-not \$path -or \$path -notmatch '\\.exe\$') { return }

    \$exeN = [IO.Path]::GetFileName(\$path)
    if (-not \$seen.Add(\$exeN)) { return }

    # Имя = Process.Name (то что видно в Task Manager) — самое надёжное.
    # MainWindowTitle кривое ("Главная — Google Chrome") и меняется постоянно.
    # Пользователь ищет по имени которое видит в диспетчере задач.
    \$displayName = \$_.Name

    \$icon = Get-IconBase64 \$path

    \$result.Add([PSCustomObject]@{
      name     = \$displayName
      exe      = \$exeN
      exePath  = \$path
      location = [IO.Path]::GetDirectoryName(\$path)
      icon     = \$icon
    })
  } catch {}
}

\$result | Sort-Object name | ConvertTo-Json -Compress -Depth 1
''';

    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', psScript],
        runInShell: false,
      ).timeout(const Duration(seconds: 20));

      if (result.exitCode != 0) {
        debugPrint('InstalledAppsService [running]: ${result.stderr}');
        return [];
      }
      final output = result.stdout.toString().trim();
      if (output.isEmpty || output == 'null') return [];
      return _parse(output);
    } catch (e) {
      debugPrint('InstalledAppsService [running] error: $e');
      return [];
    }
  }

  static List<InstalledApp> _parse(String jsonStr) {
    try {
      final dynamic decoded = json.decode(jsonStr);
      final List<dynamic> list =
      decoded is List ? decoded : (decoded is Map ? [decoded] : []);

      return list.whereType<Map>().map((item) {
        final name = item['name'] as String? ?? '';
        final exe = item['exe'] as String? ?? '';
        if (name.isEmpty || exe.isEmpty) return null;

        return InstalledApp(
          name: name,
          publisher: (item['publisher'] as String?)?.isNotEmpty == true
              ? item['publisher'] as String
              : null,
          executableName: exe,
          executablePath: item['exePath'] as String?,
          installLocation: item['location'] as String?,
          iconBase64: item['icon'] as String?,
        );
      }).whereType<InstalledApp>().toList();
    } catch (e) {
      debugPrint('InstalledAppsService parse error: $e');
      return [];
    }
  }
}