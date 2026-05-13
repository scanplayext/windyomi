# Windyomi IPA Helper

Windows helper for launching the unsigned iOS IPA GitHub Actions workflow and
downloading the resulting artifact.

It does not compile iOS locally. Apple still requires macOS/Xcode for the IPA
build, so this tool automates the remote GitHub Actions build from Windows.

## Build the EXE

```powershell
dotnet publish tools\WindyomiIpaHelper -c Release -r win-x64 --self-contained false
```

The EXE will be generated at:

```text
tools\WindyomiIpaHelper\bin\Release\net8.0\win-x64\publish\WindyomiIpaHelper.exe
```

## Use

Create a GitHub token with Actions permissions and set it:

```powershell
$env:WINDYOMI_GITHUB_TOKEN = "YOUR_TOKEN"
```

Run:

```powershell
tools\WindyomiIpaHelper\bin\Release\net8.0\win-x64\publish\WindyomiIpaHelper.exe
```

The IPA will be downloaded to `dist/` by default.
