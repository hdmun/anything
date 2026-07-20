import os
import sys
import io
import time
import json
import argparse
import urllib.request
import urllib.error
from datetime import datetime
from collections import defaultdict

# Windows 환경에서 콘솔 출력 시 cp949 한글/이모지 인코딩 오류 방지
try:
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')
except AttributeError:
    sys.stdout = io.TextIOWrapper(sys.stdout.detach(), encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.detach(), encoding='utf-8')

# 노션 시스템 상수 ID 설정 (기존 notion_auto_sync.py와 동일하게 설정)
SCRAP_PARENT_PAGE_ID = "af301053-2e1a-4d8c-a071-87c096c8cb33"       # 스크랩 정리 (부모 카테고리 루트)
FALLBACK_UNCLASSIFIED_ID = "6ab19da5-70f8-4930-9e87-8580de1a6c85"   # 미분류 (기본 Fallback 폴더)
ARCHIVE_FOLDER_NAME = "중복 정리"                                    # 임시 보관 카테고리 폴더 이름

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LOGS_DIR = os.path.join(SCRIPT_DIR, "logs")
os.makedirs(LOGS_DIR, exist_ok=True)

START_TIME_STR = datetime.now().strftime("%Y%m%d_%H%M%S")
LOG_FILE_PATH = os.path.join(LOGS_DIR, f"dedup_{START_TIME_STR}.log")
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
    """노션 '스크랩 정리' 하위 블록을 조회하여 실시간 카테고리 목록(ID:이름)을 구성합니다."""
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
                categories[cid] = title
        log(f"실시간 카테고리 로드 완료 (총 {len(categories)}개 감지)")
        return categories
    except Exception as e:
        log(f"카테고리 실시간 조회 실패: {e}")
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

def get_pages_in_category(category_id, category_name):
    """지정한 카테고리 페이지 하위의 자식 페이지 리스트를 모두 조회합니다."""
    pages = []
    has_more = True
    start_cursor = None
    
    log(f"'{category_name}' 카테고리 내 페이지 조회 시작...")
    while has_more:
        endpoint = f"/blocks/{category_id}/children?page_size=100"
        if start_cursor:
            endpoint += f"&start_cursor={start_cursor}"
            
        try:
            data = notion_api_request(endpoint, method="GET")
            results = data.get("results", [])
            for block in results:
                # 자식 페이지 타입만 스크랩 페이지로 수집
                if block.get("type") == "child_page" and not block.get("in_trash", False):
                    pages.append({
                        "id": block["id"],
                        "title": block["child_page"]["title"],
                        "created_time": block["created_time"],
                        "category_id": category_id,
                        "category_name": category_name
                    })
            
            has_more = data.get("has_more", False)
            start_cursor = data.get("next_cursor")
            time.sleep(0.3)  # API 부하 방지
        except Exception as e:
            log(f"'{category_name}' 카테고리 내 페이지 조회 중 오류 발생: {e}")
            break
            
    log(f"'{category_name}' 카테고리 조회 완료: 총 {len(pages)}개 페이지 발견")
    return pages

def move_page(page_id, target_parent_id, title):
    """지정한 페이지를 노션 상의 타겟 카테고리로 이동시킵니다."""
    endpoint = f"/pages/{page_id}/move"
    payload = {
        "parent": {
            "type": "page_id",
            "page_id": target_parent_id
        }
    }
    notion_api_request(endpoint, method="POST", payload=payload)

def main():
    parser = argparse.ArgumentParser(description="Notion 중복 스크랩 정리 스크립트")
    parser.add_argument(
        "--execute",
        action="store_true",
        help="실제 페이지 이동을 수행합니다. (지정하지 않으면 시뮬레이션 모드로 동작)"
    )
    args = parser.parse_args()

    is_dry_run = not args.execute

    log("==========================================")
    log("Notion 중복 스크랩 정리 작업을 시작합니다.")
    if is_dry_run:
        log("⚠️ 현재 모드: Dry-run (실제 이동은 수행하지 않고 대상만 출력)")
    else:
        log("🚀 현재 모드: Execution (실제 중복 정리 폴더로 이동 수행)")
    log("==========================================")

    # API 자격증명 유효성 검사
    if not NOTION_TOKEN or not NOTION_TOKEN.startswith("ntn_") or len(NOTION_TOKEN) < 10:
        log("[오류] 유효하지 않은 Notion Token입니다. notion_sync.env 설정을 점검하십시오.")
        return

    try:
        # 1. 노션 상의 카테고리 목록 조회
        categories = fetch_notion_categories()
        
        # 2. "중복 정리" 임시 보관 카테고리 식별 혹은 생성
        archive_folder_id = None
        for cid, name in categories.items():
            if name == ARCHIVE_FOLDER_NAME:
                archive_folder_id = cid
                break
                
        if not archive_folder_id:
            if is_dry_run:
                log(f"[안내] '{ARCHIVE_FOLDER_NAME}' 카테고리가 노션에 존재하지 않습니다. 실제 실행 시 동적으로 생성됩니다.")
            else:
                archive_folder_id = create_new_category(ARCHIVE_FOLDER_NAME)
                categories[archive_folder_id] = ARCHIVE_FOLDER_NAME
        else:
            log(f"임시 보관 폴더 식별 완료: '{ARCHIVE_FOLDER_NAME}' (ID: {archive_folder_id})")

        # 3. 모든 카테고리(단, "중복 정리" 자체는 제외) 하위의 페이지들 수집
        all_pages = []
        for cid, name in categories.items():
            if cid == archive_folder_id:
                # 이미 중복 정리 폴더에 들어있는 페이지는 중복 수집 대상에서 제외
                continue
            
            category_pages = get_pages_in_category(cid, name)
            all_pages.extend(category_pages)
            time.sleep(0.5)

        log(f"총 수집된 스크랩 페이지 수: {len(all_pages)}개")

        if not all_pages:
            log("수집된 페이지가 없어 작업을 마칩니다.")
            return

        # 4. 제목 기준 그룹화
        pages_by_title = defaultdict(list)
        for page in all_pages:
            title = page["title"].strip()
            if title:  # 빈 제목 제외
                pages_by_title[title].append(page)

        # 5. 중복 판정 및 보존/이동 분류
        to_move = []
        retained = []
        
        for title, pages in pages_by_title.items():
            if len(pages) > 1:
                # 생성 시간(created_time) 기준 정렬 (오름차순: 옛날 페이지 -> 최신 페이지)
                # ISO 8601 문자열 포맷이므로 단순 문자열 정렬이 시간 정렬과 일치함
                sorted_pages = sorted(pages, key=lambda x: x["created_time"])
                
                # 가장 최근 스크랩 페이지 남김 (마지막 요소)
                keep_page = sorted_pages[-1]
                move_pages = sorted_pages[:-1]
                
                retained.append(keep_page)
                to_move.extend(move_pages)

        # 6. 결과 리포트 및 실제 실행
        log(f"\n================ [분석 결과] ================")
        log(f"검사 대상 고유 제목 수: {len(pages_by_title)}")
        log(f"중복 그룹 발견 수: {len(retained)}")
        log(f"이동 대상 중복 페이지 수: {len(to_move)}개")
        log(f"=============================================\n")

        if not to_move:
            log("발견된 중복 스크랩 페이지가 없습니다. 작업을 마칩니다.")
            return

        # 중복 그룹별 매핑 출력
        log("📋 중복 페이지 목록 및 처리 예정 상세:")
        for title, pages in pages_by_title.items():
            if len(pages) > 1:
                sorted_pages = sorted(pages, key=lambda x: x["created_time"])
                keep_page = sorted_pages[-1]
                move_pages = sorted_pages[:-1]
                
                log(f"\n제목: \"{title}\"")
                log(f"  ✅ [보존] 카테고리: {keep_page['category_name']} | 생성일: {keep_page['created_time']} | ID: {keep_page['id']}")
                for mp in move_pages:
                    log(f"  📦 [이동 예정] 카테고리: {mp['category_name']} | 생성일: {mp['created_time']} | ID: {mp['id']}")

        log("\n=============================================")
        if is_dry_run:
            log("⚠️ Dry-run 모드가 활성화되어 있어 페이지를 이동하지 않았습니다.")
            log("실제 이동을 원하시면 다음 명령어로 스크립트를 실행해 주세요:")
            log("python notion_deduplicate.py --execute")
        else:
            log("🚀 중복 페이지 이동 처리를 시작합니다...")
            success_count = 0
            for i, page in enumerate(to_move):
                page_id = page["id"]
                title = page["title"]
                orig_cat = page["category_name"]
                
                log(f"[{i+1}/{len(to_move)}] '{title}' (기존: {orig_cat}) -> '{ARCHIVE_FOLDER_NAME}' 이동 중...")
                try:
                    move_page(page_id, archive_folder_id, title)
                    success_count += 1
                    time.sleep(0.5)  # API Rate limit 방지
                except Exception as e:
                    log(f"   ❌ 이동 실패: {e}")

            log(f"\n이동 완료: 총 {len(to_move)}개 중 {success_count}개 성공적으로 이동되었습니다.")

    except Exception as e:
        log(f"[치명적 오류] 중복 정리 작업 중 예외 발생: {e}")

if __name__ == "__main__":
    main()
