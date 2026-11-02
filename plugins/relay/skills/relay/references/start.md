# 진행 세션 시작 (c) 0~2

> 이 파일은 SKILL.md의 단계 절차 중 일부다. SKILL.md의 불변식과 함께 읽는다. (진행 세션 시작)

## (c) 진행 세션 절차

0. **`orca skills get orchestration`으로 정본 가이드를 먼저 읽는다.**
   이 스킬이 적는 orca 명령은 작성 시점의 스냅숏이다. 정본은 바이너리가 직접 서빙하고 릴리스마다 바뀐다 —
   Orca가 배포하는 `orchestration` 스텁이 *"캐시된 복사본에서 서브커맨드나 플래그를 추측하지 말라"* 고
   명시한 이유가 이것이다. **충돌하면 정본이 옳고, 이 스킬을 고친다.**
   relay가 더하는 것은 명령 사용법이 아니라 그 위의 정책이다 — 역할 분리, 심각도 라우팅, 세션 폐기 규범.

   **relay 정책은 `relay_cli.py`가 판정한다** (ADR 0001). 이 스킬을 불러왔을 때 표시되는 *Base directory* 에서 두 단계 위가 플러그인 루트다:

   ```bash
   RELAY="<Base directory>/../.."          # 예: .../plugins/cache/hdmun-scripts/relay/1.2.0
   python "$RELAY/scripts/relay_cli.py" --help
   ```

   - **결정기**(`review-branch` 등)는 stdout에 JSON 한 줄을 낸다. 첫 키 `action`대로 행동하고, 판정 규칙을 이 문서에서 다시 계산하지 않는다.
   - **검사기**(`diff-guard`, `validate-review`)는 종료코드 0 통과 / 1 실패.
   - 종료코드 **2는 입력 오류**(경로·base 오타 등)다. 고쳐서 다시 부른다.

   **그리고 머신을 점검한다** — `python "$RELAY/scripts/relay_cli.py" doctor`. 셸 명령이라 비용이 0이다.
   - `FAIL`(종료코드 1)이면 시작하지 않는다. 출력의 `→` 줄(고치는 방법)을 사용자에게 전한다.
   - 특히 `FAIL plugin`은 **이 세션이 읽은 SKILL.md가 설치본보다 낡았다**는 뜻이다. 낡은 절차로 진행하면 이미 고친 문제를 다시 밟는다(실측 T-007: 1.2.3 설치 뒤에도 1.2.0 절차의 단독 `agy`로 띄워 9회 연속 timeout). 사용자에게 `/reload-plugins`나 세션 재시작을 요청하고 멈춘다.
   - `WARN version:*`(미검증 버전)이면 사용자에게 알리고 `relay_cli.py smoke --dir <trust 등록된 디렉터리>`를 권한다. smoke가 실패한 CLI로는 그 역할의 워커를 띄우지 않는다.
   - `FAIL models`는 모델 설정 파일(`~/.relay/models.json`, `.ai/relay-models.json`)이 잘못됐다는 뜻이다. 고치기 전에는 워커를 띄우지 않는다. 설정 파일이 없으면 `OK`다 — 기본 동작.
   - 그 밖의 `WARN`은 보고만 하고 진행한다.

   **그리고 이 진행 세션이 설정대로 떠 있는지 본다** — `python "$RELAY/scripts/relay_cli.py" model coordinator`. `action: session`의 `model`·`effort`가 있는데 지금 세션(`/model`로 확인)과 다르면 **사용자에게 `command`를 알리고 계속할지 묻는다.** 플러그인은 세션의 모델을 바꿀 수 없다. `model`이 `null`이면 설정이 없는 것이니 묻지 않는다.
1. `orca orchestration run-use --id <run_id> --json`
2. `orca orchestration task-list --ready --json` 로 다음 태스크를 꺼낸다. **태스크 상태를 컨텍스트에 들고 있지 말고 매번 Orca에 물어본다** (외부 메모리로 사용).
3. 워커 부트스트랩 — (d)
4. `worker-start` 후 대기 — (e)
5. 게이트 독립 재검증 — (f). **통과 즉시 구현 커밋한다. 리뷰 결과를 기다리지 않는다.**
6. 빈 diff 확인 후 리뷰 워커 기동(`<base>`를 spec에 넣는다) — (d), 리뷰 JSON 검증, 심각도 분기 — (g). 분기 결과와 무관하게 커밋은 이미 존재한다
7. PR 생성(경로 A) 또는 브랜치·커밋 목록 보고(경로 B) — (i)
8. **워커 정리** — `worker-release` + `trustedWorkspaces` 해제. `reclaimable`이 0인지 확인한 뒤 세션 폐기 — (i), (j)
