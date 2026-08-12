"""Post Cloud Build results to Slack.

Cloud Build publishes every build status transition to the `cloud-builds`
Pub/Sub topic. This function subscribes to it and posts the terminal ones to a
Slack channel, so that a failure is something you are told about rather than
something you find later in the build history.

Only terminal statuses are posted. Cloud Build emits QUEUED and WORKING for the
same build, and relaying those would mean three messages per build and a channel
nobody reads.
"""

import base64
import json
import os
import urllib.request

import functions_framework

SLACK_API = "https://slack.com/api/chat.postMessage"

# Statuses worth interrupting someone for. QUEUED/WORKING are deliberately absent.
TERMINAL = {
    "SUCCESS": (":white_check_mark:", "succeeded"),
    "FAILURE": (":x:", "FAILED"),
    "INTERNAL_ERROR": (":rotating_light:", "errored internally"),
    "TIMEOUT": (":hourglass:", "timed out"),
    "CANCELLED": (":black_square_for_stop:", "was cancelled"),
    "EXPIRED": (":hourglass:", "expired"),
}


def _duration(build):
    start, finish = build.get("startTime"), build.get("finishTime")
    if not (start and finish):
        return None
    try:
        from datetime import datetime

        fmt = lambda t: datetime.fromisoformat(t.replace("Z", "+00:00"))
        secs = int((fmt(finish) - fmt(start)).total_seconds())
    except (ValueError, TypeError):
        return None
    return "%dm %02ds" % divmod(secs, 60) if secs >= 60 else "%ds" % secs


def _describe(build):
    """Best-effort human name for what was built.

    Trigger name is not present on every build — manual `gcloud builds submit`
    runs have no trigger at all — so fall back through source info rather than
    posting an opaque build id.
    """
    name = build.get("substitutions", {}).get("TRIGGER_NAME")
    if name:
        return name
    source = build.get("source", {})
    repo = source.get("repoSource", {}).get("repoName")
    if repo:
        return repo
    if source.get("storageSource"):
        return "manual submit"
    return "build"


def _blocks(build):
    status = build["status"]
    emoji, verb = TERMINAL[status]
    what = _describe(build)

    line = "%s *%s* %s" % (emoji, what, verb)

    context = []
    subs = build.get("substitutions", {})
    sha = subs.get("SHORT_SHA") or subs.get("COMMIT_SHA", "")[:7]
    if sha:
        context.append("`%s`" % sha)
    if subs.get("BRANCH_NAME"):
        context.append(subs["BRANCH_NAME"])
    took = _duration(build)
    if took:
        context.append("took %s" % took)
    if context:
        line += "  ·  " + "  ·  ".join(context)

    blocks = [{"type": "section", "text": {"type": "mrkdwn", "text": line}}]

    # A failure is only actionable with the log, and the failing step is the
    # first thing anyone asks for.
    if status != "SUCCESS":
        failed = [
            s.get("id") or s.get("name", "?")
            for s in build.get("steps", [])
            if s.get("status") in ("FAILURE", "INTERNAL_ERROR", "TIMEOUT")
        ]
        detail = []
        if failed:
            detail.append("failed at: %s" % ", ".join(failed))
        if build.get("logUrl"):
            detail.append("<%s|open logs>" % build["logUrl"])
        if detail:
            blocks.append(
                {
                    "type": "context",
                    "elements": [{"type": "mrkdwn", "text": "  ·  ".join(detail)}],
                }
            )

    return line, blocks


def _post(channel, token, text, blocks):
    payload = json.dumps(
        {"channel": channel, "text": text, "blocks": blocks}
    ).encode("utf-8")
    req = urllib.request.Request(
        SLACK_API,
        data=payload,
        headers={
            "Authorization": "Bearer %s" % token,
            "Content-Type": "application/json; charset=utf-8",
        },
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        body = json.load(resp)

    # Slack answers 200 with ok:false for application errors, so the HTTP status
    # alone proves nothing.
    if not body.get("ok"):
        raise RuntimeError("Slack rejected the message: %s" % body.get("error"))


@functions_framework.cloud_event
def notify(event):
    build = json.loads(base64.b64decode(event.data["message"]["data"]))

    status = build.get("status")
    if status not in TERMINAL:
        return

    channel = os.environ["SLACK_CHANNEL"]
    token = os.environ["SLACK_BOT_TOKEN"]

    text, blocks = _blocks(build)
    _post(channel, token, text, blocks)
