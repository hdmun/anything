# PROTOTYPE: SKILL.md 의 (f) 섹션을 references/gate.md 로 빼고 변형별 지시를 남긴다
import io, sys, pathlib
v, src, dst = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
s = io.open(src, encoding='utf-8').read()
a = s.index('## (f) 게이트 독립 재검증'); b = s.index('## (g) 리뷰 결과 처리')
head, body, tail = s[:a], s[a:b], s[b:]
stub = {
 'v1-pointer': '## (f) 게이트 독립 재검증\n\n상세: `references/gate.md`\n\n',
 'v2-imperative': '## (f) 게이트 독립 재검증\n\n**이 단계에 들어서면 먼저 `references/gate.md`를 Read 한다.** 읽기 전에는 게이트를 돌리거나 통과·실패를 판정하지 않는다.\n\n',
}
stub['v3-entry-table'] = stub['v2-imperative']
if v == 'v0-monolith':
    out = s
else:
    (dst / 'references' / 'gate.md').write_text('# (f) 게이트 독립 재검증 — 상세\n\n' + body.split('\n', 1)[1], encoding='utf-8')
    out = head + stub[v] + tail
    if v == 'v3-entry-table':
        table = ('## 단계 진입표 — 단계에 들어서면 먼저 읽는다\n\n| 단계 | 먼저 Read 할 파일 |\n|---|---|\n'
                 '| (f) 게이트 독립 재검증 (`worker_done` 수신 직후) | `references/gate.md` |\n\n')
        i = out.index('## 역할과 모델'); out = out[:i] + table + out[i:]
(dst / 'SKILL.md').write_text(out, encoding='utf-8')
print(v, len(out.encode('utf-8')), 'bytes')
