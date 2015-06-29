$VerbosePreference = 'Continue'

### Amend these URLs to swap out Mercurial / Python versions ###
$mercurialurl = 'http://mercurial.selenic.com/release/windows/mercurial-2.9.0-x64.msi'
$pythonurl = 'http://www.python.org/ftp/python/2.7.6/python-2.7.6.amd64.msi'
$exeurl = 'http://mercurial.selenic.com/release/windows/mercurial-2.9.win-amd64-py2.7.exe'
$rewriteurl = 'http://download.microsoft.com/download/6/7/D/67D80164-7DD0-48AF-86E3-DE7A182D6815/rewrite_2.0_rtw_x64.msi'

### Amend these paths to change default locations ###
$repoPath = 'C:\repos'
$parentSite = 'Default Web Site'
$virtualDirectory = 'hg'

$hgpath = 'C:\Python27\Lib\site-packages\mercurial\hgweb'
$testRepo = ([IO.Path]::Combine($repoPath, 'test'))
$location = '{0}/{1}' -f $parentSite, $virtualDirectory

$hgweb = @'
#!/usr/bin/env python
#
# See also http://mercurial.selenic.com/wiki/PublishingRepositories
# Path to repo or hgweb config to serve (see 'hg help hgweb')
config = "{0}"

# Uncomment and adjust if Mercurial is not installed system-wide
# (consult "installed modules" path from 'hg debuginstall'):
#import sys; sys.path.insert(0, "/path/to/python/lib")

# Uncomment to send python tracebacks to the browser if an error occurs:
#import cgitb; cgitb.enable()

from mercurial import demandimport; demandimport.enable()
from mercurial.hgweb import hgweb, wsgicgi
application = hgweb(config)
wsgicgi.launch(application)
'@ -f ([IO.Path]::Combine($hgPath, 'hgweb.config'))

$hgconfig = @'
[web]
encoding = UTF-8
allow_push = *
push_ssl = False
allowzip = True

[paths]
test = {0}
'@ -f ([IO.Path]::Combine($repoPath, 'test'))

Function DownloadFileToTemp
{
    param
    (
        [Parameter()]
        [String]$Url
    )

    $fileName = [system.io.path]::GetFileName($url)
    $tmpFilePath = [system.io.path]::Combine($env:TEMP, $fileName)

    $wc = new-object System.Net.WebClient
    $wc.DownloadFile($url, $tmpFilePath)
    $wc.Dispose()

    return $tmpFilePath
}

Write-Verbose ("Downloading Mercurial from '{0}'." -f $mercurialurl)
$mercurialmsi = DownloadFileToTemp $mercurialurl

Write-Verbose ("Downloading Python from '{0}'." -f $pythonurl)
$pythonmsi = DownloadFileToTemp $pythonurl

Write-Verbose ("Downloading Mercurial source installer from '{0}'." -f $exeurl)
$mixedexe = DownloadFileToTemp $exeurl

Write-Verbose 'Getting local WMI installer class.'
$installer = [wmiclass]"\\.\root\cimv2:Win32_Product"

Write-Verbose ("Installing Python MSI from '{0}'." -f $pythonmsi)
[void]($installer.Install($pythonmsi, 'TARGETDIR=C:\Python27', $true))

Write-Verbose ("Installing Mercurial MSI from '{0}'." -f $mercurialmsi)
[void]($installer.Install($mercurialmsi, $null, $true))

Write-Verbose 'Starting Mercurial source installer (Next, next, next)...'
Start-Process $mixedexe -PassThru | Wait-Process

Write-Verbose 'Installing IIS and required features, if missing.'
[void](Add-WindowsFeature @("Web-CGI", "Web-ISAPI-Ext", "Web-ISAPI-Filter", "Web-Filtering", "Web-Basic-Auth", "Web-Windows-Auth") -IncludeManagementTools)

Write-Verbose ('Creating virtual directory ({0}).' -f $virtualDirectory)
[void](New-WebVirtualDirectory -Name $virtualDirectory -Site $parentSite -PhysicalPath $hgpath)

Write-Verbose 'Adding Python Script Handler for CGI.'
[void](New-WebHandler -Name Python -Path *.cgi -PSPath IIS: -ScriptProcessor 'c:\Python27\python.exe -u %s' -Verb '*' -Modules CgiModule -ResourceType File -Location $location)

Write-Verbose 'Adding Python CGI restriction allow rule.'
[void](Add-WebConfiguration -Filter "/system.webServer/security/isapiCgiRestriction" -PSPath 'IIS:' -Value @{path = 'c:\Python27\python.exe -u %s'; allowed = 'true' })

Write-Verbose 'Creating hgweb.cgi script.'
$hgweb | Out-File ([IO.PATH]::Combine($hgpath, 'hgweb.cgi')) -Force -Encoding ASCII

Write-Verbose 'Creating hgweb.config.'
$hgconfig | Out-File ([IO.PATH]::Combine($hgpath, 'hgweb.config')) -Force -Encoding ASCII

Write-Verbose 'Checking for test repo.'
if(!(Test-Path $testRepo))
{
    Write-Verbose 'Creating test repo.'
    [void](md $testRepo)
    [void](& 'c:\Program Files\Mercurial\hg.exe' init $testRepo)
}

Write-Verbose 'Opening Mercurial on local host.'
Start-Process ('http://localhost/{0}/hgweb.cgi' -f $virtualDirectory)