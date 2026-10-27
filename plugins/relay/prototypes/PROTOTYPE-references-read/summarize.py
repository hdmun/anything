# PROTOTYPE: out/<변형>.json 들을 변형 × 케이스 표로 요약한다
import json, pathlib, sys
here = pathlib.Path(__file__).parent / 'out'
print('| 변형 | 케이스 | gate.md Read | 내용 PASS | 스킬 발동 | 비용$ |\n|---|---|---|---|---|---|')
tot = {}
for f in sorted(here.glob('v*.json')):
    d = json.loads(f.read_text(encoding='utf-8')); v = f.stem
    for c in d['cases']:
        runs = c['arms']['with']; n = len(runs)
        g = lambda name: sum(1 for r in runs for x in r['graders'] if x['name'] == name and x['passed'])
        cost = sum(r.get('costUsd') or 0 for r in runs)
        print(f"| {v} | {c['name']} | {g('read-gate')}/{n} | {g('criteria')}/{n} | {g('skill-fired')}/{n} | {cost:.2f} |")
        t = tot.setdefault(v, [0, 0, 0]); t[0] += g('read-gate'); t[1] += g('criteria'); t[2] += n
    print(f"| **{v}** | 합계 | {tot[v][0]}/{tot[v][2]} | {tot[v][1]}/{tot[v][2]} | | {d['costUsd']:.2f} |")
