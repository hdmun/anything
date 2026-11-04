# -*- coding: utf-8 -*-
"""재개 — 끝난 태스크를 트레일러 `Relay-Done: I-<n>` 로 알고 다음 태스크를 고른다 (ADR 0010).

트레일러는 리뷰 `pass` 리포트 커밋(또는 성공 처리 판정 기록 커밋)에 진행자가 붙인다.
트레일러가 빠진 성공 태스크는 다시 돈다 — 그래서 붙이는 쪽은 진행자 하나다.
"""
TRAILER = "Relay-Done"


def done_tasks(trailer_values):
    """git log 의 Relay-Done 값들 → 끝난 태스크 ID 집합."""
    return {v.strip() for v in trailer_values if v.strip()}


def decide(tasks, done):
    """tasks: DAG 순서의 태스크 ID. → start(다음 태스크) 또는 pr(모두 끝남)."""
    finished = [t for t in tasks if t in done]
    for t in tasks:
        if t not in done:
            return {"action": "start", "task": t, "done": finished}
    return {"action": "pr", "done": finished}
