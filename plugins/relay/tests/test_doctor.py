# -*- coding: utf-8 -*-
import json
import unittest

from helpers import PLUGIN_ROOT
from relaylib import doctor, orca, smoke

GOOD_CODEX = 'model = "gpt-6-luna"\ncheck_for_update_on_startup = false\n[tui]\nterminal_title = ["app-name"]\n'
ROOT = r"C:\Users\x\orca\workspaces"
VERIFIED = {"codex": ["0.159.3"], "antigravity": ["1.2.16"], "orca": ["1.4.216"]}


AGY = "gemini-3.8-flash-high\tA\ngemini-3.8-flash-low\tA\n"


def facts(**kw):
    f = {
        "codex_config": GOOD_CODEX,
        "models_cfg": {"reviewer": {"model": "gpt-6-luna"}},
        "models_files": ["u.json"],
        "agy_models": AGY,
        "versions": {"codex": "0.159.3", "antigravity": "1.2.16", "orca": "1.4.216"},
        "verified": VERIFIED,
        "agy_settings": {"trustedWorkspaces": [ROOT + r"\p\T-1"], "permissions": {"allow": ["command(git diff)"]}},
        "trust_root": ROOT,
        "exists": lambda p: True,
    }
    f.update(kw)
    return f


def by_name(checks):
    return {c["name"]: c for c in checks}


class Doctor(unittest.TestCase):
    def test_all_green(self):
        checks = doctor.evaluate(facts())
        self.assertTrue(all(c["status"] == "ok" for c in checks), checks)
        self.assertEqual(doctor.exit_code(checks), 0)

    def test_reviewer_model_is_reported(self):
        self.assertIn("gpt-6-luna / high (relay 설정 파일)", by_name(doctor.evaluate(facts()))["codex"]["detail"])

    def test_no_models_file_is_fine_for_implementer_but_reviewer_needs_a_model(self):
        checks = by_name(doctor.evaluate(facts(models_cfg={}, models_files=[])))
        self.assertEqual(checks["models"]["status"], "ok")
        self.assertEqual(checks["codex"]["status"], "fail")
        self.assertIn("models.json", checks["codex"]["fix"])

    def test_codex_config_model_does_not_count_as_reviewer_model(self):
        c = by_name(doctor.evaluate(facts(models_cfg={})))["codex"]
        self.assertEqual(c["status"], "fail")
        self.assertNotIn("gpt-6-luna", c["detail"])

    def test_models_file_overrides_reviewer_in_report(self):
        cfg = {"reviewer": {"model": "gpt-9", "effort": "xhigh"}}
        checks = by_name(doctor.evaluate(facts(models_cfg=cfg, models_files=["u.json"], agy_models=AGY)))
        self.assertIn("gpt-9 / xhigh (relay 설정 파일)", checks["codex"]["detail"])
        self.assertEqual(checks["models"]["status"], "ok")

    def test_reviewer_effort_unsupported_by_model_fails(self):
        cache = '{"models":[{"slug":"gpt-6-luna","supported_reasoning_levels":[{"effort":"low"},{"effort":"high"}]}]}'
        cfg = {"reviewer": {"model": "gpt-6-luna", "effort": "ultra"}}
        c = by_name(doctor.evaluate(facts(models_cfg=cfg, codex_models=cache)))["reviewer-model"]
        self.assertEqual(c["status"], "fail")
        self.assertIn("low, high", c["detail"])

    def test_reviewer_model_in_codex_list_is_ok(self):
        cache = '{"models":[{"slug":"gpt-6-luna","supported_reasoning_levels":[{"effort":"high"}]}]}'
        self.assertEqual(by_name(doctor.evaluate(facts(codex_models=cache)))["reviewer-model"]["status"], "ok")

    def test_broken_models_file_fails(self):
        c = by_name(doctor.evaluate(facts(models_error="u.json: JSON 오류")))["models"]
        self.assertEqual(c["status"], "fail")

    def test_conflicting_agy_model_effort_fails(self):
        cfg = {"implementer": {"model": "gemini-3.8-flash-low", "effort": "high"}}
        checks = doctor.evaluate(facts(models_cfg=cfg, models_files=["u.json"], agy_models=AGY))
        self.assertEqual(by_name(checks)["models"]["status"], "fail")
        self.assertEqual(doctor.exit_code(checks), 1)

    def test_agy_listing_missing_warns(self):
        cfg = {"implementer": {"model": "gemini-3.8-flash"}}
        c = by_name(doctor.evaluate(facts(models_cfg=cfg, models_files=["u.json"], agy_models=None)))["models"]
        self.assertEqual(c["status"], "warn")

    def test_missing_codex_prereq_fails(self):
        c = by_name(doctor.evaluate(facts(codex_config='model = "m"\n')))["codex"]
        self.assertEqual(c["status"], "fail")
        self.assertIn("check_for_update_on_startup", c["fix"])
        self.assertEqual(doctor.exit_code(doctor.evaluate(facts(codex_config='model = "m"\n'))), 1)

    def test_missing_codex_config_fails(self):
        self.assertEqual(by_name(doctor.evaluate(facts(codex_config=None)))["codex"]["status"], "fail")

    def test_unverified_version_warns_but_does_not_fail(self):
        checks = doctor.evaluate(facts(versions={"codex": "0.160.0", "antigravity": "1.2.16", "orca": "1.4.216"}))
        c = by_name(checks)["version:codex"]
        self.assertEqual(c["status"], "warn")
        self.assertIn("smoke", c["fix"])
        self.assertEqual(doctor.exit_code(checks), 0)

    def test_missing_cli_fails(self):
        c = by_name(doctor.evaluate(facts(versions={"codex": None, "antigravity": "1.2.16", "orca": "1.4.216"})))["version:codex"]
        self.assertEqual(c["status"], "fail")

    def test_dead_trust_entries_warn_and_are_listed(self):
        f = facts(exists=lambda p: False)
        c = by_name(doctor.evaluate(f))["trust"]
        self.assertEqual(c["status"], "warn")
        self.assertIn("T-1", c["detail"])
        # evaluate 는 설정을 바꾸지 않는다
        self.assertEqual(len(f["agy_settings"]["trustedWorkspaces"]), 1)

    def test_agy_git_commit_permission_warns(self):
        s = {"trustedWorkspaces": [], "permissions": {"allow": ["command(git commit)", "command(powershell)"]}}
        c = by_name(doctor.evaluate(facts(agy_settings=s)))["agy-permissions"]
        self.assertEqual(c["status"], "warn")
        self.assertIn("git commit", c["detail"])
        self.assertIn("powershell", c["detail"])

    def test_stale_session_plugin_fails(self):
        # 실측(T-007): 1.2.3 이 설치된 뒤에도 세션은 1.2.0 절차(단독 agy)로 진행했다
        checks = doctor.evaluate(facts(plugin_version="1.2.0", installed_versions=["1.2.3", "1.2.10"]))
        c = by_name(checks)["plugin"]
        self.assertEqual(c["status"], "fail")
        self.assertIn("1.2.10", c["detail"])
        self.assertIn("reload-plugins", c["fix"])
        self.assertEqual(doctor.exit_code(checks), 1)

    def test_current_or_newer_session_plugin_is_ok(self):
        for installed in (["1.2.3"], ["1.2.2"], []):
            c = by_name(doctor.evaluate(facts(plugin_version="1.2.3", installed_versions=installed)))["plugin"]
            self.assertEqual(c["status"], "ok", installed)

    def test_verified_file_has_known_agents(self):
        v = json.loads(doctor.VERIFIED_PATH.read_text(encoding="utf-8"))
        self.assertTrue(str(doctor.VERIFIED_PATH).startswith(str(PLUGIN_ROOT)))
        self.assertEqual(set(v) - {"$comment"}, {"codex", "antigravity", "orca"})


class Warmup(unittest.TestCase):
    def test_ready_verified(self):
        d = doctor.warmup_decide(before="1.2.16", update_rc=0, after="1.2.16", verified=VERIFIED)
        self.assertEqual(d, {"action": "ready", "version": "1.2.16", "updated": False, "unverified": False})

    def test_updated_to_unverified(self):
        d = doctor.warmup_decide(before="1.2.16", update_rc=0, after="1.2.17", verified=VERIFIED)
        self.assertEqual((d["action"], d["updated"], d["unverified"]), ("ready", True, True))

    def test_update_failure_calls_human(self):
        d = doctor.warmup_decide(before="1.2.16", update_rc=1, after="1.2.16", verified=VERIFIED)
        self.assertEqual((d["action"], d["reason"]), ("human", "update_failed"))

    def test_missing_binary_calls_human(self):
        d = doctor.warmup_decide(before=None, update_rc=0, after=None, verified=VERIFIED)
        self.assertEqual((d["action"], d["reason"]), ("human", "agy_not_found"))


class ParseVersion(unittest.TestCase):
    def test_variants(self):
        self.assertEqual(doctor.parse_version("codex-cli 0.159.3"), "0.159.3")
        self.assertEqual(doctor.parse_version("1.2.16\n"), "1.2.16")
        self.assertEqual(doctor.parse_version("[1001/200555:ERROR:crashpad] x\n1.4.216"), "1.4.216")
        self.assertIsNone(doctor.parse_version("command not found"))


class FakeOrca(object):
    """smoke 러너용 가짜 — 호출된 명령을 기록하고 정해진 응답을 준다."""

    def __init__(self, idle_ok=True, screen="", log=""):
        self.calls, self.idle_ok, self.screen, self.log = [], idle_ok, screen, log

    def run(self, argv):
        self.calls.append(argv)
        sub = argv[1:3]
        if sub == ["terminal", "create"]:
            return 0, json.dumps({"ok": True, "result": {"terminal": {"handle": "term_x"}}})
        if sub == ["terminal", "wait"]:
            return (0, '{"ok": true}') if self.idle_ok else (1, '{"ok": false, "error": {"code": "timeout"}}')
        if sub == ["terminal", "read"]:
            return 0, json.dumps({"ok": True, "result": {"terminal": {"tail": self.screen.splitlines()}}})
        return 0, '{"ok": true}'


class Smoke(unittest.TestCase):
    def test_agy_pass(self):
        o = FakeOrca(log="HandleUserInput called with text: %s ..." % smoke.PING)
        r = smoke.run_agent("antigravity", "C:/w", o.run, read_log=lambda: o.log, sleep=lambda s: None, version="1.2.16")
        self.assertTrue(r["passed"], r)
        self.assertEqual(o.calls[-1][1:3], ["terminal", "close"])

    def test_tui_idle_timeout_fails_and_still_closes(self):
        o = FakeOrca(idle_ok=False)
        r = smoke.run_agent("codex", "C:/w", o.run, read_log=lambda: "", sleep=lambda s: None, version="0.159.3")
        self.assertFalse(r["passed"])
        self.assertEqual(r["failed_at"], "tui_idle")
        self.assertEqual(r["attempts"], ["tui_idle"] * smoke.ATTEMPTS)
        self.assertEqual(o.calls[-1][1:3], ["terminal", "close"])
        creates = [c for c in o.calls if c[1:3] == ["terminal", "create"]]
        closes = [c for c in o.calls if c[1:3] == ["terminal", "close"]]
        self.assertEqual(len(creates), len(closes), "시도마다 만든 터미널을 닫는다")

    def test_flaky_readiness_passes_on_retry(self):
        o = FakeOrca(screen="› %s" % smoke.PING)
        results = iter([(1, '{"ok": false}'), (0, '{"ok": true}')])
        orig = o.run

        def run(argv):
            if argv[1:3] == ["terminal", "wait"]:
                o.calls.append(argv)
                return next(results)
            return orig(argv)

        r = smoke.run_agent("codex", "C:/w", run, read_log=lambda: "", sleep=lambda s: None, version="0.159.3")
        self.assertTrue(r["passed"])
        self.assertEqual(r["attempts"], ["tui_idle", "passed"])

    def test_codex_delivery_via_screen(self):
        o = FakeOrca(screen="› %s\n• OK" % smoke.PING)
        r = smoke.run_agent("codex", "C:/w", o.run, read_log=lambda: "", sleep=lambda s: None, version="0.159.3")
        self.assertTrue(r["passed"], r)

    def test_agy_not_delivered(self):
        o = FakeOrca(log="nothing")
        r = smoke.run_agent("antigravity", "C:/w", o.run, read_log=lambda: o.log, sleep=lambda s: None, version="1.2.16")
        self.assertEqual((r["passed"], r["failed_at"]), (False, "delivery"))

    def test_agy_is_not_launched_as_a_bare_command(self):
        # 맨 앞 토큰이 agy 면 Orca 가 에이전트 시작 경로로 띄워 입력창이 스트림에 남지 않는다
        o = FakeOrca(log=smoke.PING + " HandleUserInput called with text:")
        smoke.run_agent("antigravity", "C:/w", o.run, read_log=lambda: o.log, sleep=lambda s: None, version="1")
        create = next(c for c in o.calls if c[1:3] == ["terminal", "create"])
        command = create[create.index("--command") + 1]
        self.assertEqual(command, orca.AGY_LAUNCH_COMMAND)
        self.assertNotEqual(command.split()[0], "agy")

    def test_commands_start_with_orca(self):
        o = FakeOrca(log=smoke.PING + " HandleUserInput called with text:")
        smoke.run_agent("antigravity", "C:/w", o.run, read_log=lambda: o.log, sleep=lambda s: None, version="1")
        self.assertTrue(all(c[0] == "orca" for c in o.calls))


if __name__ == "__main__":
    unittest.main()
