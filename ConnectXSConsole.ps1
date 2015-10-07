#
# Name			: ConnectXSConsole.ps1
# Description   : Connects to the console of a VM hosted on a XenServer hypervisor
# Author 		: Ingmar Verheij - http://www.ingmarverheij.com/
# Version		: 1.0, 2 february 2012
#
# Requires		: plink (a command-line interface to the puTTY back ends)
#				  http://www.chiark.greenend.org.uk/~sgtatham/putty/download.html
#
#				  TightVNC Viewer
#				  http://www.tightvnc.com
#
# Todo			: Only Windows virtual machines work, other (linux, etc.) use 
#				  vncterm, which require to resolve the correct PID
#

function get-ProgramFilesDir{
  if (is64bit -eq $true) {
    (Get-Item "Env:ProgramFiles(x86)").Value
  }
  else {
    (Get-Item "Env:ProgramFiles").Value
  }
}

function is64bit{
  return ([IntPtr]::Size -eq 8)
}

function StartProcess([String]$FileName, [String]$Arguments){
    $process = New-Object "System.Diagnostics.Process"
    $startinfo = New-Object "System.Diagnostics.ProcessStartInfo"
    $startinfo.FileName = $FileName
    $startinfo.Arguments = $arguments 
    $startinfo.UseShellExecute = $false
    $startinfo.RedirectStandardInput = $true
    $startinfo.RedirectStandardOutput = $true
    $startinfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden 
    $process.StartInfo = $startinfo
    $temp = $process.start()
    return $process
}

#Region PrequisiteCheck
   #Check number of arguments
   If ($args.count -lt 0)
   {
      Write-Host "Usage"
      Write-Host "powershell.exe .\ConsoleConnect.ps1 (XenServerPoolMaster) (XenServerUsername) (XenServerPassword) (VMName) [CustomFieldName] [CustomFieldValue]"
      Write-Host ""
      Write-Host "Example"
      Write-Host "powershell.exe .\ConsoleConnect.ps1 172.16.1.1 root Passw0rd WS01 STUDENT 1"
      Write-Host "" 
      Write-Host "Press any key to continue ..."
      $x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
      break
   }
#EndRegion
#Region Define variables and read
   #Constants
   $vncUse8Bit = $true
   
   #Executables
   $strExecutablePLink='c:\windows\system32\plink.exe'
   if (is64bit -eq $true) {
      #$strExectableVNCViewer=(Get-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\TightVNC').Path+'\vncviewer.exe'
      $strExectableVNCViewer="C:\Program Files (x86)\TightVNC\vncviewer.exe"
      #$strExectableVNCViewer="C:\Program Files\TightVNC\tvnviewer.exe"
   }
   else
   {
      $strExectableVNCViewer="C:\Program Files (x86)\TightVNC\vncviewer.exe"
   }
   
   #File paths
   $strPathTemp = $Env:TEMP
   $strFileQueryHost = 'QueryHost'
   $strFileQueryPort = 'QueryPort'
   $strFileQueryXSVersion = 'QueryXSVersion'
   
   #Script variables
   #$XenServerHost=$args[0]
   $XenServerHost=Read-Host -Prompt 'Input XenServer pool'   
   $VirtualMachineName=Read-Host -Prompt 'VM name with UpperCase'      
      #$XenServerPassword=$args[2]
   $c=get-credential root
   $p=$c.getnetworkcredential().password
   $u=$c.Username
   $XenServerUsername=$u
   $XenServerPassword=$p
   #$VirtualMachineName=$args[3]
   If ($args.count -ge 6) {
   		$CustomFieldName=$args[4]
   		$CustomFieldValue=$args[5]
   } else {
   	  $CustomFieldName=""
   	  $CustomFieldValue=""
   }
   
   #Filter variables
   $strFilterVM='name-label="' + $VirtualMachineName+'"'
   IF ($CustomFieldName) {$strFilterVM+=' other-config:XenCenter.CustomFields.' + $CustomFieldName + '=' + $CustomFieldValue}
#EndRegion


#Prevent rsa2 key fingerprint message
#====================================
#The server's host key is not cached in the registry. You have no guarantee that the server is the computer you #think it is. 
#The server's rsa2 key fingerprint is: ssh-rsa 2048 7c:99:f3:31:38:ca:b7:b6:3b:21:53:55:ff:f3:76:1e
#If you trust this host, enter "y" to add the key to PuTTY's cache and carry on connecting.
#If you want to carry on connecting just once, without adding the key to the cache, enter "n".
#If you do not trust this host, press Return to abandon the connection.
#
#Run plink and confirm rsa2 key fingerprint with yes
#---------------------------------------------------
$process = StartProcess $strExecutablePLink (' -l '+$XenServerUsername+' -pw '+$XenServerPassword+' '+$XenServerHost+' exit')
$process.StandardInput.WriteLine('y')


#Determine host where the VM is running
#======================================
#
#Create a script to query a XenServer where the VM is hosted
#----------------------------------------------------------
New-Item $strPathTemp -Name $strFileQueryHost -type file -Force  | Out-Null
Add-Content ($strPathTemp + '\' + $strFileQueryHost) -Value ('varResidentOnUUID=$(xe vm-list '+$strFilterVM+' params=resident-on --minimal)')
Add-Content ($strPathTemp + '\' + $strFileQueryHost) -Value ('varResidentOnIP=$(xe pif-list management=true params=IP host-uuid=$varResidentOnUUID --minimal)')
Add-Content ($strPathTemp + '\' + $strFileQueryHost) -Value ('echo $varResidentOnIP')

#Run the script on the specified XenServer
#-----------------------------------------
$process = StartProcess $strExecutablePLink (' -l '+$XenServerUsername+' -pw '+$XenServerPassword+' '+$XenServerHost+' -m '+($strPathTemp + '\' + $strFileQueryHost))
$XenServerHostRunningVM = $process.StandardOutput.ReadLine()
Remove-Item ($strPathTemp+'\'+$strFileQueryHost)

#Determine if the virtual machine can be found
#---------------------------------------------
if(!$XenServerHostRunningVM) {
   Write-Host "The virtual machine '"$VirtualMachineName"' could not be found."
   Write-Host "" 
   Write-Host "Press any key to continue ..."
   $x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
   break
} 
else {
    Write-Host "The virtual machine '"$VirtualMachineName"' is running on host "$XenServerHostRunningVM
}


#Determine version XenServerHostRunningVM
#==============================================
#
#Create a script to query the XenServer where the VM is running on what version XenServer API
#----------------------------------------------------------------------------------------------
New-Item $strPathTemp -Name $strFileQueryXSVersion -type file -Force | Out-Null
Add-Content ($strPathTemp + '\' + $strFileQueryXSVersion) -Value ('varXSVersion=$(cat /etc/xensource-inventory |grep PRODUCT_VERSION= |cut -d= -f2 |cut -c 2-2)')
Add-Content ($strPathTemp + '\' + $strFileQueryXSVersion) -Value ('echo $varXSVersion')

#Run the script on the specified XenServer
#-----------------------------------------
$process = StartProcess $strExecutablePLink (" -l " + $XenServerUsername + " -pw " + $XenServerPassword + " " +  $XenServerHostRunningVM + " -m " + ($strPathTemp + '\' + $strFileQueryXSVersion))
$process.StandardInput.WriteLine('y')
$XenServerVersion = $process.StandardOutput.ReadLine()
Remove-Item ($strPathTemp+'\'+$strFileQueryXSVersion)
Write-Host "The version Citrix XenServer where running '"$VirtualMachineName"' is "$XenServerVersion


#Determine the port nummer where VNC is running
#==============================================
#
#Create a script to query the XenServer where the VM is running on what TCP port VNC is running
#----------------------------------------------------------------------------------------------
New-Item $strPathTemp -Name $strFileQueryPort -type file -Force | Out-Null
if ($XenServerVersion -gt 5) {
    Add-Content ($strPathTemp + '\' + $strFileQueryPort) -Value ('varDomPrefix=qemu-dm-')
}
else {
    Add-Content ($strPathTemp + '\' + $strFileQueryPort) -Value ('varDomPrefix=qemu.')
}

Add-Content ($strPathTemp + '\' + $strFileQueryPort) -Value ('varDomId=$(xe vm-list '+$strFilterVM+' params=dom-id --minimal)')
Add-Content ($strPathTemp + '\' + $strFileQueryPort) -Value ('[ -z $varDomId ] && (varDomPrefix=vncterm;varDomId=$(xe vm-list name-label="' + $VirtualMachineName + '" other-config:XenCenter.CustomFields.' + $CustomFieldName + '=' + $CustomFieldValue + ' params=dom-id --minimal))')
Add-Content ($strPathTemp + '\' + $strFileQueryPort) -Value ('varTCPPort=$(netstat -lp|grep -w $varDomPrefix$varDomId|awk ''{print $4}''|cut -d: -f2)')
Add-Content ($strPathTemp + '\' + $strFileQueryPort) -Value ('echo $varTCPPort')

#Run the script on the specified XenServer
#-----------------------------------------
$process = StartProcess $strExecutablePLink (" -l " + $XenServerUsername + " -pw " + $XenServerPassword + " " +  $XenServerHostRunningVM + " -m " + ($strPathTemp + '\' + $strFileQueryPort))
$process.StandardInput.WriteLine('y')
$VirtualMachineVNCPort = $process.StandardOutput.ReadLine()
Remove-Item ($strPathTemp+'\'+$strFileQueryPort)


#Determine if the VNC port can be found
#--------------------------------------
if(!$VirtualMachineVNCPort) {
   Write-Host "The VNC port for virtual machine '"$VirtualMachineName"' could not be found."
   Write-Host "" 
   Write-Host "Press any key to continue ..."
   $x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
   break
} 
else {
   $VirtualMachineVNCPort = [int]$VirtualMachineVNCPort
   Write-Host "The VNC port for virtual machine '"$VirtualMachineName"' is "$VirtualMachineVNCPort
}


#Open an SSH tunnel to map the port to the localhost
#===================================================
$processPLink=StartProcess $strExecutablePLink (' -N -l ' + $XenServerUsername + ' -pw ' + $XenServerPassword + ' ' +  $XenServerHostRunningVM + ' -L ' + $VirtualMachineVNCPort +':localhost:'+$VirtualMachineVNCPort +' '+$XenServerHostRunningVM) 

#Configure VNC to use 8 bit (if necessary)
#=========================================
$intVNCPort = ([int]$VirtualMachineVNCPort)-5900
New-Item -Path ('HKCU:\SOFTWARE\ORL\VNCviewer\History\localhost:'+$intVNCPort) -Force | Out-Null
Set-ItemProperty -Path ('HKCU:\SOFTWARE\ORL\VNCviewer\History\localhost:'+$intVNCPort) -name '8bit' -type DWORD -value 1 -Force


#Start VNC to the VM
#===================
$processVNCViewer=StartProcess $strExectableVNCViewer ("localhost::"+$VirtualMachineVNCPort) 
$processVNCViewer.WaitForExit()



#Kill the SSH tunnel
#===================
$processPLink.Kill()
