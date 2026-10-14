/* ======================================================================================
 * @description : 내 점검 목록(inspectionList) 검색 · 정렬 · 페이징 컨트롤러
 * @testClass   : InspectionListControllerTest
 * @layer       : Controller
 * @author      : 이은석(Kai)
 * ======================================================================================
 *  Date         Modifier   Status      Description
 * --------------------------------------------------------------------------------------
 *  2026.10.13   Kai        Created     최초 작성
 *  2026.10.13   Kai        Updated     상태 조건 status → statuses(List) 변경 (칩 하나에 상태 여러 개)
 * ======================================================================================
 *  @see         : docs/d7-lwc-handoff.md §5
 *  @note        : BR-10(담당 매장만)은 with sharing + 공유 규칙이 거른다. 코드에 OwnerId 조건을 넣지 않는다
 * ======================================================================================*/
public with sharing class InspectionListController {
  // DESC: 정렬 허용 컬럼 화이트리스트 — 동적 SOQL의 ORDER BY에는 바인드 변수를 쓸 수 없어 문자열로 붙이므로 반드시 검증한다
  private static final Set<String> SORTABLE_FIELDS = new Set<String>{
    'InspectionDate__c',
    'Status__c',
    'Judgement__c'
  };
  private static final String DEFAULT_SORT_BY = 'InspectionDate__c';
  private static final Integer DEFAULT_PAGE_SIZE = 20;
  private static final Integer MAX_PAGE_SIZE = 200;
  // WARN: SOQL OFFSET 최대 2,000 — (pageNumber - 1) * pageSize가 넘으면 조회 불가. 점검 수가 늘면 Keyset 페이징으로 바꿔야 한다
  private static final Integer MAX_OFFSET = 2000;

  private static final String SELECT_FIELDS =
    'Id, Name, InspectionDate__c, Status__c, Judgement__c, ruTotalScore__c, ' +
    'Franchise__c, Franchise__r.Name, RecordType.Name';

  public class SearchCriteria {
    @AuraEnabled
    public String keyword { get; set; }
    // NOTE: 칩 하나가 상태 여러 개를 묶는다 (예: 시정 대기 = 시정중 + 지연). 칩 → 상태 매핑은 LWC가 가진다
    @AuraEnabled
    public List<String> statuses { get; set; } // null · 빈 목록이면 전체
    @AuraEnabled
    public String judgement { get; set; } // null이면 전체
    @AuraEnabled
    public Date dateFrom { get; set; }
    @AuraEnabled
    public Date dateTo { get; set; }
    @AuraEnabled
    public String sortBy { get; set; } // 화이트리스트 검증
    @AuraEnabled
    public String sortDir { get; set; } // asc | desc
    @AuraEnabled
    public Integer pageSize { get; set; }
    @AuraEnabled
    public Integer pageNumber { get; set; } // 1부터
  }

  public class InspectionPageWrapper {
    @AuraEnabled
    public List<Inspection__c> records;
    @AuraEnabled
    public Integer totalCount;
  }

  /**
   * @description : 조건에 맞는 점검 한 페이지와 전체 건수를 돌려준다.
   * @author      : 이은석(Kai) | 2026.10.13
   * @param criteria 검색 · 정렬 · 페이징 조건 (null이면 전체 · 기본 정렬 · 1페이지)
   * @return InspectionPageWrapper 현재 페이지 레코드와 전체 건수
   **/
  @AuraEnabled(cacheable=true)
  public static InspectionPageWrapper search(SearchCriteria criteria) {
    if (criteria == null) {
      criteria = new SearchCriteria();
    }
    String sortBy = resolveSortBy(criteria.sortBy);
    String sortDir = resolveSortDir(criteria.sortDir);
    Integer pageSize = resolvePageSize(criteria.pageSize);
    Integer pageNumber = (criteria.pageNumber == null ||
      criteria.pageNumber < 1)
      ? 1
      : criteria.pageNumber;
    Integer offsetCount = (pageNumber - 1) * pageSize;
    if (offsetCount > MAX_OFFSET) {
      throw newAuraException(
        '조회할 수 있는 범위를 넘었습니다. 검색 조건을 좁혀 주세요.'
      );
    }

    Map<String, Object> bindsByName = new Map<String, Object>();
    String whereClause = buildWhereClause(criteria, bindsByName);

    // NOTE: 정렬값이 같은 행이 많으면 페이지 경계에서 순서가 흔들려 중복·누락이 생기므로 Name으로 순서를 고정한다
    String recordQuery =
      'SELECT ' +
      SELECT_FIELDS +
      ' FROM Inspection__c' +
      whereClause +
      ' ORDER BY ' +
      sortBy +
      ' ' +
      sortDir +
      ' NULLS LAST, Name ASC' +
      ' LIMIT :pageSize OFFSET :offsetCount';
    bindsByName.put('pageSize', pageSize);
    bindsByName.put('offsetCount', offsetCount);

    InspectionPageWrapper page = new InspectionPageWrapper();
    // DESC: USER_MODE — sharing에 더해 오브젝트 · 필드 권한(FLS)까지 현재 사용자 기준으로 강제한다
    page.records = Database.queryWithBinds(
      recordQuery,
      bindsByName,
      AccessLevel.USER_MODE
    );
    page.totalCount = Database.countQueryWithBinds(
      'SELECT COUNT() FROM Inspection__c' + whereClause,
      bindsByName,
      AccessLevel.USER_MODE
    );
    return page;
  }

  /**
   * @description : 값이 있는 조건만 WHERE에 붙이고 값은 바인드 맵에 넣는다. 사용자 입력은 SOQL 문자열에 직접 붙이지 않는다.
   * @author      : 이은석(Kai) | 2026.10.13
   * @param criteria    검색 조건
   * @param bindsByName 바인드 변수 이름 → 값 (이 메서드가 채운다)
   * @return String ' WHERE ...' 또는 빈 문자열
   **/
  private static String buildWhereClause(
    SearchCriteria criteria,
    Map<String, Object> bindsByName
  ) {
    List<String> conditions = new List<String>();

    if (String.isNotBlank(criteria.keyword)) {
      conditions.add('Franchise__r.Name LIKE :keywordPattern');
      bindsByName.put('keywordPattern', '%' + criteria.keyword.trim() + '%');
    }
    if (criteria.statuses != null && !criteria.statuses.isEmpty()) {
      conditions.add('Status__c IN :statuses');
      bindsByName.put('statuses', criteria.statuses);
    }
    if (String.isNotBlank(criteria.judgement)) {
      conditions.add('Judgement__c = :judgement');
      bindsByName.put('judgement', criteria.judgement);
    }
    if (criteria.dateFrom != null) {
      conditions.add('InspectionDate__c >= :dateFrom');
      bindsByName.put('dateFrom', criteria.dateFrom);
    }
    if (criteria.dateTo != null) {
      conditions.add('InspectionDate__c <= :dateTo');
      bindsByName.put('dateTo', criteria.dateTo);
    }
    return conditions.isEmpty()
      ? ''
      : ' WHERE ' + String.join(conditions, ' AND ');
  }

  private static String resolveSortBy(String sortBy) {
    if (String.isBlank(sortBy)) {
      return DEFAULT_SORT_BY;
    }
    if (!SORTABLE_FIELDS.contains(sortBy)) {
      throw newAuraException('정렬할 수 없는 컬럼입니다: ' + sortBy);
    }
    return sortBy;
  }

  private static String resolveSortDir(String sortDir) {
    if (String.isBlank(sortDir)) {
      return 'ASC';
    }
    String upperSortDir = sortDir.toUpperCase();
    if (upperSortDir != 'ASC' && upperSortDir != 'DESC') {
      throw newAuraException(
        '정렬 방향은 asc 또는 desc만 가능합니다: ' + sortDir
      );
    }
    return upperSortDir;
  }

  private static Integer resolvePageSize(Integer pageSize) {
    if (pageSize == null || pageSize < 1) {
      return DEFAULT_PAGE_SIZE;
    }
    return Math.min(pageSize, MAX_PAGE_SIZE);
  }

  // NOTE: AuraHandledException은 setMessage를 하지 않으면 Apex(테스트 포함)에서 getMessage()가 'Script-thrown exception'으로 보인다
  private static AuraHandledException newAuraException(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
