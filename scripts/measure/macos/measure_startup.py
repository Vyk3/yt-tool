#!/usr/bin/env python3
"""Measure packaged macOS app startup timings for yt-tool."""
from __future__ import annotations

import argparse
import os
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path


READY_VALUES = {"✓ 就绪", "✓ 基本就绪"}
TRACE_LINE_RE = re.compile(r"^\[startup \+([0-9.]+)s\] (.+)$")


def run_osascript(script: str, *args: str) -> str:
    result = subprocess.run(
        ["osascript", "-e", script, *args],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def close_app(process_name: str) -> None:
    run_osascript(f'tell application "{process_name}" to quit')
    subprocess.run(["pkill", "-x", process_name], check=False, capture_output=True, text=True)


def wait_until_gone(process_name: str, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not run_osascript(
            f'tell application "System Events" to tell process "{process_name}" to get count of windows'
        ):
            return
        time.sleep(0.1)


def app_window_count(process_name: str) -> int:
    output = run_osascript(
        f'tell application "System Events" to tell process "{process_name}" to get count of windows'
    )
    if not output:
        return 0
    try:
        return int(output)
    except ValueError:
        return 0


def app_ready_value(process_name: str) -> str:
    # This path matches the current pywebview accessibility tree:
    # window -> group -> group -> scroll area -> web area -> UI element 21 (env status)
    script = f"""
on run
    tell application "System Events" to tell process "{process_name}"
        try
            return value of UI element 21 of UI element 1 of UI element 1 of UI element 1 of UI element 1 of window 1
        on error
            return ""
        end try
    end tell
end run
"""
    return run_osascript(script)


def bundle_binary_path(app_path: Path, process_name: str) -> Path:
    candidates = [app_path / "Contents" / "MacOS" / process_name, app_path / "Contents" / "MacOS" / app_path.stem]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    raise FileNotFoundError(f"Could not locate bundle binary under {app_path / 'Contents' / 'MacOS'}")


def parse_trace_output(output: str) -> list[tuple[str, float]]:
    events: list[tuple[str, float]] = []
    for line in output.splitlines():
        match = TRACE_LINE_RE.match(line.strip())
        if match:
            events.append((match.group(2), float(match.group(1))))
    return events


def summarize_trace_samples(samples: list[dict[str, object]]) -> dict[str, dict[str, float]]:
    event_to_values: dict[str, list[float]] = {}
    for sample in samples:
        for event, elapsed in sample.get("trace_events", []):  # type: ignore[assignment]
            event_to_values.setdefault(event, []).append(float(elapsed))
    return {
        event: {
            "min": min(values),
            "median": statistics.median(values),
            "mean": statistics.mean(values),
            "max": max(values),
        }
        for event, values in event_to_values.items()
    }


def sample_once(
    app_path: Path,
    process_name: str,
    timeout: float,
    interval: float,
    *,
    launcher: str,
    capture_trace: bool,
) -> dict[str, object]:
    close_app(process_name)
    wait_until_gone(process_name, timeout=3.0)

    started_at = time.monotonic()
    proc: subprocess.Popen[str] | None = None
    if launcher == "binary":
        env = os.environ.copy()
        if capture_trace:
            env["YT_TOOL_STARTUP_TRACE"] = "1"
        proc = subprocess.Popen(
            [str(bundle_binary_path(app_path, process_name))],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )
    else:
        subprocess.run(["open", "-n", str(app_path)], check=True)

    window_visible_at: float | None = None
    ready_at: float | None = None
    deadline = started_at + timeout

    while time.monotonic() < deadline:
        now = time.monotonic()
        if window_visible_at is None and app_window_count(process_name) > 0:
            window_visible_at = now
        if window_visible_at is not None:
            ready_value = app_ready_value(process_name)
            if ready_value in READY_VALUES:
                ready_at = now
                break
        time.sleep(interval)

    if window_visible_at is None:
        raise TimeoutError(f"Timed out waiting for first window from {process_name}")
    if ready_at is None:
        raise TimeoutError(f"Timed out waiting for ready state from {process_name}")

    result: dict[str, object] = {
        "window_visible_s": window_visible_at - started_at,
        "ready_s": ready_at - started_at,
        "ready_after_window_s": ready_at - window_visible_at,
    }
    close_app(process_name)
    wait_until_gone(process_name, timeout=3.0)

    if proc is not None:
        try:
            _, stderr = proc.communicate(timeout=5.0)
        except subprocess.TimeoutExpired:
            proc.kill()
            _, stderr = proc.communicate(timeout=5.0)
        trace_events = parse_trace_output(stderr)
        result["trace_events"] = trace_events
        result["trace_output"] = stderr

    return result


def summarize(samples: list[dict[str, float]]) -> dict[str, dict[str, float]]:
    keys = ("window_visible_s", "ready_s", "ready_after_window_s")
    return {
        key: {
            "min": min(sample[key] for sample in samples),
            "median": statistics.median(sample[key] for sample in samples),
            "mean": statistics.mean(sample[key] for sample in samples),
            "max": max(sample[key] for sample in samples),
        }
        for key in keys
    }


def run_measurements(
    *,
    app_path: Path,
    process_name: str,
    iterations: int,
    timeout: float,
    interval: float,
    launcher: str,
    capture_trace: bool,
) -> tuple[list[dict[str, object]], dict[str, dict[str, float]], dict[str, dict[str, float]]]:
    samples: list[dict[str, object]] = []
    try:
        for idx in range(1, iterations + 1):
            sample = sample_once(
                app_path=app_path,
                process_name=process_name,
                timeout=timeout,
                interval=interval,
                launcher=launcher,
                capture_trace=capture_trace,
            )
            samples.append(sample)
            print(
                f"sample {idx}: "
                f"window={sample['window_visible_s']:.3f}s, "
                f"ready={sample['ready_s']:.3f}s, "
                f"window->ready={sample['ready_after_window_s']:.3f}s"
            )
            if sample.get("trace_events"):
                print("  trace:")
                for event, elapsed in sample["trace_events"]:  # type: ignore[index]
                    print(f"    {elapsed:.3f}s  {event}")
    finally:
        close_app(process_name)

    summary = summarize(samples)  # type: ignore[arg-type]
    trace_summary = summarize_trace_samples(samples) if capture_trace else {}
    return samples, summary, trace_summary


def print_summary(
    summary: dict[str, dict[str, float]],
    trace_summary: dict[str, dict[str, float]],
) -> None:
    print("\nsummary:")
    for key, stats in summary.items():
        print(
            f"  {key}: "
            f"min={stats['min']:.3f}s, "
            f"median={stats['median']:.3f}s, "
            f"mean={stats['mean']:.3f}s, "
            f"max={stats['max']:.3f}s"
        )
    if trace_summary:
        print("\ntrace summary:")
        for event, stats in trace_summary.items():
            print(
                f"  {event}: "
                f"min={stats['min']:.3f}s, "
                f"median={stats['median']:.3f}s, "
                f"mean={stats['mean']:.3f}s, "
                f"max={stats['max']:.3f}s"
            )


def main() -> int:
    parser = argparse.ArgumentParser(description="Measure packaged macOS app startup timings.")
    parser.add_argument("--app", default="dist/yt-tool.app", help="Path to .app bundle")
    parser.add_argument("--process-name", default="yt-tool", help="macOS process name to probe")
    parser.add_argument("--iterations", type=int, default=3, help="Number of samples to capture")
    parser.add_argument("--timeout", type=float, default=30.0, help="Per-sample timeout in seconds")
    parser.add_argument("--interval", type=float, default=0.1, help="Polling interval in seconds")
    parser.add_argument("--launcher", choices=("open", "binary"), default="open", help="How to launch the app")
    parser.add_argument("--capture-trace", action="store_true", help="Launch bundle binary with YT_TOOL_STARTUP_TRACE=1")
    parser.add_argument(
        "--compare-launchers",
        action="store_true",
        help="Run both open and binary launch modes back-to-back and print a comparison",
    )
    args = parser.parse_args()

    app_path = Path(args.app).resolve()
    if not app_path.exists():
        print(f"App not found: {app_path}", file=sys.stderr)
        return 2

    launcher = args.launcher
    if args.capture_trace and launcher == "open":
        launcher = "binary"
        print("capture-trace requested: switching launcher to binary", file=sys.stderr)

    if args.compare_launchers:
        print("== open launcher ==")
        _, open_summary, _ = run_measurements(
            app_path=app_path,
            process_name=args.process_name,
            iterations=args.iterations,
            timeout=args.timeout,
            interval=args.interval,
            launcher="open",
            capture_trace=False,
        )
        print_summary(open_summary, {})
        print("\n== binary launcher ==")
        _, binary_summary, binary_trace_summary = run_measurements(
            app_path=app_path,
            process_name=args.process_name,
            iterations=args.iterations,
            timeout=args.timeout,
            interval=args.interval,
            launcher="binary",
            capture_trace=True,
        )
        print_summary(binary_summary, binary_trace_summary)
        print("\ncomparison:")
        for key in ("window_visible_s", "ready_s", "ready_after_window_s"):
            print(
                f"  {key}: "
                f"open_median={open_summary[key]['median']:.3f}s, "
                f"binary_median={binary_summary[key]['median']:.3f}s, "
                f"delta={binary_summary[key]['median'] - open_summary[key]['median']:.3f}s"
            )
        return 0

    _, summary, trace_summary = run_measurements(
        app_path=app_path,
        process_name=args.process_name,
        iterations=args.iterations,
        timeout=args.timeout,
        interval=args.interval,
        launcher=launcher,
        capture_trace=args.capture_trace,
    )
    print_summary(summary, trace_summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
