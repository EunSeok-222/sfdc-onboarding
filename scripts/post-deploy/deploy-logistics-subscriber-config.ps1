# DESC: 「물류 통보 이벤트」 트리거(LogisticsNotifyEvent)의 실행 사용자를 연동 사용자로 지정한다 (배포 후 수작업, D10 Step 5R)
# 실행: powershell -ExecutionPolicy Bypass -File scripts/post-deploy/deploy-logistics-subscriber-config.ps1 -TargetOrg kai-dev
# NOTE: PlatformEventSubscriberConfig에는 Username이 들어간다. Username은 org에서 Alias로 조회해 임시 사본에만 채우고,
#       배포가 끝나면(실패해도) 임시 사본을 지운다. 레포에는 자리를 비운 틀(logistics-subscriber-config/)만 둔다
# NOTE: npm으로 설치한 sf는 PowerShell 래퍼(sf.ps1)라 CLI 경고(stderr)가 오류 레코드로 바뀐다 —
#       sf 호출은 ErrorActionPreference를 Stop으로 두지 않고 종료 코드($LASTEXITCODE)로 판단한다
# WARN: Username은 화면에 출력하지 않는다
param(
  [Parameter(Mandatory = $true)][string]$TargetOrg,
  [string]$IntegrationAlias = 'lgproc'
)
$ErrorActionPreference = 'Continue'
$env:SF_SKIP_NEW_VERSION_CHECK = 'true'
$templateDir = Join-Path $PSScriptRoot 'logistics-subscriber-config'
$configRelPath = 'PlatformEventSubscriberConfigs\LogisticsNotifyEventConfig.platformEventSubscriberConfig'

# 1) 연동 사용자 Username 조회 (출력하지 않음)
$query = "SELECT Username FROM User WHERE Alias = '$IntegrationAlias' AND IsActive = true"
$queryJson = (sf data query -q $query -o $TargetOrg --json 2>$null) | Out-String
if ($LASTEXITCODE -ne 0) { throw "연동 사용자 조회 실패 (exit $LASTEXITCODE)" }
$queryResult = ($queryJson | ConvertFrom-Json).result
if ($null -eq $queryResult -or $queryResult.totalSize -ne 1) {
  throw "연동 사용자(Alias $IntegrationAlias)를 org $TargetOrg 에서 1명으로 특정할 수 없습니다."
}
$username = $queryResult.records[0].Username

# 2) 임시 사본에 채워 배포 → 3) 사본 삭제
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ('pesc-' + [guid]::NewGuid())
try {
  Copy-Item -LiteralPath $templateDir -Destination $tempDir -Recurse -ErrorAction Stop
  $configPath = Join-Path $tempDir $configRelPath
  $content = [IO.File]::ReadAllText($configPath, [Text.Encoding]::UTF8).Replace('{{INTEGRATION_USERNAME}}', $username)
  [IO.File]::WriteAllText($configPath, $content, (New-Object Text.UTF8Encoding $false))
  Write-Host "대상 org: $TargetOrg · 실행 사용자: Alias $IntegrationAlias · 컴포넌트: PlatformEventSubscriberConfig:LogisticsNotifyEventConfig"
  sf project deploy start --metadata-dir $tempDir -o $TargetOrg --wait 10 2>$null
  if ($LASTEXITCODE -ne 0) { throw "배포 실패 (exit $LASTEXITCODE)" }
} finally {
  if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
  Write-Host "임시 사본 삭제: $(-not (Test-Path -LiteralPath $tempDir))"
}
