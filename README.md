# GeneratCertIIS
## Generation d'un certificat de site web a l'aide de Powershell pour serveur IIS

Ce Script a pour but de creer un certificat valide sur la plupart des navigateurs de façon gratuite depuis Let's Encript
Il peut etre automatisé avec un Task Sheduler

### Parti variable
C'est la premiere partie du script il faut ici remplacer les ... par les valeurs de votre site:

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

### Partie dependances
Il faut ajouter a powershell les dependances dont il a besoin en commancant par les installer puis en les important

Install-Module -Name ACMESharp -AllowClobber
Install-Module -Name ACMESharp.Providers.IIS

Import-Module ACMESharp

if ((Get-ACMEExtensionModule) -eq $null)
{
		# Importe le module ACMEExtansion s'il ne l'est pas déjà
		Enable-ACMEExtensionModule -ModuleName ACMESharp.Providers.IIS
}

### Création du Vault sur la machine

Initialize-ACMEVault

if ((Get-ACMEVault) -eq $null)
{
		# creer un vault s'il ne l'est pas déjà
		Initialize-ACMEVault
}

### Création du compte chez Let's Encrypt user@entreprise.com
New-ACMERegistration -Contacts mailto:$email -AcceptTos

### Validation des ellements du certificat

Get-ACMEChallengeHandlerProfile -ListChallengeHandlers 

New-ACMEIdentifier -Dns $DNS -Alias $Alias
New-ACMEIdentifier -Dns $DNS2 -Alias $Alias2

Complete-ACMEChallenge -IdentifierRef $Alias -ChallengeType http-01 -Handler iis -Force -HandlerParameters @{ WebSiteRef = $Website }
Complete-ACMEChallenge -IdentifierRef $Alias2 -ChallengeType http-01 -Handler iis -Force -HandlerParameters @{ WebSiteRef = $Website }

### Envoie a Let's Encript

Submit-ACMEChallenge -IdentifierRef $Alias -ChallengeType http-01 -Force
Submit-ACMEChallenge -IdentifierRef $Alias2 -ChallengeType http-01 -Force

Write-Host -ForegroundColor green 'attente de validation'
sleep -s 60

Update-ACMEIdentifier -IdentifierRef $Alias
Update-ACMEIdentifier -IdentifierRef $Alias2

### Generation certificat

New-ACMECertificate -Generate -IdentifierRef $Alias -AlternativeIdentifierRefs @($Alias2)  -Alias $CertRef

Submit-ACMECertificate -CertificateRef $CertRef
Update-ACMECertificate -CertificateRef $CertRef

### Installation certificat sur site iis
j'ai ajouter un remove du binding pour qu'il n'y est pas de conflit et que ce script puisse etre joué plusieurs fois

Get-ACMEInstallerProfile -ListInstallers

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

### Export pour une autre machine ou un autre type de site

Get-ACMECertificate $CertRef -ExportKeyPEM "$ExportPath.key.pem"


Get-ACMECertificate $CertRef -ExportPkcs12 "$ExportPath.pfx" -CertificatePassword $pass

Write-Host -ForegroundColor green 'Certificat exporter dans'$ExportPath
