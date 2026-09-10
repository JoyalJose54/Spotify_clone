Set WshShell = CreateObject("WScript.Shell")
Dim fso, scriptDir, domainFile, domain
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)

domain = "removal-magnolia-overhand.ngrok-free.dev"
domainFile = scriptDir & "\ngrok_domain.txt"
If fso.FileExists(domainFile) Then
    Dim txt
    Set txt = fso.OpenTextFile(domainFile, 1)
    domain = Trim(txt.ReadLine)
    txt.Close
End If

' 1. Start Python backend silently
WshShell.CurrentDirectory = scriptDir & "\cloud_functions"
WshShell.Run "cmd /c python main.py", 0, False

' 2. Wait 2 seconds and launch Ngrok tunnel silently
WScript.Sleep 2000
WshShell.Run "cmd /c ngrok http --domain=" & domain & " 8080", 0, False

Set WshShell = Nothing
Set fso = Nothing
