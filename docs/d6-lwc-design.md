## SC-03 매장 이력 타임라인 (Account 레코드 페이지)

### 화면 스케치

(ASCII나 손그림 사진. 가맹점 상단 요약 + 아래로 점검·시정·페널티가 시간순)

### 컴포넌트 트리

franchiseHistoryTimeline ← 부모. recordId를 받아 데이터 조회
└ timelineFilterBar ← 유형(점검/시정/페널티)·기간 필터
└ timelineItem (반복) ← 항목 한 개. 날짜·유형·요약·상태 배지

### @api / 이벤트

| 컴포넌트                 | @api          | 발생 이벤트  | 받는 쪽 |
| ------------------------ | ------------- | ------------ | ------- |
| franchiseHistoryTimeline | recordId      | -            | -       |
| timelineFilterBar        | selectedTypes | filterchange | 부모    |
| timelineItem             | item, isLast  | itemselect   | 부모    |

### 호출할 Apex

| 메서드                                                 | 반환                      | 비고                                |
| ------------------------------------------------------ | ------------------------- | ----------------------------------- |
| FranchiseHistoryController.getTimeline(Id franchiseId) | List<TimelineItemWrapper> | @AuraEnabled(cacheable=true) → wire |

### 결정해야 할 것

- 점검·시정·페널티를 **하나의 Wrapper**로 합칠지, 세 리스트로 줄지
- wire(자동 갱신·캐시) vs imperative(버튼으로 조회)
