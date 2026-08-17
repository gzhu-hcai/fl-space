"""Run a controlled FedLEO experiment designed to trigger real offloading."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from fl_space.fedleo.experiment import run_fedleo_experiment


def _checks(history: list[dict[str, Any]]) -> dict[str, Any]:
    scheduled = [row for row in history if row.get("round", 0) > 0]
    action_rounds = [row for row in scheduled if row.get("num_offload_actions", 0) > 0]
    totals = [sum(row.get("data_sizes", [])) for row in history]
    return {
        "action_rounds": [row["round"] for row in action_rounds],
        "action_round_count": len(action_rounds),
        "total_offloaded": sum(row.get("total_offloaded_samples", 0) for row in history),
        "sample_totals": totals,
        "samples_conserved": bool(totals) and len(set(totals)) == 1,
        "offload_delay_positive": any(row.get("offload_delay", 0) > 0 for row in history),
        "actions_have_payload": all(
            action.get("offload_samples", 0) > 0
            for row in action_rounds
            for action in row.get("offload_actions", [])
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        default="experiments/validation_results/fedleo_triggered_offloading",
    )
    parser.add_argument("--seed", type=int, default=20260816)
    args = parser.parse_args()

    common = {
        "num_planes": 2,
        "sats_per_plane": 2,
        "num_rounds": 8,
        "local_epochs": 1,
        "batch_size": 64,
        "learning_rate": 0.02,
        "dataset": "mnist",
        "data_dir": "./data",
        "device": "cpu",
        "offload_every_n_rounds": 1,
        "max_offload_iter": 10,
        "bandwidth_mbps": 1000.0,
        "bytes_per_sample": 784,
        "timeslot_duration_sec": 60.0,
        "discrete_ratios": [0.0, 0.25, 0.5, 0.75],
        "delay_weight": 1.0,
        "divergence_weight": 5.0,
        "comm_cost_weight": 0.0,
        "eval_every_n_rounds": 1,
        "classes_per_client": 1,
        "max_samples_per_client": 300,
        "sample_imbalance": 0.95,
        "seed": args.seed,
        "verbose": False,
    }
    output = Path(args.output)
    on = run_fedleo_experiment(
        **common,
        enable_offloading=True,
        output_dir=str(output / "offload_on"),
    )
    off = run_fedleo_experiment(
        **common,
        enable_offloading=False,
        output_dir=str(output / "offload_off"),
    )

    on_checks = _checks(on.history)
    off_checks = _checks(off.history)
    initial_on = on.history[0].get("data_sizes", [])
    initial_off = off.history[0].get("data_sizes", [])
    gates = {
        "same_initial_partition": initial_on == initial_off,
        "on_has_multiple_action_rounds": on_checks["action_round_count"] >= 2,
        "off_control_has_no_actions": off_checks["total_offloaded"] == 0,
        "on_has_payloads": on_checks["actions_have_payload"],
        "on_samples_conserved": on_checks["samples_conserved"],
        "off_samples_conserved": off_checks["samples_conserved"],
        "on_delay_accounted": on_checks["offload_delay_positive"],
        "balance_improved": (
            on.history[-1].get("data_balance_entropy", 0)
            > off.history[-1].get("data_balance_entropy", 0)
        ),
    }
    summary = {
        "experiment": "FedLEO triggered offloading on/off control",
        "config": common,
        "offload_on": {"checks": on_checks, "history": on.history},
        "offload_off": {"checks": off_checks, "history": off.history},
        "gates": gates,
        "passed": all(gates.values()),
    }
    output.mkdir(parents=True, exist_ok=True)
    (output / "validation_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(json.dumps({"gates": gates, "passed": summary["passed"]}, ensure_ascii=False, indent=2))
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
