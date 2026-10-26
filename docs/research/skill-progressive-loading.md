# Claude Code 스킬의 점진적 로딩 동작 조사

- 이슈: hdmun/anything#2 (상위 #1, 후속 #4, #6)
- 조사일: 2026-10-26
- 대상: `plugins/relay/skills/relay/SKILL.md` (688줄, 63,530바이트) 개편 판단 근거

## 출처

| 약칭 | URL |
| --- | --- |
| [CC-Skills] | https://code.claude.com/docs/en/skills |
| [Overview] | https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview (구 docs.claude.com, 302 리다이렉트) |
| [BestPractices] | https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices |
| [Spec] | https://agentskills.io/specification |
| [Blog] | https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills |

아래에서 **사실**은 위 출처의 문장을 옮긴 것이고, **추론**은 그 사실을 relay 스킬에 적용한 판단이다.

---

## Q1. 부속 파일은 언제·어떻게 컨텍스트에 들어오는가

### 사실

- **시작 시점에는 name + description만 들어간다.** "In a regular session, skill descriptions are loaded into context so Claude knows what's available, but full skill content only loads when invoked." [CC-Skills] / "At startup, only the metadata (name and description) from all Skills is pre-loaded." [BestPractices]
- **호출 시점에 SKILL.md 본문 전체가 들어간다.** "When you or Claude invoke a skill, the rendered `SKILL.md` content enters the conversation as a single message and stays there across later turns." [CC-Skills] / "the agent will load this entire file once it's decided to activate a skill." [Spec]
- **부속 파일은 자동으로 들어가지 않는다. 모델이 직접 읽을 때만 들어간다.**
  - "Claude reads `SKILL.md` only when the Skill becomes relevant, and reads additional files only as needed." [BestPractices]
  - "Reference files load into context when read. Scripts run through bash, and only their output enters context." (Level 3 표) [Overview]
  - "If those instructions reference other files (such as `FORMS.md` or a database schema), Claude reads those files too using additional bash commands." [Overview]
  - Claude Code 문서의 디렉터리 예시: `reference.md (detailed API docs - loaded when needed)`, `scripts/helper.py (utility script - executed, not loaded)` [CC-Skills]
- **부속 파일을 읽게 만드는 장치는 SKILL.md 안의 참조뿐이다.** "Reference supporting files from `SKILL.md` so Claude knows what each file contains and when to load it." [CC-Skills]
- **3단계 비용 표** [Overview], [Spec]:

  | 단계 | 시점 | 비용 |
  | --- | --- | --- |
  | 1 메타데이터 | 항상(시작 시) | 스킬당 약 100토큰 |
  | 2 SKILL.md 본문 | 발동 시 | 5k 토큰 미만 권장 |
  | 3 리소스 | 필요할 때 | 읽기 전까지 0 |

- **한 번 들어간 본문은 다시 읽지 않는다.** "Claude Code does not re-read the skill file on later turns, so write guidance that should apply throughout a task as standing instructions rather than one-time steps." [CC-Skills]
- **컴팩션 후에는 앞부분만 남는다.** "Claude Code re-attaches the most recent invocation of each skill after the summary, keeping the first 5,000 tokens of each. Re-attached skills share a combined budget of 25,000 tokens." [CC-Skills] 또 "put the most important instructions near the top of `SKILL.md`." [CC-Skills]
- **예외: 서브에이전트에 preload된 스킬**은 시작 시 본문 전체가 주입된다. [CC-Skills]
- `disable-model-invocation: true`이면 description도 컨텍스트에 들어가지 않고, 사용자가 `/name`으로 부를 때만 본문이 들어간다. [CC-Skills]

### 관찰(이 세션)

- Skill 도구로 스킬을 부르면 본문 앞에 `Base directory for this skill: <경로>` 한 줄이 붙어 들어온다. 그래서 모델은 상대 경로 `references/...`를 절대 경로로 풀 수 있다. 공식 문서는 스크립트 경로에 `${CLAUDE_SKILL_DIR}` 치환을 쓰라고 안내한다. [CC-Skills]

### 추론

- relay의 `references/spec-template.md`, `review-schema.json`은 SKILL.md 92행·488행에서 언급될 때 모델이 Read해야만 컨텍스트에 들어간다. 언급만 하고 "읽어라"는 지시가 약하면 건너뛸 수 있다.
- 지금 relay 본문 63KB는 호출 즉시 통째로 들어가서 세션 끝까지 남는다. 한국어 비중을 생각하면 수만 토큰으로 추정되며, 권장치(5k 토큰 미만)보다 몇 배 크다. 컴팩션 후에는 앞의 5,000토큰만 다시 붙으므로 뒷부분 규칙(리뷰 분기, PR 단계 등)은 잃을 수 있다.

---

## Q2. 한 플러그인에 스킬이 여럿일 때 발동은 어떻게 되고, 서로 경쟁하는가

### 사실

- **발동 판단 근거는 description뿐이다.** "The `description` is what Claude matches your request against when determining whether to trigger the Skill" [Overview] / "Claude uses it to choose the right Skill from potentially 100+ available Skills." [BestPractices] / "If Claude thinks the skill is relevant to the current task, it will load the skill" [Blog]
- 결정적인 매칭 알고리즘은 문서화돼 있지 않다. 시스템 프롬프트의 목록을 보고 모델이 판단하는 방식이다. [Blog], [Overview]
- **플러그인 스킬에는 네임스페이스가 붙는다.** `/plugin-name:skill-name` 형식이라 다른 위치의 같은 이름 스킬과 충돌하지 않는다("Both load"). [CC-Skills]
- **스킬 수는 매 턴 비용이 된다.** "Every skill in the skill listing adds to your context on every turn, whether or not Claude ever uses it." [CC-Skills]
- **목록 예산이 있다.** 목록 전체 예산은 모델 컨텍스트 창의 1%이고, 넘치면 "drops descriptions starting with the skills you invoke least". 항목 하나의 description + `when_to_use` 합계는 목록에서 1,536자에서 잘린다(`skillListingMaxDescChars`로 조정 가능). 스펙상 description 상한은 1,024자다. [CC-Skills], [Spec]
- 너무 자주 발동하면 "Make the description more specific" 또는 `disable-model-invocation: true`로 대응하라고 안내한다. [CC-Skills]
- `paths` frontmatter로 특정 파일을 다룰 때만 활성화되도록 범위를 좁힐 수 있다. [CC-Skills]
- 플러그인이라면 `claude plugin eval`의 `tool_used: Skill` 그레이더로 발동률을 측정할 수 있다. [CC-Skills]

### 쪼개기 vs references에 대한 공식 가이드

- 스킬을 여러 개로 나누는 기준은 공식 문서에 명시돼 있지 않다.
- 반면 **한 스킬 안에서 파일을 나누는 가이드는 분명하다.**
  - "When the `SKILL.md` file becomes unwieldy, split its content into separate files and reference them." [Blog]
  - "If certain contexts are mutually exclusive or rarely used together, keeping the paths separate will reduce the token usage." [Blog]
  - 도메인별 구성(Pattern 2), 조건부 상세(Pattern 3) 예시가 있다. [BestPractices]
  - "If workflows become large or complicated with many steps, consider pushing them into separate files and tell Claude to read the appropriate file based on the current task." [BestPractices]

### 추론

- 스킬을 여러 개로 나누면 description이 늘어 매 턴 비용이 커지고, 비슷한 description끼리 모델이 하나를 골라야 하는 상황이 생긴다. 사용자 입장에서 **발동 조건이 다른** 단위(예: `relay:init`처럼 따로 부르는 작업)일 때만 별도 스킬로 두고, 같은 요청 흐름 안의 단계(spec 작성, dispatch, 리뷰 분기, PR)는 한 스킬 + references로 나누는 편이 공식 가이드와 맞는다.
- 단계별로 서로 배타적으로 쓰이는 내용(예: 리뷰 심각도 분기 상세는 리뷰 단계에서만 필요)은 references 파일로 빼기 좋은 후보다.

---

## Q3. SKILL.md 권장 크기·구조

### 사실

- **크기**
  - "Keep `SKILL.md` under 500 lines. Move detailed reference material to separate files." [CC-Skills], [Spec]
  - "Keep the `SKILL.md` body under 500 lines for optimal performance. Split content into separate files when approaching this limit." [BestPractices]
  - 본문은 5,000토큰 미만 권장. [Spec], [Overview]
  - "Once a skill loads, its content stays in context across turns, so every line is a recurring token cost." [CC-Skills]
- **간결함**: "The context window is a public good." / "Only add context Claude doesn't already have." [BestPractices]
- **참조 깊이**: "Keep references one level deep from `SKILL.md`." 중첩 참조 시 Claude가 `head -100` 같은 부분 읽기만 하고 넘어갈 수 있다. [BestPractices], [Spec]
- **긴 참조 파일**: 100줄 넘는 참조 파일은 맨 위에 목차를 둔다. 부분 읽기를 해도 전체 범위를 볼 수 있게 하기 위해서다. [BestPractices]
- **참조 파일을 확실히 읽게 하는 방법**
  - SKILL.md에서 각 파일이 무엇을 담고 **언제** 읽어야 하는지 적는다. [CC-Skills]
  - 실행할지 읽을지 의도를 분명히 한다: "Run `analyze_form.py` ..." vs "See `analyze_form.py` for ...". [BestPractices]
  - 파일 이름을 내용이 드러나게 짓는다(`form_validation_rules.md`, `doc2.md`는 피함). [BestPractices]
  - Claude가 참조를 따라가지 않으면 "Your links might need to be more explicit or prominent." 반대로 같은 파일을 반복해서 읽으면 그 내용을 SKILL.md로 올리는 것을 검토한다. [BestPractices]
  - 중요 규칙은 "MUST filter"처럼 강한 표현을 쓰거나 더 눈에 띄게 재배치하는 개선 예시가 있다. [BestPractices]
  - 반드시 매번 지켜야 할 규칙은 스킬 문장이 아니라 hook으로 옮기라고 권한다(skill frontmatter `hooks` 가능). [CC-Skills]
- **구조 패턴**: 복잡한 작업은 체크리스트 워크플로, 검증 → 수정 → 반복 피드백 루프, 조건부 워크플로(분기마다 다른 파일)로 구성한다. [BestPractices]
- **경로**: 슬래시(`/`)만 쓴다. [BestPractices]

### 추론 (relay 적용)

- relay SKILL.md는 688줄로 500줄 권장선을 넘고, 토큰은 권장치의 몇 배로 추정된다. 다음과 같이 정리하면 공식 가이드에 맞는다.
  1. SKILL.md에는 역할 구성, 단계 순서, 매 단계에 늘 지켜야 할 규칙, references 목차("X 단계에 들어가면 `references/x.md`를 Read한다")만 남긴다.
  2. 단계별 상세(리뷰 심각도 분기 표, PR 절차 등)는 `references/` 아래 한 단계 깊이 파일로 옮기고, 100줄이 넘으면 목차를 단다.
  3. 컴팩션 후에도 살아남아야 할 규칙은 SKILL.md 앞부분(5,000토큰 안)에 둔다.
  4. 반드시 지켜야 하는 게이트성 규칙은 hook으로 옮길 수 있는지 검토한다.
- 분리 후 references를 실제로 읽는지는 문서로 보장되지 않으므로 `claude plugin eval` 등으로 확인해야 한다(#4, #6 후속 작업 몫).
