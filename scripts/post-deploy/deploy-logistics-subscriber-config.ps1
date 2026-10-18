# DESC: 「물류 통보 이벤트」 트리거(LogisticsNotifyEvent)의 실행 사용자를 연동 사용자로 지정한다 (배포 후 수작업, D10 Step 5R)
# 실행: powershell -ExecutionPolicy Bypass -File scripts/post-deploy/deploy-logistics-subscriber-config.ps1 -TargetOrg kai-dev
# NOTE: PlatformEventSubscriberConfig에는 Username이 들어간다. Username은 org에서 Alias로 조회해 임시 사본에만 채우고,
#       배포가 끝나면(실패해도) 임시 사본을 지운다. 레포에는 자리를 비운 틀(logistics-subscriber-config/)만 둔다
# NOTE: npm으로 설치한 sf는 PowerShell 래퍼(sf.ps1)라 CLI 경고(stderr)가 오류 레코드로 바뀐다 —
#       sf 호출은 ErrorActionPreference를 Stop으로 두지 않고 종료 코드($LASTEXITCODE)로 판단한다
# WARN: Username은 화면에 출력하지 않는다
# WARN: 배포만으로는 적용되지 않는다 — 이미 구독 중인 트리거는 설정을 캐시해 기본 실행 사용자(Automated Process)로
#       계속 돈다(D11 실측: 콜아웃이 External Credential 접근 불가로 실패). 배포 뒤 아래 수작업을 반드시 한다
# NOTE: 두 org 전체 배포 후 수작업은 scripts/post-deploy/README.md — 아래 1~4는 이 스크립트와 관련된 kai-dev 항목만
# 배포 후 수작업(대상 org마다):
#   1) 구독 재시작: Setup → Quick Find 「Platform Events」 → 「물류 통보 이벤트」 → Subscriptions의
#      LogisticsNotifyEvent 옆 Manage → Suspend → (State Suspended 확인) → Resume from Tip → State Running 확인.
#      「Resume」은 버스에 남은 예전 이벤트부터 다시 처리하므로 「Resume from Tip」을 누른다
#   2) 적용 확인: 깨우기 스크립트(scripts/apex/logisticsNotifyWakeUp.apex) 실행 뒤 Setup → Apex Jobs에서
#      LogisticsNotifyQueueable의 Submitted By가 연동 사용자(「물류 연동 처리」)인지 본다. Process Automated면 미적용
#   3) 권한 집합 「물류 통보 요청」(LogisticsNotifyRequestAccess)을 공급 제한 승인자(권역팀장)에게 할당한다 —
#      없으면 승인 때 이벤트 발행이 실패해 로그가 전송대기로 남고 오류 메시지에 「이벤트 발행 실패」가 기록된다
#   4) 연동 사용자에게 권한 집합 「물류 연동」(LogisticsIntegrationAccess)이 할당돼 있는지 확인한다 — External Credential
#      Principal 접근과 「User External Credential」 오브젝트 Read를 함께 준다. Read가 없으면 콜아웃이
#      "You don't have read permissions on the User External Credential object"로 실패한다(D11 실측, 관리자는 프로필에 있어 안 보임).
#      Apex 테스트는 Mock이라 이 권한을 검증하지 못한다 — 깨우기 스크립트로 실제 1건을 보내 로그 「성공」까지 확인한다
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
  Write-Host "다음 수작업: 구독 재시작(Suspend → Resume from Tip) → Apex Jobs 제출자 확인 → 승인자에게 「물류 통보 요청」 할당 (스크립트 맨 위 주석 참고)"
} finally {
  if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
  Write-Host "임시 사본 삭제: $(-not (Test-Path -LiteralPath $tempDir))"
}
