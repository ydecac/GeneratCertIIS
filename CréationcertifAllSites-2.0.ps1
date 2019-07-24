<# .SYNOPSIS
Configuration des certificats sur les sites IIS presents sur le serveur
il est lié aux informations contenus dans le JSON lié
Il utilise ce JSON pour charger toutes les variables

Attention ce script requiert la derniere version de PSH

.EXAMPLE
.CréationcertifAllSites-2.0.ps1
genere des certif et les ajoute aux sites IIS selon le JSON.

.NOTES
Auteur : Yves de Cacqueray

Version G2R0 : nouvelle version pour Ameliorer le script et simplifier la maintenance
 #>


 Get-Date -Format "yyyyMMdd"
$random = Get-Date -Format "yyyyMMdd" #ajout d'un random pour lancer le renouvellement du certificat avant son expiration
Write-Host -ForegroundColor green $random

Try {
	$global:jsonConfiguration = Get-Content -Path "$(pwd)\paramfile.json" -Raw -ErrorAction Stop | ConvertFrom-Json
	Write-Host "All variables loaded in memory" -ForegroundColor Green
}
Catch {
	throw "KO - Error loading variables. $($_)"
}


$CertRef = $global:jsonConfiguration.global.Nom+$random #nom donné au certificat (alias)
$ExportPath = "$(pwd)\$CertRef" #emplacement export PFX
$email = $global:jsonConfiguration.global.email #email de contact" #email de contact


Install-Module -Name ACMESharp -AllowClobber
Install-Module -Name ACMESharp.Providers.IIS

Import-Module ACMESharp

if ($null -eq (Get-ACMEExtensionModule))
{
		# Importe le module ACMEExtansion s'il ne l'est pas déjà
		Enable-ACMEExtensionModule -ModuleName ACMESharp.Providers.IIS
}


## Initialize Vault
if (!(Get-ACMEVault))
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
ForEach ($Site in $global:jsonConfiguration.sites) 
{
  Write-Host "création du ACMEIdentifier du site"$Site.Nom"" -ForegroundColor Green
  ForEach ($Alias in $site.Alias) 
  {
    Write-Host $Alias -ForegroundColor Green
    New-ACMEIdentifier -Dns $Alias -Alias $Alias$random
  }
}

## Handle the challenge using HTTP validation on IIS

ForEach ($Site in $global:jsonConfiguration.sites) 
{
  Write-Host "Complete ACMEChallenge pour le site"$Site.Nom"" -ForegroundColor Green
  ForEach ($Alias in $site.Alias) 
  {
    Write-Host $Alias -ForegroundColor Green
    Complete-ACMEChallenge -IdentifierRef $Alias$random -ChallengeType http-01 -Handler iis -Force -HandlerParameters @{ WebSiteRef = $Site.Nom }
  }
}


## Tell Let's Encrypt it's OK to validate now

ForEach ($Alias in $global:jsonConfiguration.sites.alias) 
{
  Write-Host "Soumetre ACMEChallenge pour le site:$Alias$random" -ForegroundColor Green
  Submit-ACMEChallenge -IdentifierRef $Alias$random -ChallengeType http-01 -Force
}


## You should see something like this (note the "Status" is "Pending"):
####IdentifierType : dns
####Identifier     : www.example.com
####Uri            : https://acme-v01.api.letsencrypt.org/acme/authz/J-C2p4ZjSEcQSIbDI_kAeMBrHs_mJsP6x0uZaLVlZdA
####Status         : pending
####Expires        : 7/22/2017 6:15:39 PM
####Challenges     : {, , iis}
####Combinations   : {2, 1, 0}


########Wait Let's encript valide cartif##########
Write-Host -ForegroundColor Yellow 'attente de validation'
sleep -s 60

## Update the status of the Identifier
ForEach ($Alias in $global:jsonConfiguration.sites.alias) 
{
  Write-Host "Mise a jour du statut de ACMEIdentifier du site: $Alias" -ForegroundColor Green
  Update-ACMEIdentifier -IdentifierRef $Alias$random
}

## You should see something like this (note the "Status" is "Valid"):
####IdentifierType : dns
####Identifier     : www.example.com
####Uri            : https://acme-v01.api.letsencrypt.org/acme/authz/J-C2p4ZjSEcQSIbDI_kAeMBrHs_mJsP6x0uZaLVlZdA
####Status         : valid
####Expires        : 7/22/2017 6:15:39 PM
####Challenges     : {, , }
####Combinations   : {2, 1, 0}




############Generate Certificate############

$PrincipalDNS = $global:jsonConfiguration.sites.alias[0] #ne prendre que le 1er de la liste
#Ajout du random a chaque element de l'array et ne prend que les ellements qui sont different du principal DNS (SAN)
$SanAlias = foreach ( $node in ($global:jsonConfiguration.sites.alias | Where-Object { $_ –ne "$principalDns" }))
    {
        "$node$random"
    }

New-ACMECertificate -Generate -IdentifierRef $PrincipalDNS$random -AlternativeIdentifierRefs $SanAlias  -Alias $CertRef
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
ForEach ($Site in $global:jsonConfiguration.sites) 
{
  ForEach ($Alias in $site.Alias) 
  {
    Write-Host "Installation du certificat sur le binding :"$Alias -ForegroundColor green
    Get-WebBinding -Port 443 -HostHeader $Alias | Remove-WebBinding
    Install-ACMECertificate -CertificateRef $CertRef -Installer iis -InstallerParameters @{
      WebSiteRef = $Site.Nom
      BindingHost = $Alias
      BindingPort = 443
      CertificateFriendlyName = $CertRef
    }
  }
}

#########Export############

## Export Private key
Get-ACMECertificate $CertRef -ExportKeyPEM "$ExportPath.key.pem"


Get-ACMECertificate $CertRef -ExportPkcs12 "$ExportPath.pfx" -CertificatePassword $global:jsonConfiguration.global.pass
Write-Host -ForegroundColor green 'Certificat exporter dans'$ExportPath


#######Renew###########
#To renew cert change Only Alias name
#fait automatiquement avec le random du debut