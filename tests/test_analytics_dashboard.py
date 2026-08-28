import json
import os
from datetime import datetime, timezone

import pytest

import scripts.analytics_dashboard as dashboard
from scripts.analytics_dashboard import (
    build_snapshot,
    estimate_external_interest,
    render_dashboard,
    write_private,
)

NOW = datetime(2026, 8, 27, 22, 0, tzinfo=timezone.utc)


def github_fixture():
    return {
        "repository": {
            "full_name": "shimoverse/openvoiceflow",
            "html_url": "https://github.com/shimoverse/openvoiceflow",
            "stargazers_count": 16,
            "forks_count": 2,
            "open_issues_and_pull_requests_count": 1,
        },
        "views": {
            "count": 35,
            "uniques": 24,
            "views": [{"timestamp": "2026-08-26T00:00:00Z", "count": 1, "uniques": 1}],
        },
        "clones": {
            "count": 274,
            "uniques": 141,
            "clones": [{"timestamp": "2026-08-26T00:00:00Z", "count": 103, "uniques": 41}],
        },
        "popular_referrers": [
            {"referrer": "panel.socialplug.io", "count": 14, "uniques": 12},
            {"referrer": "github.com", "count": 4, "uniques": 3},
        ],
        "popular_paths": [{"path": "/shimoverse/openvoiceflow", "title": "OpenVoiceFlow", "count": 31, "uniques": 22}],
        "releases": [
            {
                "tag_name": "native-v0.5.6",
                "published_at": "2026-08-26T06:51:52Z",
                "assets": [
                    {"name": "OpenVoiceFlow-0.5.6.dmg", "download_count": 25},
                    {"name": "appcast.xml", "download_count": 1},
                ],
            }
        ],
        "workflow_runs": [
            {"id": 1, "created_at": "2026-08-24T01:00:00Z", "checkout_jobs": 90},
            {"id": 2, "created_at": "2026-08-26T01:00:00Z", "checkout_jobs": 49},
        ],
        "stargazers": [
            {
                "login": "old-contributor",
                "starred_at": "2026-08-27T01:00:00Z",
                "created_at": "2018-01-01T00:00:00Z",
                "public_repos": 12,
                "followers": 3,
            },
            {
                "login": "new-empty",
                "starred_at": "2026-08-26T01:00:00Z",
                "created_at": "2026-08-26T00:00:00Z",
                "public_repos": 0,
                "followers": 0,
            },
            {
                "login": "shimoverse",
                "starred_at": "2026-08-26T01:00:00Z",
                "created_at": "2015-01-01T00:00:00Z",
                "public_repos": 50,
                "followers": 20,
            },
        ],
    }


def vercel_fixture():
    return {
        "available": True,
        "window": {"from": "2026-07-29T07:00:00Z", "to": "2026-08-28T07:00:00Z", "days": 30},
        "overview": {"pageviews": 16, "visitors": 15},
        "stats": {
            "path": [{"key": "/", "total": 15, "visitors": 14}],
            "referrer": [{"key": "bing.com", "total": 6, "visitors": 5}],
            "event_name": [],
            "country": [{"key": "US", "total": 14, "visitors": 13}],
            "device_type": [{"key": "desktop", "total": 14, "visitors": 13}],
            "os_name": [{"key": "Mac", "total": 1, "visitors": 1}],
        },
    }


def test_external_interest_is_a_lower_bound_not_an_install_claim():
    estimate = estimate_external_interest(github_fixture(), owner_logins={"shimoverse"}, now=NOW)

    assert estimate["high_confidence_external_interest"] == 1
    assert estimate["verified_installs"] is None
    assert estimate["possible_external_cloners"] is None
    assert "not install" in estimate["label"].lower()
    assert estimate["low_signal_recent_stars"] == 1


def test_snapshot_keeps_metrics_separate_and_labels_automation():
    snapshot = build_snapshot(github_fixture(), vercel_fixture(), now=NOW, owner_logins={"shimoverse"})

    assert snapshot["schema_version"] == 1
    assert snapshot["github"]["clones"]["operations"] == 274
    assert snapshot["github"]["clones"]["unique_cloners"] == 141
    assert snapshot["github"]["automation"]["checkout_jobs"] == 139
    assert snapshot["github"]["automation"]["owner_external_split"] is None
    assert snapshot["github"]["release_assets"][0]["requests"] == 25
    assert snapshot["website"]["pageviews"] == 16
    assert snapshot["website"]["visitors"] == 15
    assert snapshot["adoption"]["verified_installs"] is None
    assert snapshot["adoption"]["active_users"] is None
    assert snapshot["adoption"]["exact_real_users"] is None


def test_snapshot_does_not_embed_credentials_or_local_auth_paths():
    snapshot = build_snapshot(github_fixture(), vercel_fixture(), now=NOW, owner_logins={"shimoverse"})
    serialized = json.dumps(snapshot).lower()

    for forbidden in ("authorization", "bearer ", "auth.json", "vercel_token", "github_token"):
        assert forbidden not in serialized


def test_dashboard_is_self_contained_private_and_explains_limitations():
    snapshot = build_snapshot(github_fixture(), vercel_fixture(), now=NOW, owner_logins={"shimoverse"})
    html = render_dashboard(snapshot)

    assert "OpenVoiceFlow Analytics" in html
    assert "High-confidence external interest" in html
    assert "Verified installs" in html
    assert "Unknown" in html
    assert "274" in html
    assert "139" in html
    assert "GitHub does not expose clone identities, IP addresses, user agents, or geography" in html
    assert "<script src=" not in html
    assert "https://va.vercel-scripts.com" not in html


def test_private_writer_uses_owner_only_permissions(tmp_path):
    output = tmp_path / "nested" / "dashboard.html"
    write_private(output, "secret-ish aggregate analytics")

    assert output.read_text() == "secret-ish aggregate analytics"
    assert os.stat(output).st_mode & 0o777 == 0o600


def test_private_writer_does_not_chmod_existing_custom_parent(tmp_path):
    shared = tmp_path / "shared"
    shared.mkdir(mode=0o755)
    os.chmod(shared, 0o755)

    write_private(shared / "dashboard.html", "aggregate analytics")

    assert os.stat(shared).st_mode & 0o777 == 0o755
    assert os.stat(shared / "dashboard.html").st_mode & 0o777 == 0o600


def test_vercel_project_discovery_supports_personal_scope(monkeypatch):
    calls = []

    def fake_json(url, token):
        calls.append(url)
        if "/v2/teams" in url:
            return {"teams": [{"id": "team_1"}]}
        if url.endswith("/v9/projects/openvoiceflow"):
            return {"id": "prj_personal"}
        raise AssertionError(url)

    monkeypatch.setattr(dashboard, "_vercel_json", fake_json)

    assert dashboard._discover_vercel_project("unused", "openvoiceflow") == (None, "prj_personal")
    assert not any("teamId=" in url for url in calls)


def test_vercel_collector_uses_documented_api_and_normalizes_metrics(monkeypatch):
    calls = []

    def fake_json(url, token):
        calls.append(url)
        if "/visits/count?" in url:
            return {"version": 1, "data": {"pageviews": 16, "visitors": 15}}
        if "/events/aggregate?" in url:
            return {"version": 1, "data": [{"eventName": "download_click", "count": 2, "visitors": 1}]}
        if "/visits/aggregate?" in url:
            from urllib.parse import parse_qs, urlparse

            dimension = parse_qs(urlparse(url).query)["by"][0]
            return {"version": 1, "data": [{dimension: "sample", "pageviews": 3, "visitors": 2}]}
        raise AssertionError(url)

    monkeypatch.setattr(dashboard, "_vercel_token", lambda: "unused")
    monkeypatch.setattr(dashboard, "_discover_vercel_project", lambda token, name: ("team_1", "prj_1"))
    monkeypatch.setattr(dashboard, "_vercel_json", fake_json)

    result = dashboard.collect_vercel(now=NOW, days=30)

    assert result["overview"] == {"pageviews": 16, "visitors": 15}
    assert result["stats"]["path"] == [{"key": "sample", "total": 3, "visitors": 2}]
    assert result["stats"]["event_name"] == [{"key": "download_click", "total": 2, "visitors": 1}]
    assert calls and all(url.startswith("https://api.vercel.com/v1/query/web-analytics/") for url in calls)
    assert all("vercel.com/api/web-analytics/v2" not in url for url in calls)


def test_github_object_pagination_collects_every_page(monkeypatch):
    def fake_api(path, accept=None):
        from urllib.parse import parse_qs, urlparse

        page = parse_qs(urlparse(path).query)["page"][0]
        if page == "1":
            return {"workflow_runs": [{"id": value} for value in range(100)]}
        if page == "2":
            return {"workflow_runs": [{"id": 100}]}
        raise AssertionError(path)

    monkeypatch.setattr(dashboard, "_gh_api", fake_api)

    runs = dashboard._gh_paginate_key("repos/example/actions/runs", "workflow_runs")

    assert len(runs) == 101
    assert runs[-1]["id"] == 100


def test_dashboard_survives_missing_vercel_data():
    unavailable = {"available": False, "error": "Vercel analytics unavailable"}
    snapshot = build_snapshot(github_fixture(), unavailable, now=NOW, owner_logins={"shimoverse"})
    html = render_dashboard(snapshot)

    assert snapshot["website"]["available"] is False
    assert "Website analytics unavailable" in html


def test_invalid_provider_shapes_fail_closed():
    bad = github_fixture()
    bad["clones"] = {"count": "274", "uniques": 10, "clones": []}

    with pytest.raises(ValueError, match="clones.count"):
        build_snapshot(bad, vercel_fixture(), now=NOW, owner_logins={"shimoverse"})
