#Attention ce script requiert la derniere version de PSH

$random = Get-Random -Maximum 1000 #ajout d'un random pour lancer le renouvellement du certificat avant son expiration
Write-Host -ForegroundColor green $random

$email = "..." #email de contact
$CertRef = "...$random" #nom donné au certificat (alias)
$DNS = "..." #adresse DNS du site
$DNS2 = "..." #2eme adresse DNS du site (www. ... .fr)
$Alias = "...$random" #Alias certificat
$Alias2 = "...$random" #Alias certificat
$Website = "..." #nom du site dans iis
$ExportPath = "c:\cert\$CertRef" #emplacement export PFX
$Pass = "..." #Mot de pass PFX

Install-Module -Name ACMESharp -AllowClobber
Install-Module -Name ACMESharp.Providers.IIS

Import-Module ACMESharp

if ((Get-ACMEExtensionModule) -eq $null)
{
		# Importe le module ACMEExtansion s'il ne l'est pas déjà
		Enable-ACMEExtensionModule -ModuleName ACMESharp.Providers.IIS
}


## Initialize Vault
Initialize-ACMEVault

if ((Get-ACMEVault) -eq $null)
{
		# creer un vault s'il ne l'est pas déjà
		Initialize-ACMEVault
}


##Register Account on Let's Encrypt mail format user@entreprise.com
New-ACMERegistration -Contacts mailto:$email -AcceptTos


#######Validate Identifiers #############

## Make sure the IIS Challenge Handler is available =manual / iis
Get-ACMEChallengeHandlerProfile -ListChallengeHandlers 


## Create a new Identifier with Let's Encrypt
New-ACMEIdentifier -Dns $DNS -Alias $Alias
New-ACMEIdentifier -Dns $DNS2 -Alias $Alias2

## Handle the challenge using HTTP validation on IIS
Complete-ACMEChallenge -IdentifierRef $Alias -ChallengeType http-01 -Handler iis -Force -HandlerParameters @{ WebSiteRef = $Website }
Complete-ACMEChallenge -IdentifierRef $Alias2 -ChallengeType http-01 -Handler iis -Force -HandlerParameters @{ WebSiteRef = $Website }

## Tell Let's Encrypt it's OK to validate now
Submit-ACMEChallenge -IdentifierRef $Alias -ChallengeType http-01 -Force
Submit-ACMEChallenge -IdentifierRef $Alias2 -ChallengeType http-01 -Force

## You should see something like this (note the "Status" is "Pending"):
####IdentifierType : dns
####Identifier     : www.example.com
####Uri            : https://acme-v01.api.letsencrypt.org/acme/authz/J-C2p4ZjSEcQSIbDI_kAeMBrHs_mJsP6x0uZaLVlZdA
####Status         : pending
####Expires        : 7/22/2017 6:15:39 PM
####Challenges     : {, , iis}
####Combinations   : {2, 1, 0}



########Wait Let's encript valide cartif##########
Write-Host -ForegroundColor green 'attente de validation'
sleep -s 60

## Update the status of the Identifier
Update-ACMEIdentifier -IdentifierRef $Alias
Update-ACMEIdentifier -IdentifierRef $Alias2
## You should see something like this (note the "Status" is "Valid"):
####IdentifierType : dns
####Identifier     : www.example.com
####Uri            : https://acme-v01.api.letsencrypt.org/acme/authz/J-C2p4ZjSEcQSIbDI_kAeMBrHs_mJsP6x0uZaLVlZdA
####Status         : valid
####Expires        : 7/22/2017 6:15:39 PM
####Challenges     : {, , }
####Combinations   : {2, 1, 0}




############Generate Certificate############

New-ACMECertificate -Generate -IdentifierRef $Alias -AlternativeIdentifierRefs @($Alias2)  -Alias $CertRef
## You should see something like this:
####Id                       : 8071b73c-2fed-45df-93b0-85936aacb761
####Alias                    : cert-example-domains
####Label                    :
####Memo                     :
####IdentifierRef            : fa52309d-4184-4a8b-ad53-1682c15c3f03
####IdentifierDns            : www.example.com
####AlternativeIdentifierDns : 
####KeyPemFile               :
####CsrPemFile               :
####GenerateDetailsFile      : 8071b73c-2fed-45df-93b0-85936aacb761-gen.json
####CertificateRequest       :
####CrtPemFile               :
####CrtDerFile               :
####IssuerSerialNumber       :
####SerialNumber             :
####Thumbprint               :
####Signature                :
####SignatureAlgorithm       :


## Submit the certificate request to Let's Encrypt:
Submit-ACMECertificate -CertificateRef $CertRef
Update-ACMECertificate -CertificateRef $CertRef


#########Install############

## Make sure the IIS Installer is available = iis
Get-ACMEInstallerProfile -ListInstallers


## Install the cert on the alternate HTTPS binding, but only for one DNS name
Write-Host -ForegroundColor green 'Installation du certificat sur le site :'$website
Get-WebBinding -Port 443 -HostHeader $DNS | Remove-WebBinding
Install-ACMECertificate -CertificateRef $CertRef -Installer iis -InstallerParameters @{
  WebSiteRef = $website
  BindingHost = $DNS
  BindingPort = 443
  CertificateFriendlyName = $CertRef
}
Get-WebBinding -Port 443 -HostHeader $DNS2 | Remove-WebBinding
Install-ACMECertificate -CertificateRef $CertRef -Installer iis -InstallerParameters @{
  WebSiteRef = $website
  BindingHost = $DNS2
  BindingPort = 443
  CertificateFriendlyName = $CertRef
}

#########Export############

## Export Private key
Get-ACMECertificate $CertRef -ExportKeyPEM "$ExportPath.key.pem"


Get-ACMECertificate $CertRef -ExportPkcs12 "$ExportPath.pfx" -CertificatePassword $pass
Write-Host -ForegroundColor green 'Certificat exporter dans'$ExportPath


#######Renew###########
#To renew cert change Only Alias name