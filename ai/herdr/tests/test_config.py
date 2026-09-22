"""Unit tests for `herdr_team.config`, and for the files it resolves.

`run.sh` is the end-to-end suite, and it is where the *behaviour* this file
describes is pinned: the frozen cases in it are the parity claim T-01 makes, and
they say that a `team.sh` reading this config still spawns what it spawned
before. What this file covers is the reader itself — the merge order, the trust
rules, the verbs, and the fixtures under `tests/fixtures/config` that AC2 names.

The subject is always the shipped `ai/herdr/team.toml`, loaded directly rather
than through `team.sh`. Two consequences worth stating: every case here passes
`env={}`, because the environment this suite runs in has `HERDR_TEAM_ROOT` and
`DOTFILES` set by whatever shell started it, and a test that read them would be
a test about the developer's machine; and `dotfiles` is passed explicitly for
the same reason, since `{dotfiles}` in a value has to expand to the checkout
these tests live in and not to wherever `DOTFILES` happens to point.

The fixtures are overlays, not whole files. Four are merged over the shipped
defaults as a trusted layer, which is what a user's own `team.local.toml` is;
two are merged as an untrusted project layer, which is what fills in the
`role.<r>.profiles` a repo is allowed to set and the `never` list it is not.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import Any

import pytest

from herdr_team import config

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "config"
DOTFILES = Path(__file__).resolve().parents[3]
TEAM = DOTFILES / "ai/herdr/team.toml"


@pytest.fixture(autouse=True)
def no_ambient_config(monkeypatch: pytest.MonkeyPatch) -> None:
    """Take the shell that started the suite out of the picture.

    The verbs read `os.environ`, and this suite is most often run from inside a
    herdr pane — where `HERDR_TEAM_ROOT`, the caps and `DOTFILES` are all
    exported by the Run that started it. A test that read those would be a test
    about the developer's machine, and a cap set to 2 in the ambient
    environment would silently outrank the value under test.
    """
    for name in list(os.environ):
        if name.startswith("HERDR_TEAM_") or name == "DOTFILES":
            monkeypatch.delenv(name, raising=False)


def shipped(**overrides: Any) -> config.Config:
    """The shipped configuration, with the ambient environment left out."""
    return config.load(env={}, dotfiles=DOTFILES, **overrides)


def overlaid(name: str, trusted: bool = True, **overrides: Any) -> config.Config:
    """A fixture merged over the shipped file, as the layer it stands for."""
    return config.load(
        layers=[config.Layer(TEAM, True), config.Layer(FIXTURES / name, trusted)],
        env={},
        dotfiles=DOTFILES,
        **overrides,
    )


def findings(name: str, trusted: bool = True, **overrides: Any) -> list[str]:
    return overlaid(name, trusted, **overrides).lint()


# --- the shipped configuration ---------------------------------------------


def test_the_shipped_config_lints_clean() -> None:
    assert shipped().lint() == []


def test_env_emits_every_knob_team_sh_reads() -> None:
    assert shipped().env_pairs() == [
        ("HERDR_TEAM_ROOT", str(DOTFILES / ".herdr")),
        ("HERDR_TEAM_EXEC_CAP", "2"),
        ("HERDR_TEAM_DETECT_TIMEOUT", "60"),
        ("HERDR_TEAM_CLEAR_CONFIRM_TIMEOUT", "15"),
        ("HERDR_TEAM_HANDOFF_MAX", "150"),
        ("HERDR_TEAM_PRO_FALLBACK_MAX", "70"),
        (
            "HERDR_TEAM_PRO_QUOTA_CACHE",
            str(Path.home() / ".claude/cache/pro-quota.json"),
        ),
        ("HERDR_TEAM_PRO_QUOTA_MAX_AGE", "900"),
    ]


def test_the_quota_cache_prefers_claude_config_dir() -> None:
    configured = config.load(env={"CLAUDE_CONFIG_DIR": "/tmp/cc"}, dotfiles=DOTFILES)
    assert dict(configured.env_pairs())["HERDR_TEAM_PRO_QUOTA_CACHE"] == (
        "/tmp/cc/cache/pro-quota.json"
    )


def test_the_quota_cache_falls_back_to_home() -> None:
    # With no environment at all the reference is `${CLAUDE_CONFIG_DIR:-${HOME}
    # /.claude}`, and `${HOME}` has to answer: expanding it to nothing would
    # point the cache at `/.claude/...`, which is not a path anything wrote.
    unset = config.load(env={}, dotfiles=DOTFILES)
    assert dict(unset.env_pairs())["HERDR_TEAM_PRO_QUOTA_CACHE"] == (
        "%s/.claude/cache/pro-quota.json" % Path.home()
    )


def test_the_checkout_is_derived_when_no_layer_names_it() -> None:
    # Every other case here passes `dotfiles` explicitly, so this is the one
    # that pins the fallback a shell with nothing exported depends on: the
    # reader counts five directories up from its own file to find the checkout.
    # Counted wrong it finds no layers at all, and every verb answers about an
    # empty config instead of failing — which is how a reader that is off by one
    # still exits 0.
    derived = config.load(env={})
    assert derived.get("paths.root") == str(DOTFILES / ".herdr")
    assert derived.lint() == []


def test_the_quota_cache_reads_home_from_the_environment() -> None:
    moved = config.load(env={"HOME": "/tmp/home"}, dotfiles=DOTFILES)
    assert dict(moved.env_pairs())["HERDR_TEAM_PRO_QUOTA_CACHE"] == (
        "/tmp/home/.claude/cache/pro-quota.json"
    )


def test_env_passes_an_override_through_untouched() -> None:
    # `70%` is not a number and `team.sh`'s own gate is what says so, in a
    # message a frozen case in run.sh matches. A reader that corrected the value
    # here would make that case pass for the wrong reason, so it does not look.
    config_with = config.load(
        env={"HERDR_TEAM_PRO_FALLBACK_MAX": "70%"}, dotfiles=DOTFILES
    )
    assert ("HERDR_TEAM_PRO_FALLBACK_MAX", "70%") in config_with.env_pairs()
    assert config_with.lint() == []


def test_env_lines_are_assignments() -> None:
    assert "HERDR_TEAM_ROOT=%s/.herdr" % DOTFILES in shipped().env_lines()
    assert "HERDR_TEAM_EXEC_CAP=2" in shipped().env_lines()


def test_env_quotes_a_value_that_would_otherwise_expand() -> None:
    config_with = config.load(
        env={"HERDR_TEAM_PRO_QUOTA_CACHE": "/tmp/a b/$notvar"}, dotfiles=DOTFILES
    )
    assert "HERDR_TEAM_PRO_QUOTA_CACHE='/tmp/a b/$notvar'" in config_with.env_lines()


def test_a_numeric_override_that_is_not_a_number_is_a_finding() -> None:
    found = config.load(env={"HERDR_TEAM_EXEC_CAP": "two"}, dotfiles=DOTFILES).lint()
    assert found == [
        "HERDR_TEAM_EXEC_CAP=two is not a whole number, and "
        "role.exec.max_per_run is a limit `team.sh` compares as a number"
    ]


def test_the_root_override_is_a_path_and_not_a_count() -> None:
    # `HERDR_TEAM_ROOT` is in the same table of names as the counts and is the
    # only one that is not one. Checking it as a number would make every run
    # of every verb a finding, which is how this case came to exist.
    config_with = config.load(
        env={"HERDR_TEAM_ROOT": "/tmp/elsewhere"}, dotfiles=DOTFILES
    )
    assert config_with.lint() == []
    assert ("HERDR_TEAM_ROOT", "/tmp/elsewhere") in config_with.env_pairs()


def test_an_override_reaches_the_value_a_spawn_reads() -> None:
    # The environment is the layer above every file, so `get` has to answer it:
    # a reader whose `env` emitted 9 while `get` printed 2 would be two answers
    # to one question, and `resolve` and `route` read the document.
    capped = config.load(env={"HERDR_TEAM_EXEC_CAP": "9"}, dotfiles=DOTFILES)
    assert capped.get("role.exec.max_per_run") == 9
    assert ("HERDR_TEAM_EXEC_CAP", "9") in capped.env_pairs()
    assert capped.source("role.exec.max_per_run") == "HERDR_TEAM_EXEC_CAP"


def test_an_override_that_is_not_a_number_is_a_finding_and_not_a_limit() -> None:
    # Fail closed on the value as well as reporting it. `two` is not a cap, and
    # a document that took it would have `resolve` and `route` reading a limit
    # the shell refuses to compare.
    typo = config.load(env={"HERDR_TEAM_EXEC_CAP": "two"}, dotfiles=DOTFILES)
    assert typo.get("role.exec.max_per_run") == 2
    assert typo.lint() == [
        "HERDR_TEAM_EXEC_CAP=two is not a whole number, and "
        "role.exec.max_per_run is a limit `team.sh` compares as a number"
    ]


def test_the_plan_maximum_is_not_exported() -> None:
    # `plan.py` reads it from the file directly. A name here that nothing reads
    # would be a knob that looks set from a shell and is not.
    names = [name for name, _ in shipped().env_pairs()]
    assert "HERDR_TEAM_PLAN_MAX_PATHS" not in names


def test_get_expands_a_placeholder() -> None:
    assert shipped().get("paths.root") == str(DOTFILES / ".herdr")
    assert shipped().get("limits.handoff_max_lines") == 150


def test_get_returns_the_default_for_a_key_no_layer_set() -> None:
    assert shipped().get("limits.nope") is None
    assert shipped().get("limits.nope", 3) == 3


def test_show_names_the_layer_a_value_came_from() -> None:
    lines = shipped().show(sources=True)
    assert "role.exec.max_per_run = 2  # %s" % TEAM in lines
    assert "paths.root = %s/.herdr  # %s" % (DOTFILES, TEAM) in lines


def test_show_indexes_a_list_of_tables() -> None:
    paths = [path for path, _ in config.flatten(shipped().resolved())]
    assert "route[0].role" in paths
    assert "route[0].when.provider_cost" in paths


# --- resolve ----------------------------------------------------------------


def test_resolve_profile_ccd() -> None:
    # The whole answer, key set included: an emitted key is a promise that
    # `team.sh` evals it, and the launch is the only thing this verb is asked
    # for. `harness`, `credential`, `reset`, `cost`, `ceiling` and `never` are
    # the profile *table*'s columns — `settle` reads them there, one call for
    # every profile at once — and a copy of them here would be a second answer
    # to keep in step with that one.
    assert shipped().profile("ccd") == {
        "launch": "ccd",
        "launch_args": "",
        # No `model` on the profile and `--model` on the harness: the harness
        # says how a model is passed, the profile says which one, and this
        # profile names none — the launcher's own `cc_provider` injection is
        # what puts `deepseek-flash` in front of the CLI.
        "model": "",
        "model_arg": "--model",
        "requires_reason": "false",
        "key": "env:CLAUDE_CODE_DEEPSEEK_API_KEY",
        "url": "https://api.deepseek.com/anthropic",
        "fallback": "cc",
        "fallback_on": "key-missing",
        "guard_credential": "anthropic-pro",
        "quota_max_pct": "70",
    }


def test_resolve_profile_carries_a_model_to_the_launch(tmp_path: Path) -> None:
    # The half of the profile's answer that is not a threshold: a profile that
    # *does* name a model has to reach the command line, or `[profile.cdx]`'s
    # `gpt-5-codex` would be a word only this file knows. The one profile that
    # names one ships disabled — codex until its spike passes, and its provider
    # entry with it — so a trusted overlay turns both on for the length of this
    # case, and the harness supplies the flag the CLI takes a model with.
    registry = tmp_path / "providers.toml"
    login = '[provider.openai]\nprotocol = "login"\nharnesses = ["codex"]\nceiling = 4'
    registry.write_text(
        (DOTFILES / "ai/providers.toml")
        .read_text()
        .replace("%s\nenabled = false" % login, "%s\nenabled = true" % login, 1)
    )
    overlay = tmp_path / "team.toml"
    overlay.write_text(
        "[harness.codex]\nenabled = true\n\n[profile.cdx]\nenabled = true\n"
    )
    profile = config.load(
        layers=[config.Layer(TEAM, True), config.Layer(overlay, True)],
        env={},
        providers_path=registry,
        dotfiles=DOTFILES,
    ).profile("cdx")
    assert profile["model"] == "gpt-5-codex"
    assert profile["model_arg"] == "-m"


def test_resolve_profile_omp_has_no_key_to_probe() -> None:
    # omp reads its key through its own config, so the file has a credential and
    # no url — which is what tells `spawn` there is nothing to probe for.
    profile = shipped().profile("omp")
    assert profile["launch"] == "omp"
    assert profile["launch_args"] == "--config %s/ai/omp/executor.yml" % DOTFILES
    assert profile["key"] == "env:PI_CODING_AGENT_DEEPSEEK_API_KEY"
    assert profile["url"] == ""
    assert profile["fallback"] == ""


def test_resolve_profile_cc_is_premium_and_has_to_say_why() -> None:
    profile = shipped().profile("cc")
    assert profile["requires_reason"] == "true"
    # The Pro login reads no key ref and is injected nothing: `cc` unsets the
    # provider environment and runs the CLI as the user's own login, so both
    # fields `spawn` probes on are empty, and an empty `fallback` says nothing
    # chains off the one profile that is already the expensive end of the table.
    assert profile["key"] == ""
    assert profile["url"] == ""
    assert profile["fallback"] == ""


def test_resolve_refuses_a_profile_that_ships_disabled() -> None:
    for name in ("cck", "cco", "cdx", "ccur", "ccp", "oc"):
        with pytest.raises(config.ConfigError, match="is disabled"):
            shipped().profile(name)


def test_resolve_refuses_a_profile_that_is_not_there() -> None:
    with pytest.raises(config.ConfigError, match="no profile"):
        shipped().profile("nope")


def table_of(conf: config.Config) -> dict[str, list[str]]:
    """`resolve profiles` as {profile: [credential, ceiling, reset]}.

    Split on the tab and not on whitespace: a harness that states no `reset =`
    leaves that column empty, and a whitespace split would drop it rather than
    report it — which is the column `settle` refuses on.
    """
    return {
        row[0]: row[1:] for row in (line.split("\t") for line in conf.profiles_table())
    }


def test_the_profile_table_names_every_profile_with_its_ceiling_and_reset() -> None:
    # The one call `team.sh` makes about ceilings: the ceiling belongs to the
    # credential and the reset to the harness, while every pane record, every
    # message and every plan row names a *profile* — and this is where the three
    # meet. Disabled profiles are in it too, which is the difference between it
    # and `resolve profile`: a pane spawned before its profile was disabled
    # still has to be settled, and the table is what `settle` reads to find out
    # what that pane clears with.
    table = [line.split("\t") for line in shipped().profiles_table()]
    assert table == [
        ["cc", "anthropic-pro", "4", "/clear"],
        ["ccd", "deepseek", "4", "/clear"],
        ["cck", "kimi", "4", "/clear"],
        ["cco", "openrouter", "4", "/clear"],
        ["ccp", "copilot", "4", ""],
        ["ccur", "cursor", "4", ""],
        ["cdx", "openai", "4", "/new"],
        ["oc", "openrouter", "4", ""],
        ["omp", "deepseek-omp", "4", "/clear"],
    ]


def test_the_table_carries_no_reset_for_a_harness_that_states_none() -> None:
    # Empty rather than `/clear`: the two harnesses below ship disabled and with
    # no `reset =`, and a `settle --clear` on one of them has no command it may
    # send. A default here would be this reader inventing one.
    resets = {name: row[2] for name, row in table_of(shipped()).items()}
    assert resets["cdx"] == "/new"
    assert resets["ccur"] == resets["ccp"] == ""


def test_the_table_follows_the_harness_a_profile_points_at(tmp_path: Path) -> None:
    # A profile is harness × credential × model, and the reset comes from the
    # first of those — so pointing one at another harness moves its reset, and
    # nothing about the profile's name is involved. `cck` rather than a profile
    # a role names, so that moving it moves nothing else.
    overlay = tmp_path / "team.toml"
    overlay.write_text('[profile.cck]\nharness = "codex"\ncredential = "openai"\n')
    moved = config.load(
        layers=[config.Layer(TEAM, True), config.Layer(overlay, True)],
        env={},
        dotfiles=DOTFILES,
    )
    assert moved.lint() == []
    assert table_of(moved)["cck"][2] == "/new"


def test_the_guard_is_found_through_the_role_and_not_by_name(tmp_path: Path) -> None:
    # The executor tier is whatever `role.exec.profiles` names, and which
    # profile that is is a config decision — `ccd` is not written down anywhere
    # in the reader. Pointing the role at another chain moves the guard with it.
    assert shipped().guard() == {"credential": "anthropic-pro", "quota_max_pct": 70}

    overlay = tmp_path / "team.toml"
    overlay.write_text(
        '[fallback.omp]\nto = ["cc"]\n'
        'guard = { credential = "anthropic-pro", quota_max_pct = 30 }\n\n'
        '[role.exec]\nprofiles = ["omp"]\n'
    )
    moved = config.load(
        layers=[config.Layer(TEAM, True), config.Layer(overlay, True)],
        env={},
        dotfiles=DOTFILES,
    )
    assert moved.lint() == []
    assert moved.guard() == {"credential": "anthropic-pro", "quota_max_pct": 30}
    assert dict(moved.env_pairs())["HERDR_TEAM_PRO_FALLBACK_MAX"] == "30"


def test_a_tier_with_no_guard_exports_no_fallback_limit(tmp_path: Path) -> None:
    overlay = tmp_path / "team.toml"
    overlay.write_text('[role.exec]\nprofiles = ["omp"]\n')
    unguarded = config.load(
        layers=[config.Layer(TEAM, True), config.Layer(overlay, True)],
        env={},
        dotfiles=DOTFILES,
    )
    assert unguarded.guard() is None
    assert "HERDR_TEAM_PRO_FALLBACK_MAX" not in dict(unguarded.env_pairs())


# --- route ------------------------------------------------------------------


def test_route_sends_a_row_with_a_verify_to_exec() -> None:
    route = shipped().route({"provider": "ccd", "verify": "pytest -q"})
    assert route == {"role": "exec", "lane": "exec", "profile": "ccd"}


def test_route_sends_a_web_need_to_research() -> None:
    route = shipped().route({"needs": "web"})
    assert route == {"role": "research", "lane": "res", "profile": "omp"}


def test_route_sends_a_premium_row_with_blockers_to_review() -> None:
    route = shipped().route({"provider": "cc", "blocks": ["T-02", "T-03"]})
    assert route == {"role": "review", "lane": "rev", "profile": "cc"}


def test_route_prefers_the_premium_rule_over_the_verify_rule() -> None:
    # Both match. First match wins, which is why the table is ordered and the
    # review rule is written above the exec rule.
    route = shipped().route(
        {"provider": "cc", "blocks": ["T-02"], "verify": "pytest -q"}
    )
    assert route["role"] == "review"


def test_route_takes_a_row_with_nothing_at_all() -> None:
    assert shipped().route({}) == {"role": "exec", "lane": "exec", "profile": "ccd"}


def test_route_refuses_a_row_that_names_a_provider_the_config_does_not_know() -> None:
    # `cdd` for `ccd` is the typo this is about, and the failure is the reason
    # the profile is a word half the printed sentences are spelled with: filling
    # in the default here would put the row on a profile its author never wrote,
    # and it would look like the row the config *was* asked for. Refused with the
    # name and where profiles live, which is what a caller has to fix; `spawn`
    # refuses the same name for the same reason, one wave later.
    with pytest.raises(config.ConfigError) as raised:
        shipped().route({"provider": "cdd", "verify": "pytest -q"})
    assert "the row names cdd" in str(raised.value)
    assert "no layer defines a profile of that name" in str(raised.value)


def test_route_reads_needs_as_words_or_as_a_list() -> None:
    assert shipped().route({"needs": "web,verify"})["role"] == "research"
    assert shipped().route({"needs": ["web"]})["role"] == "research"
    assert shipped().route({"needs": "review"})["role"] == "exec"


def test_route_will_not_answer_while_the_config_has_findings() -> None:
    with pytest.raises(config.ConfigError, match="finding"):
        overlaid("bad-ref.toml").route({})


def test_route_places_a_row_on_the_profile_the_route_names() -> None:
    # The profile a provider-less row launches is the matched entry's own word.
    # `shipped()` answers `ccd` for this row because no route names anything;
    # the fixture's third entry names `mid`, and that is the whole difference —
    # which is what lets a config put a kind of row on its own tier without a
    # line of `loop.py` or `team.sh` knowing the name.
    table = overlaid("route-names-a-profile.toml")
    assert table.route({"verify": "pytest -q"}) == {
        "role": "exec",
        "lane": "exec",
        "profile": "mid",
    }


def test_route_answers_a_lane_no_reader_knows() -> None:
    # The lane is the matched role's prefix, so a role this file adds answers a
    # lane of its own — `audit`, which appears in no reader, in `team.sh`'s
    # `case` arms or in its lane pools. That is the property `lane_for` has
    # because it asks `route` rather than comparing a provider against a name.
    table = overlaid("route-names-a-profile.toml")
    assert table.route({"needs": "web"}) == {
        "role": "audit",
        "lane": "audit",
        "profile": "mid",
    }


def test_requires_reason_is_read_off_the_profile_the_row_names() -> None:
    # The read `plan.py`'s tier warning makes, spelled out: the key is the
    # profile the row names, and a profile may be added to the set that has to
    # account for itself without being called `cc`. `None` is a profile that has
    # said nothing about its tier, which `_needs_reason` reads as `is True` —
    # not as a third answer.
    table = overlaid("route-names-a-profile.toml")
    assert table.get("profile.mid.requires_reason") is True
    assert table.get("profile.ccd.requires_reason") is None


# --- the layers -------------------------------------------------------------


def test_a_later_layer_wins(tmp_path: Path) -> None:
    overlay = tmp_path / "team.toml"
    overlay.write_text("[limits]\ndetect_timeout_s = 30\n")
    config_with = config.load(
        layers=[config.Layer(TEAM, True), config.Layer(overlay, True)],
        env={},
        dotfiles=DOTFILES,
    )
    assert config_with.get("limits.detect_timeout_s") == 30
    assert config_with.get("limits.handoff_max_lines") == 150
    assert config_with.lint() == []


def test_arrays_replace_rather_than_concatenate() -> None:
    # Not a detail of the merge: an untrusted layer that could *append* to
    # `fallback.<p>.never` could also choose what the list ends up being.
    overlaid_roles = overlaid("untrusted-premium.toml", trusted=True)
    assert overlaid_roles.get("role.spec.profiles") == ["cc"]
    assert "spec-" in str(overlaid_roles.get("role.spec.prefix"))


def test_a_layer_that_is_not_there_is_not_a_finding(tmp_path: Path) -> None:
    config_with = config.load(
        layers=[config.Layer(TEAM, True), config.Layer(tmp_path / "absent.toml", True)],
        env={},
        dotfiles=DOTFILES,
    )
    assert config_with.lint() == []


def test_a_local_file_overrides_the_shipped_one(tmp_path: Path) -> None:
    local = tmp_path / "team.toml"
    local.write_text("[role.exec]\nmax_per_run = 4\n")
    config_with = config.load(
        layers=[config.Layer(TEAM, True), config.Layer(local, True)],
        env={},
        dotfiles=DOTFILES,
    )
    assert config_with.get("role.exec.max_per_run") == 4
    assert config_with.get("role.exec.profiles") == ["ccd"]


def test_herdr_team_config_replaces_the_whole_stack(tmp_path: Path) -> None:
    # The recovery path a typo in team.local.toml needs: without it the broken
    # file is read by every verb and there is no way to ask for the defaults.
    one = tmp_path / "one.toml"
    one.write_text(TEAM.read_text())
    layers = config.default_layers(env={"HERDR_TEAM_CONFIG": str(one)})
    assert layers == [config.Layer(one, True)]


def test_the_project_layers_are_only_read_for_another_checkout(tmp_path: Path) -> None:
    here = config.default_layers(dotfiles=DOTFILES, env={})
    assert [layer.path for layer in here] == [
        DOTFILES / "ai/herdr/team.toml",
        DOTFILES / "ai/herdr/team.local.toml",
    ]
    elsewhere = config.default_layers(dotfiles=DOTFILES, repo=tmp_path, env={})
    assert [layer.trusted for layer in elsewhere] == [True, True, False, False]
    assert elsewhere[2].path == tmp_path / ".config/herdr/team.toml"


# --- presets ----------------------------------------------------------------


def test_a_preset_patches_the_roles() -> None:
    assert shipped(preset="pro-low").get("role.plan.profiles") == ["ccd"]
    assert shipped(preset="pro-low").get("role.exec.profiles") == ["ccd"]
    assert shipped(preset="all-cheap").get("role.exec.max_per_run") == 4
    assert shipped(preset="all-cheap").get("role.plan.profiles") == ["cc"]


def test_a_preset_is_reported_as_its_own_layer() -> None:
    assert shipped(preset="pro-low").source("role.plan.profiles") == "preset:pro-low"


def test_a_preset_is_not_left_in_the_resolved_document() -> None:
    assert shipped(preset="pro-low").get("preset") is None


def test_a_preset_selected_by_the_environment_is_used() -> None:
    config_with = config.load(env={"HERDR_TEAM_PRESET": "all-cheap"}, dotfiles=DOTFILES)
    assert config_with.get("role.exec.max_per_run") == 4


def test_an_unknown_preset_is_refused() -> None:
    with pytest.raises(config.ConfigError, match="all-cheap, pro-low"):
        shipped(preset="nope")


def test_a_preset_still_has_to_validate() -> None:
    assert shipped(preset="pro-low").lint() == []
    assert shipped(preset="all-cheap").lint() == []


# --- trust ------------------------------------------------------------------


def test_an_untrusted_layer_may_set_limits_roles_and_routes(tmp_path: Path) -> None:
    overlay = tmp_path / "team.toml"
    overlay.write_text(
        "[limits]\ndetect_timeout_s = 30\n\n"
        '[role.exec]\nprofiles = ["omp"]\nmax_per_run = 6\n\n'
        '[[route]]\nrole = "research"\n'
    )
    config_with = config.load(
        layers=[config.Layer(TEAM, True), config.Layer(overlay, False)],
        env={},
        dotfiles=DOTFILES,
    )
    assert config_with.lint() == []
    assert config_with.get("limits.detect_timeout_s") == 30
    assert config_with.get("role.exec.max_per_run") == 6
    assert config_with.route({"needs": "web"})["role"] == "research"


def refused(tmp_path: Path, body: str) -> config.Config:
    """An untrusted project layer over the shipped file."""
    overlay = tmp_path / "team.toml"
    overlay.write_text(body)
    return config.load(
        layers=[config.Layer(TEAM, True), config.Layer(overlay, False)],
        env={},
        dotfiles=DOTFILES,
    )


@pytest.mark.parametrize(
    ("body", "refused_key"),
    [
        # Named by the table the layer wrote rather than by the keys in it: the
        # whole of `[profile.ccd]` is the user's, and one finding about the
        # table a project added is more use than one line per key inside it.
        ('[harness.mine]\nkind = "mine"\nlaunch = "mine"\n', "harness.mine"),
        ('[paths]\nroot = "/tmp/elsewhere"\n', "paths"),
        (
            '[profile.ccd]\nlaunch = "/tmp/evil"\ncredential = "anthropic-pro"\n',
            "profile.ccd",
        ),
        ('[role.exec]\nprefix = "x-"\n', "role.exec.prefix"),
        ('[fallback.ccd]\nguard = { credential = "deepseek" }\n', "fallback.ccd.guard"),
        ("schema = 1\nfoo = 2\n", "foo"),
    ],
)
def test_an_untrusted_layer_may_not_reach_a_key_that_names_a_command(
    tmp_path: Path, body: str, refused_key: str
) -> None:
    # A finding rather than an exception, and the difference matters: `env`,
    # `resolve` and `route` all refuse to run while findings exist, so the file
    # is never acted on, while `show` and `lint` still run so its owner can find
    # out what is wrong with it.
    config_with = refused(tmp_path, body)
    assert any(refused_key in finding for finding in config_with.lint())
    with pytest.raises(config.ConfigError, match="finding"):
        config_with.env_pairs()


def test_an_untrusted_layer_may_not_name_a_premium_profile() -> None:
    assert findings("untrusted-premium.toml", trusted=False) == [
        "%s: role.spec.profiles names cc, whose cost is premium — an untrusted "
        "layer may name only cheap profiles, so it can never spend the Pro "
        "login" % (FIXTURES / "untrusted-premium.toml")
    ]


def test_an_untrusted_route_may_not_land_on_a_premium_role() -> None:
    # The hole a reader that stopped at `route.profile` left: this route names no
    # profile, it names a role, and the role it names launches `cc` — the same
    # attack as the fixture above, through the other key a route has for saying
    # where a row goes. The finding is about what the route landed on rather than
    # what it wrote, which is why it is a `_cheap_only` finding at all.
    assert findings("untrusted-route-role.toml", trusted=False) == [
        "%s: route[0].role.profiles names cc, whose cost is premium — an "
        "untrusted layer may name only cheap profiles, so it can never spend "
        "the Pro login" % (FIXTURES / "untrusted-route-role.toml")
    ]


def test_the_same_file_is_fine_from_a_trusted_layer() -> None:
    assert findings("untrusted-premium.toml", trusted=True) == []
    assert findings("untrusted-route-role.toml", trusted=True) == []


def test_an_untrusted_layer_may_not_shrink_never() -> None:
    assert findings("never-shrinks.toml", trusted=False) == [
        "%s: fallback.ccd.never drops omp from `never` — a project may add to "
        "that list and never take away from it" % (FIXTURES / "never-shrinks.toml")
    ]


def test_an_untrusted_layer_may_grow_never(tmp_path: Path) -> None:
    overlay = tmp_path / "team.toml"
    overlay.write_text('[fallback.ccd]\nnever = ["omp", "cc"]\n')
    config_with = config.load(
        layers=[config.Layer(TEAM, True), config.Layer(overlay, False)],
        env={},
        dotfiles=DOTFILES,
    )
    # `cc` is in `to`, so this one is also a contradiction of its own.
    assert any("both `to` and `never`" in finding for finding in config_with.lint())
    assert not any("drops" in finding for finding in config_with.lint())


def test_an_untrusted_preset_is_held_to_the_same_rules(tmp_path: Path) -> None:
    overlay = tmp_path / "team.toml"
    overlay.write_text('[preset.mine]\nrole.spec.profiles = ["cc"]\n')
    config_with = config.load(
        layers=[config.Layer(TEAM, True), config.Layer(overlay, False)],
        preset="mine",
        env={},
        dotfiles=DOTFILES,
    )
    assert any(
        "preset.mine.role.spec.profiles" in finding for finding in config_with.lint()
    )


# --- the fixtures AC2 names -------------------------------------------------

CASES = [
    ("bad-ref.toml", "role.spec.profiles names 'nope'"),
    ("fallback-cycle.toml", "a cycle through cc -> ccd -> cc"),
    ("to-and-never.toml", "cc is in both `to` and `never`"),
    ("unknown-key.toml", "unknown key provider_cap"),
]


@pytest.mark.parametrize(("name", "expected"), CASES)
def test_a_fixture_is_reported(name: str, expected: str) -> None:
    found = findings(name)
    assert any(expected in finding for finding in found), found


@pytest.mark.parametrize("name", [name for name, _ in CASES])
def test_a_fixture_is_valid_toml(name: str) -> None:
    # lint.yml parses every tracked `*.toml` with the standard library's reader.
    # A fixture that was malformed would fail that step before any test ran, so
    # the malformed cases are written into a temporary directory instead.
    assert config.read_layer(FIXTURES / name)


def test_every_fixture_is_something_lint_refuses() -> None:
    for name in (
        "bad-ref.toml",
        "fallback-cycle.toml",
        "to-and-never.toml",
        "unknown-key.toml",
    ):
        assert findings(name), "%s lints clean, so it pins nothing" % name
    for name in (
        "untrusted-premium.toml",
        "untrusted-route-role.toml",
        "never-shrinks.toml",
    ):
        assert findings(name, trusted=False), name


# --- failing closed ---------------------------------------------------------


def broken(tmp_path: Path) -> Path:
    path = tmp_path / "team.local.toml"
    path.write_text('schema = 1\n\n[limits\nexec_per_run = "two"\n')
    return path


def test_a_syntax_error_names_the_file_and_the_line(tmp_path: Path) -> None:
    path = broken(tmp_path)
    with pytest.raises(config.ConfigError) as raised:
        config.read_layer(path)
    assert raised.value.where == str(path)
    assert raised.value.line == 3
    assert str(raised.value).startswith("%s:3" % path)


def test_a_schema_from_the_future_is_refused(tmp_path: Path) -> None:
    path = tmp_path / "team.toml"
    path.write_text("schema = 99\n")
    with pytest.raises(config.ConfigError, match="schema 99 is not 1"):
        config.read_layer(path)


@pytest.mark.parametrize(
    "argv",
    [
        ["env"],
        ["get", "limits.exec_per_run"],
        ["resolve", "profile", "ccd"],
        ["route", "{}"],
    ],
)
def test_every_verb_refuses_a_broken_layer(
    argv: list[str],
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    monkeypatch.setenv(config.ENV_CONFIG, str(broken(tmp_path)))
    assert config.main(argv) == 1
    assert "team.local.toml:3" in capsys.readouterr().err


def test_every_verb_refuses_a_layer_that_will_not_parse(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    # AC6: a file that will not parse is not a finding, because nothing was
    # resolved to have a finding about. `show` included — it has no config to
    # show — and the refusal names the file and the line.
    monkeypatch.setenv(config.ENV_CONFIG, str(broken(tmp_path)))
    assert config.main(["show"]) == 1


def test_show_still_runs_on_a_config_that_has_findings(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    # The two verbs that exist to explain a bad configuration have to survive
    # one, or a config that does not validate is also one nobody can inspect.
    # `HERDR_TEAM_CONFIG` replaces the stack rather than adding to it, so what
    # `show` prints here is the fixture on its own.
    monkeypatch.setenv(config.ENV_CONFIG, str(FIXTURES / "unknown-key.toml"))
    monkeypatch.setenv("DOTFILES", str(DOTFILES))
    assert config.main(["show"]) == 0
    assert "provider_cap = 4" in capsys.readouterr().out


def test_lint_reports_and_exits_non_zero(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv(config.ENV_CONFIG, str(FIXTURES / "unknown-key.toml"))
    assert config.main(["lint"]) == 1
    assert "unknown key provider_cap" in capsys.readouterr().out


def test_a_literal_key_in_the_registry_reaches_config_lint(tmp_path: Path) -> None:
    # The registry's own findings are part of the document's, and this is the
    # verb that has to carry them: `config lint` is the only one that sees both
    # files, so it is the only place a secret written into ai/providers.toml can
    # be refused before the shell cache defines a launcher around it. A profile
    # names its `credential` here, so the entry behind that name has already
    # been parsed by the time a finding is raised about it — reporting one file
    # clean while the other is not would be the reader's answer drifting from
    # the shell's.
    registry = tmp_path / "providers.toml"
    registry.write_text(
        (DOTFILES / "ai/providers.toml")
        .read_text()
        .replace(
            'key = "env:CLAUDE_CODE_DEEPSEEK_API_KEY"', 'key = "sk-not-a-reference"', 1
        )
    )
    found = config.load(
        layers=[config.Layer(TEAM, True)],
        env={},
        providers_path=registry,
        dotfiles=DOTFILES,
    ).lint()
    assert any("is not a reference" in finding for finding in found), found


# --- the command line -------------------------------------------------------


def test_main_lint_is_zero_on_a_clean_config(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv(config.ENV_CONFIG, str(TEAM))
    monkeypatch.setenv("DOTFILES", str(DOTFILES))
    assert config.main(["lint"]) == 0
    assert capsys.readouterr().out == "config: ok\n"


def test_main_env_prints_shell_assignments(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv(config.ENV_CONFIG, str(TEAM))
    monkeypatch.setenv("DOTFILES", str(DOTFILES))
    assert config.main(["env"]) == 0
    out = capsys.readouterr().out
    assert "HERDR_TEAM_ROOT=%s/.herdr\n" % DOTFILES in out
    assert "HERDR_TEAM_EXEC_CAP=2\n" in out


def test_main_resolve_profiles_prints_the_table(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    # What `team.sh` runs once per process for the ceilings, and the reason it
    # can count a credential's panes while every record it holds names a
    # profile. One profile per line, four tab-separated columns.
    monkeypatch.setenv(config.ENV_CONFIG, str(TEAM))
    monkeypatch.setenv("DOTFILES", str(DOTFILES))
    assert config.main(["resolve", "profiles"]) == 0
    out = capsys.readouterr().out
    assert "ccd\tdeepseek\t4\t/clear\n" in out
    assert "cdx\topenai\t4\t/new\n" in out
    assert "ccur\tcursor\t4\t\n" in out


def test_main_env_is_evaluable(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv(config.ENV_CONFIG, str(TEAM))
    monkeypatch.setenv("DOTFILES", str(DOTFILES))
    config.main(["env"])
    namespace: dict[str, str] = {}
    for line in capsys.readouterr().out.splitlines():
        name, value = line.split("=", 1)
        namespace[name] = value.strip("'")
    assert namespace["HERDR_TEAM_EXEC_CAP"] == "2"
    assert namespace["HERDR_TEAM_PRO_QUOTA_MAX_AGE"] == "900"


def test_main_resolve_prints_a_profile_as_assignments(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv(config.ENV_CONFIG, str(TEAM))
    monkeypatch.setenv("DOTFILES", str(DOTFILES))
    assert config.main(["resolve", "profile", "ccd"]) == 0
    assert "launch=ccd\n" in capsys.readouterr().out


def test_main_route_prints_the_role_the_lane_and_the_profile(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv(config.ENV_CONFIG, str(TEAM))
    monkeypatch.setenv("DOTFILES", str(DOTFILES))
    assert config.main(["route", '{"needs": "web"}']) == 0
    assert capsys.readouterr().out == "role=research\nlane=res\nprofile=omp\n"


def test_main_get_prints_one_value(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv(config.ENV_CONFIG, str(TEAM))
    monkeypatch.setenv("DOTFILES", str(DOTFILES))
    assert config.main(["get", "role.exec.max_per_run"]) == 0
    assert capsys.readouterr().out == "2\n"


def test_main_get_names_a_key_that_is_not_there(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv(config.ENV_CONFIG, str(TEAM))
    monkeypatch.setenv("DOTFILES", str(DOTFILES))
    assert config.main(["get", "limits.nope"]) == 1
    assert "no limits.nope" in capsys.readouterr().err


@pytest.mark.parametrize(
    "argv",
    [[], ["nope"], ["show", "--bad"], ["get"], ["resolve", "role", "exec"], ["route"]],
)
def test_main_refuses_what_it_cannot_answer(
    argv: list[str], capsys: pytest.CaptureFixture[str]
) -> None:
    assert config.main(argv) == 2
    capsys.readouterr()


def test_main_route_reports_json_it_cannot_read(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv(config.ENV_CONFIG, str(TEAM))
    monkeypatch.setenv("DOTFILES", str(DOTFILES))
    assert config.main(["route", "{not json"]) == 2
    assert "not JSON" in capsys.readouterr().err


# --- the merge and the expansion, as functions ------------------------------


def test_merge_leaves_a_sibling_alone() -> None:
    into: dict[str, Any] = {"limits": {"exec_per_run": 2, "handoff_max_lines": 150}}
    config.merge(into, {"limits": {"exec_per_run": 6}})
    assert into == {"limits": {"exec_per_run": 6, "handoff_max_lines": 150}}


def test_leaves_are_dotted_and_a_list_of_tables_is_one_leaf() -> None:
    node: dict[str, Any] = {
        "b": 1,
        "a": {"d": 2, "c": 3},
        "route": [{"role": "review"}],
    }
    assert list(config.leaves(node)) == ["a.c", "a.d", "b", "route"]


def test_expand_reads_a_default_still_containing_a_reference() -> None:
    expanded = config._expand("${A:-${B}/x}", {"B": "/b"})
    assert expanded == "/b/x"


def test_expand_prefers_the_value_over_the_default() -> None:
    assert config._expand("${A:-/b}", {"A": "/a"}) == "/a"


def test_expand_leaves_an_unset_reference_empty() -> None:
    assert config._expand("${A:-}", {}) == ""
    assert config._expand("x${A}y", {}) == "xy"


def test_expand_only_rewrites_a_leading_tilde() -> None:
    assert config._expand("~/x", {"HOME": "/h"}) == "/h/x"
    assert config._expand("/a/~/b", {"HOME": "/h"}) == "/a/~/b"


# --- the project's own repository (T-01: run-bound repo) --------------------


def _git(*args: str, cwd: Path) -> None:
    subprocess.run(
        ["git", "-c", "commit.gpgsign=false", *args],
        cwd=cwd,
        check=True,
        capture_output=True,
        env={
            **os.environ,
            "GIT_AUTHOR_NAME": "t",
            "GIT_AUTHOR_EMAIL": "t@t",
            "GIT_COMMITTER_NAME": "t",
            "GIT_COMMITTER_EMAIL": "t@t",
        },
    )


def test_common_dir_of_a_non_git_path_is_none(tmp_path: Path) -> None:
    assert config._common_dir(tmp_path) is None


def test_common_dir_of_a_git_checkout_is_stable() -> None:
    # Not asserting a particular string — only that a real checkout answers,
    # and answers the same way twice, since that stability is the whole of
    # what the comparison in `default_layers` depends on.
    common = config._common_dir(DOTFILES)
    assert common is not None
    assert common == config._common_dir(DOTFILES)


def test_default_layers_reads_the_repo_from_the_environment(tmp_path: Path) -> None:
    # AC5/AC8's transport: `team.sh` exports `HERDR_TEAM_REPO` rather than
    # passing `--repo` to the Python reader, so `default_layers` has to fall
    # back to it exactly the way it falls back to `DOTFILES`.
    from_env = config.default_layers(
        dotfiles=DOTFILES, env={config.ENV_REPO: str(tmp_path)}
    )
    assert [layer.trusted for layer in from_env] == [True, True, False, False]
    assert from_env[2].path == tmp_path / ".config/herdr/team.toml"
    # An explicit `repo=` still wins over the environment.
    explicit = config.default_layers(
        dotfiles=DOTFILES, repo=DOTFILES, env={config.ENV_REPO: str(tmp_path)}
    )
    assert [layer.path for layer in explicit] == [
        DOTFILES / "ai/herdr/team.toml",
        DOTFILES / "ai/herdr/team.local.toml",
    ]


def test_default_layers_treats_a_worktree_as_the_same_repository(
    tmp_path: Path,
) -> None:
    # The comparison is git identity, not path spelling: a linked worktree of
    # `dotfiles` is a different directory but the same repository, and reading
    # its `.config/herdr/` as a project layer would be reading the dotfiles'
    # own directory back as if it belonged to someone else.
    main_repo = tmp_path / "main"
    main_repo.mkdir()
    _git("init", "-q", cwd=main_repo)
    _git("commit", "-q", "--allow-empty", "-m", "x", cwd=main_repo)
    wt = tmp_path / "wt"
    _git("worktree", "add", "-q", "-b", "feature", str(wt), cwd=main_repo)
    layers = config.default_layers(dotfiles=main_repo, repo=wt, env={})
    assert [layer.path for layer in layers] == [
        main_repo / "ai/herdr/team.toml",
        main_repo / "ai/herdr/team.local.toml",
    ]


def test_default_layers_treats_an_unrelated_repository_as_a_project(
    tmp_path: Path,
) -> None:
    other = tmp_path / "other"
    other.mkdir()
    _git("init", "-q", cwd=other)
    layers = config.default_layers(dotfiles=DOTFILES, repo=other, env={})
    assert [layer.trusted for layer in layers] == [True, True, False, False]
    assert layers[2].path == other / ".config/herdr/team.toml"


def test_main_repo_flag_reads_the_project_layer(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    # AC8: `show`, `get`, `lint` and `env` accept `--repo`, which is how
    # `team.sh config` (via `cmd_config`) hands the reader the Run's project
    # without every caller having to export `HERDR_TEAM_REPO` first.
    monkeypatch.setenv("DOTFILES", str(DOTFILES))
    project = tmp_path / "project"
    (project / ".config/herdr").mkdir(parents=True)
    (project / ".config/herdr/team.toml").write_text("[limits]\ndetect_timeout_s = 5\n")
    assert config.main(["get", "limits.detect_timeout_s", "--repo", str(project)]) == 0
    assert capsys.readouterr().out == "5\n"
    assert config.main(["show", "--repo", str(project)]) == 0
    assert "detect_timeout_s = 5" in capsys.readouterr().out
    assert config.main(["lint", "--repo", str(project)]) == 0
    assert config.main(["env", "--repo", str(project)]) == 0
    assert "HERDR_TEAM_DETECT_TIMEOUT=5\n" in capsys.readouterr().out


def test_main_repo_flag_needs_a_path(capsys: pytest.CaptureFixture[str]) -> None:
    assert config.main(["show", "--repo"]) == 1
    assert "--repo: needs a path" in capsys.readouterr().err


def test_main_env_refuses_an_argument_that_is_not_repo(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv(config.ENV_CONFIG, str(TEAM))
    monkeypatch.setenv("DOTFILES", str(DOTFILES))
    assert config.main(["env", "--bad"]) == 2
