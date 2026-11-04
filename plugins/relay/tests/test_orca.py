# -*- coding: utf-8 -*-
"""워커 기동 인자 결정기."""
import unittest

import helpers  # noqa: F401
from relaylib import models, orca


class ReviewerModel(unittest.TestCase):
    GOOD = 'model = "gpt-6-luna"\ncheck_for_update_on_startup = false\n\n[tui]\nterminal_title = ["app-name", "project-name"]\n'

    def test_model_and_effort_come_from_relay_models(self):
        d = orca.reviewer_model(self.GOOD, {"reviewer": {"model": "gpt-9", "effort": "xhigh"}})
        self.assertEqual(d, {"action": "launch", "agent": "codex", "model": "gpt-9", "effort": "xhigh"})

    def test_effort_defaults_to_high(self):
        d = orca.reviewer_model(self.GOOD, {"reviewer": {"model": "gpt-9"}})
        self.assertEqual(d["effort"], "high")

    def test_codex_config_model_is_ignored(self):
        # config.toml 의 model(평소 용도)을 리뷰어 모델로 쓰지 않는다 — 설정 파일에 model 이 없으면 사람 호출
        for cfg in (None, {}, {"reviewer": {"effort": "medium"}}):
            d = orca.reviewer_model(self.GOOD, cfg)
            self.assertEqual((d["action"], d["reason"]), ("human", "reviewer_model_unset"), cfg)

    def test_same_model_regardless_of_codex_config_model(self):
        cfg = {"reviewer": {"model": "gpt-9"}}
        a = orca.reviewer_model(self.GOOD, cfg)
        b = orca.reviewer_model(self.GOOD.replace('model = "gpt-6-luna"\n', 'model = "other"\n'), cfg)
        c = orca.reviewer_model(self.GOOD.replace('model = "gpt-6-luna"\n', ""), cfg)
        self.assertTrue(a == b == c)

    def test_prereqs_still_required_with_relay_models(self):
        d = orca.reviewer_model('model = "m"\n', {"reviewer": {"model": "gpt-9"}})
        self.assertEqual(d["reason"], "codex_prereq_missing")

    def test_missing_prereqs(self):
        d = orca.reviewer_model('model = "m"\n')
        self.assertEqual(d["action"], "human")
        self.assertEqual(sorted(d["missing"]), ["check_for_update_on_startup = false", "tui.terminal_title 에 app-name"])

    def test_update_check_true_is_missing(self):
        d = orca.reviewer_model(self.GOOD.replace("= false", "= true"))
        self.assertIn("check_for_update_on_startup = false", d["missing"])


AGY_IDS = ("gemini-3.8-flash-high", "gemini-3.8-flash-low", "gemini-3.1-pro-high", "gemini-3.1-pro-low")
AGY_MODELS = "\n".join(["Fetching available models..."] + [i + "\tlabel" for i in AGY_IDS]) + "\n"

class ImplementerModel(unittest.TestCase):
    """구현 워커(agy)는 worker-start --agent antigravity 로 띄운다 — 결정기는 그 인자만 돌려준다 (ADR 0003)."""

    def test_default_launches_agy_without_model_flags(self):
        d = orca.implementer_model()
        self.assertEqual(d, {"action": "launch", "agent": "antigravity", "model": None, "effort": None, "source": "agy_default"})

    def test_configured_model_and_effort(self):
        d = orca.implementer_model({"implementer": {"model": "gemini-3.8-flash", "effort": "low"}})
        self.assertEqual((d["action"], d["model"], d["effort"], d["source"]), ("launch", "gemini-3.8-flash", "low", "relay_models"))

    def test_effort_without_model_is_refused_before_launch(self):
        # Orca: worker-start 의 --effort 는 --model 이 있어야 한다. 조용히 버리지 않는다
        d = orca.implementer_model({"implementer": {"effort": "high"}})
        self.assertEqual((d["action"], d["reason"]), ("human", "effort_needs_model"))

    def test_valid_against_agy_models(self):
        d = orca.implementer_model({"implementer": {"model": "gemini-3.8-flash", "effort": "low"}}, AGY_MODELS)
        self.assertEqual(d["action"], "launch")

    def test_level_suffixed_model_with_effort_is_refused_before_launch(self):
        d = orca.implementer_model({"implementer": {"model": "gemini-3.8-flash-low", "effort": "high"}}, AGY_MODELS)
        self.assertEqual((d["action"], d["reason"]), ("human", "agy_model_invalid"))

    def test_unknown_model_and_unsupported_effort(self):
        self.assertEqual(orca.implementer_model({"implementer": {"model": "nope"}}, AGY_MODELS)["reason"], "agy_model_invalid")
        d = orca.implementer_model({"implementer": {"model": "gemini-3.1-pro", "effort": "xhigh"}}, AGY_MODELS)
        self.assertIn("low, high", d["detail"])


class DesignerModel(unittest.TestCase):
    """설계 세션은 사람이 연 세션이라 플러그인이 모델을 바꿀 수 없다 — 따를 명령만 안내한다."""

    def test_defaults(self):
        d = orca.session_model("designer")
        self.assertEqual((d["action"], d["model"], d["effort"], d["command"]), ("session", None, "high", "claude --effort high"))

    def test_configured(self):
        d = orca.session_model("designer", {"designer": {"model": "opus", "effort": "max"}})
        self.assertEqual(d["command"], "claude --model opus --effort max")


class CoordinatorModel(unittest.TestCase):
    """진행자는 설계 세션이 worker-start --agent claude 로 띄우는 워커다 (ADR 0004) — 기동 인자를 돌려준다."""

    def test_default_launches_opus_low_worker(self):
        d = orca.coordinator_model()
        self.assertEqual((d["action"], d["agent"], d["model"], d["effort"], d["source"]),
                         ("launch", "claude", "opus", "low", "default"))
        self.assertNotIn("command", d)      # 사람에게 안내할 claude 명령줄은 이제 없다

    def test_configured_values_win(self):
        d = orca.coordinator_model({"coordinator": {"model": "opus", "effort": "high"}})
        self.assertEqual((d["model"], d["effort"], d["source"]), ("opus", "high", "relay_models"))



if __name__ == "__main__":
    unittest.main()
