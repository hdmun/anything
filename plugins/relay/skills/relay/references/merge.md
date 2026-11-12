# 머지와 연쇄 handoff

> 이 파일은 SKILL.md 의 단계 절차 중 일부다. SKILL.md 의 불변식과 함께 읽는다. (기동 줄에 `일괄 진행:` 이 있을 때만)

들어오는 곳은 `references/finish.md` 다: `publish pr` 이 `created` 또는 `exists` 를 냈고 기동 줄에 `일괄 진행:` 이 있을 때.

## 1. 머지 조건

```bash
python "$RELAY/scripts/relay_cli.py" merge-check --issue <구현 이슈 URL> --worktree <worktree>
```

- 종료코드 1 이면 멈춤 보고(PR 은 연 채) 「머지 조건 어긋남: <FAIL 검사 이름들>」 — (h).
- 머지를 막지 않는 것(기록만): 판정 `dismiss`·`accept`(PR 본문 「기각한 지적」), `MINOR` 만 남은 리뷰(「남은 MINOR」), doctor `WARN`(`warnings:`), 도중의 사람 개입 이력.

## 2. 머지 직전 (횟수 제한 없음)

1. `git -C <worktree> fetch origin main`. `origin/main` 이 HEAD 의 조상이 아니면 `git -C <worktree> rebase origin/main`. 충돌이면 `git -C <worktree> rebase --abort` 뒤 멈춤 보고 「main 과 충돌: <파일>」. 충돌 해결을 구현자에게 맡기지 않는다(리뷰를 거치지 않은 코드가 된다).
2. rebase 했으면 `python "$RELAY/scripts/relay_cli.py" publish push --worktree <worktree> --force-with-lease`. `stop` 이면 멈춤 보고. main 은 어떤 경우에도 force push 하지 않는다.
3. 지금 HEAD SHA 와 `origin/main` SHA(= base)를 적어 둔다. 모든 태스크 스냅숏의 「인수 조건」 `게이트 명령:` 을 `references/gate.md`(f) 의 방법대로 돌린다. main 이 그대로여도 돌린다(앞 태스크의 게이트는 그 시점에만 통과했다). 의존성 매니페스트·lockfile 이 바뀌었으면 의존성을 먼저 동기화한다. 실패하면 멈춤 보고 「합친 결과 게이트 실패」.
4. `git -C <worktree> fetch origin main`. `origin/main` 이 3 의 base 와 다르면 1 로 돌아간다. 같으면 아래 명령을 3 의 HEAD SHA 로 부른다. 실패하면 멈춤 보고 「gh 머지 실패: <첫 줄>」. squash·rebase merge, `--auto`, `--delete-branch` 는 쓰지 않는다. `--delete-branch` 는 gh 2.96 에서 이슈 워크트리 안의 main checkout 이 실패해 원격 브랜치도 지우지 못한다.

   ```bash
   gh pr merge <PR> --merge --match-head-commit <게이트를 돌린 HEAD SHA> --subject "Merge branch '<브랜치>'" --body "<PR URL>"
   ```

## 3. 머지 뒤 확인

1. 머지 커밋(`gh pr view <PR> --json mergeCommit`)의 첫 부모를 fetch 뒤 `git rev-parse <머지 커밋>^1` 로 본다. 2-3 의 base 와 다르면 머지 커밋을 detached 로 체크아웃해 모든 태스크의 게이트를 다시 돈다. 실패하면 **main 깨짐** 멈춤 보고: 이미 닫힌 이 이슈에 코멘트로 단다. 이슈를 다시 열지 않는다. revert 하지 않는다. 재개 줄은 「main 을 고친 뒤 <다음 열린 이슈 URL> 로 시작 명령」이다. 원격·로컬 브랜치와 워크트리를 남긴다.
2. 원격 브랜치 삭제: 내용을 내보내지 않는 푸시라 유출 검사가 없다.

   ```bash
   git -C <worktree> push origin --delete <브랜치>
   ```

3. 구현 이슈와 하위 이슈마다 `gh issue view <URL> --json state` 로 상태를 본다. 열려 있으면 `publish comment` 로 「<PR URL> 로 머지됨」을 단 뒤 `gh issue close <URL>` 로 닫는다.

## 4. 다음 이슈

기동 줄 필드에서 자기 이슈 뒤에 있는 이슈 중 열린 첫 이슈다(`gh issue view --json state`).

- **없으면 마지막이다 → 완료 보고**:
  ```bash
  python "$RELAY/scripts/relay_cli.py" batch-report --issue <자기 이슈 URL> --list "<필드 값>" --out <파일>
  python "$RELAY/scripts/relay_cli.py" publish comment --worktree <worktree> --issue <자기 이슈 URL> --body-file <파일>
  ```
  `stop` 이거나 실패하면 6 을 하지 않는다(워크트리를 남긴다). 세션 출력에 이유와 올리려던 본문을 적고 끝난다(유출 검사에 걸렸으면 걸린 값은 뺀다). 다시 시작할 것이 없으므로 멈춤 보고가 아니다.
- **있으면 handoff**: `python "$RELAY/scripts/relay_cli.py" doctor` 와 `python "$RELAY/scripts/relay_cli.py" handoff-check --issue <다음 이슈 URL>` 를 끝까지 돌린다. 둘 다 통과하면 `$RELAY/skills/handoff/references/launch.md` 절차로 띄운다(일괄 진행 기동 줄, 필드는 받은 그대로, 슬러그는 다음 이슈 제목에서). 검사 `FAIL` 이나 기동 실패면 **다음 이슈**에 멈춤 보고를 단다(`references/stop.md` 일괄 진행 형식). 6 을 하지 않고(워크트리를 남긴다) 끝난다. 다음 이슈는 워크트리가 없어 Orca 미읽음이 뜨지 않기 때문이다.
- 중간 이슈의 머지는 따로 알리지 않는다(코멘트 없음).

## 5. 알림 원칙

**사람에게 알릴 수단이 없으면 워크트리를 남긴다.**

## 6. 마지막 행동 — 자기 이슈 워크트리 삭제

Orca 가이드의 워크트리 삭제 동사(`worktree rm`)에 `--worktree current --delete-branch` 를 준다. `--force` 는 주지 않는다.

이 뒤에는 아무것도 하지 않는다(Orca 가 이 세션을 먼저 끄므로 결과를 받지 못한다, ADR 0011·#68 실측). Orca 가 거부하면(커밋하지 않은 파일) 세션은 살아 있다. 세션 출력에 거부 이유를 적고 끝난다. GitHub 코멘트는 달지 않고, 일괄 진행도 멈추지 않는다(다음 이슈는 이미 돌고 있다). Orca 가 머지를 증명하지 못한 로컬 브랜치는 남을 수 있다.
