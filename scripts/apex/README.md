# scripts/apex

- **시연 초기화 순서**: `demo-rehearsal-cleanup.apex`(kai-dev) 미리보기 → 실행 → 출력된 상관 ID를 `demo-rehearsal-cleanup-logistics.apex`(hankki-logistics)에 넣어 미리보기 → 실행 → `demo-scene5-reset.apex`(kai-dev)로 DEMO-005 · 006 다시 생성. 두 정리 스크립트는 `EXECUTE = false`(미리보기)가 기본이다.
- 인터페이스 로그가 재시도대기면 정리하지 말고, 성공 또는 실패(중단)가 된 뒤 실행한다 — 대기 중에 지우면 진행 중인 물류 통보와 엇갈린다.
