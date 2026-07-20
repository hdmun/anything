import os
import sys
import io
import time
import json
import subprocess
import urllib.request
import urllib.error
from datetime import datetime

# Windows 환경에서 콘솔 출력 시 cp949 한글/이모지 인코딩 오류 방지
try:
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
except AttributeError:
    sys.stdout = io.TextIOWrapper(sys.stdout.detach(), encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.detach(), encoding='utf-8')

# 노션 시스템 상수 ID 설정
SCRAP_SOURCE_PAGE_ID = "71ada71d-dce3-4842-a221-a04499d3fe7e"       # 스크랩 (원본 모니터링 폴더)
SCRAP_PARENT_PAGE_ID = "af301053-2e1a-4d8c-a071-87c096c8cb33"       # 스크랩 정리 (부모 카테고리 루트)
FALLBACK_UNCLASSIFIED_ID = "6ab19da5-70f8-4930-9e87-8580de1a6c85"   # 미분류 (기본 Fallback 폴더)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LOGS_DIR = os.path.join(SCRIPT_DIR, "logs")
os.makedirs(LOGS_DIR, exist_ok=True)

START_TIME_STR = datetime.now().strftime("%Y%m%d_%H%M%S")
LOG_FILE_PATH = os.path.join(LOGS_DIR, f"sync_{START_TIME_STR}.log")
ENV_FILE_PATH = os.path.join(SCRIPT_DIR, "notion_sync.env")

def log(message):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    full_message = f"[{timestamp}] {message}"
    print(full_message)
    try:
        with open(LOG_FILE_PATH, "a", encoding="utf-8") as f:
            f.write(full_message + "\n")
    except Exception as e:
        print(f"로그 파일 쓰기 오류: {e}")

def load_env():
    env_vars = {}
    if os.path.exists(ENV_FILE_PATH):
        with open(ENV_FILE_PATH, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    env_vars[k.strip()] = v.strip()
    else:
         log(f"경고: 설정 파일({ENV_FILE_PATH})을 찾을 수 없습니다. 기본 환경 변수를 사용합니다.")
    return env_vars

# 환경 변수 및 설정 로드
ENV = load_env()
NOTION_TOKEN = ENV.get("NOTION_TOKEN")

AGY_MODEL = "Gemini 3.5 Flash (Low)"

NOTION_HEADERS = {
    "Authorization": f"Bearer {NOTION_TOKEN}",
    "Notion-Version": "2022-06-28",
    "Content-Type": "application/json"
}

def notion_api_request(endpoint, method="GET", payload=None):
    url = f"https://api.notion.com/v1{endpoint}"
    data = json.dumps(payload).encode('utf-8') if payload else None
    req = urllib.request.Request(url, data=data, headers=NOTION_HEADERS, method=method)
    
    retries = 3
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req) as response:
                if response.status in [200, 201]:
                    return json.loads(response.read().decode('utf-8'))
        except urllib.error.HTTPError as e:
            if e.code == 429:
                retry_after = int(e.headers.get("Retry-After", 5))
                log(f"[대기] Notion Rate Limit 감지! {retry_after}초 후 재시도합니다.")
                time.sleep(retry_after)
            else:
                try:
                    error_detail = e.read().decode('utf-8')
                except Exception:
                    error_detail = str(e)
                log(f"[에러] Notion API 오류 (HTTP {e.code}): {error_detail}")
                raise e
        except Exception as e:
            log(f"[오류] 네트워크 연결 장애: {e}. 3초 후 재시도합니다.")
            time.sleep(3)
    raise Exception("Notion API 최대 재시도 횟수를 초과했습니다.")

def fetch_notion_categories():
    """노션 '스크랩 정리' 하위 블록을 조회하여 실시간 카테고리 목록(ID:이름)을 동적으로 구성합니다."""
    log("노션에서 실시간 카테고리 목록을 로드하는 중...")
    categories = {}
    endpoint = f"/blocks/{SCRAP_PARENT_PAGE_ID}/children?page_size=100"
    
    try:
        data = notion_api_request(endpoint, method="GET")
        results = data.get("results", [])
        for block in results:
            if block.get("type") == "child_page" and not block.get("in_trash", False):
                cid = block["id"]
                title = block["child_page"]["title"]
                # 미분류 폴더 자체는 동적 분류 분석 대상 카테고리 명단에서 제외
                if cid != FALLBACK_UNCLASSIFIED_ID:
                    categories[cid] = title
        log(f"실시간 카테고리 로드 완료 (총 {len(categories)}개 감지)")
        return categories
    except Exception as e:
        log(f"카테고리 실시간 동적 조회 실패: {e}")
        raise e

def create_new_category(category_name):
    """노션 '스크랩 정리' 폴더 하위에 새 카테고리 페이지를 생성하고 생성된 페이지 ID를 반환합니다."""
    log(f"[새 카테고리 생성] 노션에 '{category_name}' 카테고리 페이지 생성을 시도합니다...")
    endpoint = "/pages"
    payload = {
        "parent": {
            "type": "page_id",
            "page_id": SCRAP_PARENT_PAGE_ID
        },
        "properties": {
            "title": {
                "title": [
                    {
                        "text": {
                            "content": category_name
                        }
                    }
                ]
            }
        }
    }
    try:
        res = notion_api_request(endpoint, method="POST", payload=payload)
        new_page_id = res.get("id")
        log(f"[생성 완료] 새 카테고리 '{category_name}' 생성 성공 (ID: {new_page_id})")
        return new_page_id
    except Exception as e:
        log(f"[생성 에러] 노션 새 카테고리 생성 중 실패: {e}")
        raise e

def append_error_block_to_notion(error_msg):
    """Notion 미분류 페이지 상단에 에러 알림 콜아웃 블록을 주입합니다."""
    try:
        endpoint = f"/blocks/{FALLBACK_UNCLASSIFIED_ID}/children"
        payload = {
            "children": [
                {
                    "object": "block",
                    "type": "callout",
                    "callout": {
                        "rich_text": [
                            {
                                "type": "text",
                                "text": {
                                    "content": f"🚨 [Notion 스크랩 동기화 오류] {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n{error_msg}"
                                }
                            }
                        ],
                        "icon": {
                            "type": "emoji",
                            "emoji": "🚨"
                        },
                        "color": "red_background"
                    }
                }
            ]
        }
        notion_api_request(endpoint, method="PATCH", payload=payload)
        log("노션 미분류 페이지에 오류 경고 블록이 생성되었습니다.")
    except Exception as e:
        log(f"노션에 오류 블록 생성 실패: {e}")

def get_new_scraps():
    """스크랩 페이지 하위에 새로 수집된 자식 페이지 리스트를 조회합니다."""
    scraps = []
    has_more = True
    start_cursor = None
    
    while has_more:
        endpoint = f"/blocks/{SCRAP_SOURCE_PAGE_ID}/children?page_size=100"
        if start_cursor:
            endpoint += f"&start_cursor={start_cursor}"
            
        data = notion_api_request(endpoint, method="GET")
        results = data.get("results", [])
        for block in results:
            if block.get("type") == "child_page" and not block.get("in_trash", False):
                scraps.append({
                    "id": block["id"],
                    "title": block["child_page"]["title"]
                })
        
        has_more = data.get("has_more", False)
        start_cursor = data.get("next_cursor")
        time.sleep(0.5)
        
    return scraps


def parse_agy_response(text_response):
    """agy 응답 텍스트에서 JSON 배열 데이터를 파싱합니다."""
    text_clean = text_response.strip()

    # 마크다운 코드 블록 지시자 제거
    if "```json" in text_clean:
        text_clean = text_clean.split("```json")[-1].split("```")[0].strip()
    elif "```" in text_clean:
        text_clean = text_clean.split("```")[1].split("```")[0].strip()

    # 괄호 매칭으로 '[' ~ ']' 배열 범위 엄격하게 추출
    start_idx = text_clean.find("[")
    if start_idx != -1:
        bracket_count = 0
        end_idx = -1
        for idx in range(start_idx, len(text_clean)):
            if text_clean[idx] == "[":
                bracket_count += 1
            elif text_clean[idx] == "]":
                bracket_count -= 1
                if bracket_count == 0:
                    end_idx = idx
                    break
        if end_idx != -1:
            text_clean = text_clean[start_idx:end_idx + 1]

    try:
        result = json.loads(text_clean)
        if isinstance(result, list):
            return result
        # 단일 객체 응답은 리스트로 래핑하여 방어 처리
        log("[경고] agy가 배열 대신 단일 객체로 응답했습니다. 리스트로 래핑합니다.")
        return [result]
    except Exception as parse_err:
        log(f"[치명적] JSON 배열 파싱 실패. 원본 응답:\n{text_response}")
        raise parse_err


def classify_all_scraps_with_agy(scraps, current_categories):
    """agy CLI를 한 번 호출하여 모든 스크랩 페이지를 일괄 분류합니다.
    PROMPT.md가 위치한 SCRIPT_DIR을 --add-dir로 전달하여 agy가 직접 참조하도록 합니다."""
    categories_text = "\n".join(
        [f"- {name} (ID: {cid})" for cid, name in current_categories.items()]
    )
    pages_text = "\n".join(
        [f"- page_id: {s['id']}, 제목: \"{s['title']}\"" for s in scraps]
    )
    prompt_text = (
        "PROMPT.md 파일의 지시 사항에 따라 아래 페이지들을 분류해줘.\n\n"
        f"분류할 페이지 목록:\n{pages_text}\n\n"
        f"기존 카테고리 목록:\n{categories_text}"
    )

    cmd = [
        "agy",
        "--model", AGY_MODEL,
        "--add-dir", SCRIPT_DIR,
        "--prompt", prompt_text
    ]
    log(f"[agy] 일괄 분류 호출 시작: 총 {len(scraps)}개 페이지")

    retries = 5
    for attempt in range(retries):
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                encoding="utf-8",
                timeout=300  # 배치 처리이므로 타임아웃을 300초로 설정
            )

            if result.returncode != 0:
                stderr_msg = result.stderr.strip()
                log(f"[경고] agy 프로세스가 비정상 종료되었습니다 (코드 {result.returncode}): {stderr_msg}")
                if attempt < retries - 1:
                    log(f"  => {attempt + 1}/{retries}회 시도 실패. 10초 후 재시도합니다.")
                    time.sleep(10)
                    continue
                raise Exception(f"agy 실행 실패 (반환 코드 {result.returncode}): {stderr_msg}")

            text_response = result.stdout.strip()
            log(f"[디버그] agy 원본 응답:\n{text_response}\n----------------------------------")

            return parse_agy_response(text_response)

        except subprocess.TimeoutExpired:
            log(f"[경고] agy 배치 호출 시간 초과 (300초). (시도 {attempt+1}/{retries})")
            if attempt < retries - 1:
                time.sleep(5)
                continue
            raise Exception("agy 배치 호출이 최대 제한 시간을 초과했습니다.")
        except Exception as e:
            log(f"agy 호출 중 오류 발생: {e}")
            raise e

    raise Exception("agy 최대 재시도 횟수를 초과했습니다.")

def move_page(page_id, target_parent_id, title):
    """지정한 페이지를 노션 상의 타겟 카테고리(부모)로 이동시킵니다."""
    endpoint = f"/pages/{page_id}/move"
    payload = {
        "parent": {
            "type": "page_id",
            "page_id": target_parent_id
        }
    }
    notion_api_request(endpoint, method="POST", payload=payload)

def main():
    log("==========================================")
    log("Notion 스크랩 자동 동기화 작업을 시작합니다.")
    log("==========================================")
    
    # API 자격증명 기초 유효성 검사
    if not NOTION_TOKEN or NOTION_TOKEN.startswith("ntn_") is False or len(NOTION_TOKEN) < 10:
        err = "유효하지 않은 Notion Token입니다. .env 설정을 점검하십시오."
        log(err)
        return
        
    try:
        # 1. 노션 상의 기존 카테고리 목록을 실시간으로 가져옵니다 (하드코딩 제거)
        CATEGORIES = fetch_notion_categories()
        
        scraps = get_new_scraps()
        log(f"조회 완료: 분류 대기 중인 새 스크랩 문서 {len(scraps)}개 발견")
        
        if not scraps:
            log("동기화할 새로운 스크랩이 없습니다. 작업을 마칩니다.")
            return
            
        success_count = 0

        # 2. agy 1회 호출로 전체 페이지 일괄 분류
        try:
            classifications = classify_all_scraps_with_agy(scraps, CATEGORIES)
        except Exception as e:
            log(f"[치명적 오류] agy 일괄 분류 실패로 작업을 조기 중단합니다: {e}")
            raise e

        # 분류 결과를 page_id 기준으로 인덱싱 (순서 변경에 안전한 매핑)
        classification_map = {c["page_id"]: c for c in classifications if "page_id" in c}

        # 3. 개별 페이지 Notion 이동 처리
        for i, scrap in enumerate(scraps):
            page_id = scrap["id"]
            title = scrap["title"]
            log(f"[{i+1}/{len(scraps)}] '{title}' 이동 처리 시작...")

            classification = classification_map.get(page_id)
            if not classification:
                log(f"   => [경고] '{title}'의 분류 결과가 없습니다. 미분류로 처리합니다.")
                classification = {"category_id": None, "category_name": None, "reason": "분류 결과 누락"}

            try:
                target_id = classification.get("category_id")
                category_name = classification.get("category_name")
                reason = classification.get("reason", "이유 없음")

                # 신규 카테고리 생성 조건 처리
                if target_id == "NEW_CATEGORY" and category_name:
                    # 같은 배치 내 중복 생성 방지: 이미 동일 이름의 카테고리가 만들어진 경우 재사용
                    existing_id = next(
                        (cid for cid, name in CATEGORIES.items() if name == category_name), None
                    )
                    if existing_id:
                        target_id = existing_id
                        target_name = category_name
                        log(f"   => [재사용] '{category_name}' 카테고리가 이미 존재하여 재사용합니다.")
                    else:
                        log(f"   => [신설 카테고리 감지] AI가 새 카테고리 '{category_name}' 생성을 제안했습니다.")
                        try:
                            # 3-1. 노션에 신규 카테고리 페이지 동적 생성
                            target_id = create_new_category(category_name)
                            # 3-2. 현재 실행 세션 카테고리 맵에 추가 (이후 반복 시 재사용)
                            CATEGORIES[target_id] = category_name
                            target_name = category_name
                        except Exception as cat_err:
                            log(f"   => [생성 실패 오류] 새 카테고리 생성에 실패하여 미분류 폴더로 대체 전송합니다: {cat_err}")
                            target_id = FALLBACK_UNCLASSIFIED_ID
                            target_name = "미분류 (Fallback)"

                elif target_id and target_id in CATEGORIES:
                    target_name = CATEGORIES[target_id]
                    log(f"   => [분류] AI 판단 카테고리: {target_name} ({reason})")
                else:
                    target_id = FALLBACK_UNCLASSIFIED_ID
                    target_name = "미분류 (Fallback)"
                    log(f"   => [보류] 매핑 불확실하여 미분류 폴더로 전송합니다. ({reason})")

                # 3-3. 최종 노션 페이지 이동
                move_page(page_id, target_id, title)
                log(f"   => [완료] '{title}'이(가) '{target_name}' 카테고리로 성공적으로 이동되었습니다.")
                success_count += 1

            except Exception as e:
                log(f"   => [실패] '{title}' 노션 이동 처리 중 오류 발생: {e}")
                # 이동 에러가 났을 때 미분류 폴더로 최종 복구 이동 시도
                try:
                    move_page(page_id, FALLBACK_UNCLASSIFIED_ID, title)
                    log(f"   => [복구] 안전 예외 처리를 위해 미분류 폴더로 강제 이동시켰습니다.")
                except Exception as inner_err:
                    log(f"   => [복구 실패] 미분류 폴더 이동 마저 실패: {inner_err}")

        log(f"모든 분류 작업 완료: 총 {len(scraps)}개 중 {success_count}개 정상 처리 완료.")
        
    except Exception as e:
        err_msg = f"동기화 루프가 치명적인 예외로 중단되었습니다: {e}"
        log(err_msg)
        append_error_block_to_notion(err_msg)

if __name__ == "__main__":
    main()
