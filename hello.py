#!/usr/bin/env python3
"""
hello.py — a deliberately tiny Python application.

The point of this project isn't the code (it's one function), it's the
CI/CD pipeline wrapped around it: tests, multi-format container builds
(Docker + Apptainer/Singularity), vulnerability scanning, registry
publishing, remote deployment via SSH, and a PyPI release pipeline.

numpy is used here on purpose so the built container images have a
real (small) third-party dependency to install and scan.
"""
from __future__ import annotations

import platform
import sys

import numpy as np


def greeting(name: str = "World") -> str:
    """Return a friendly greeting."""
    return f"Hello, {name}!"


def compute_demo_stats(size: int = 10) -> dict:
    """
    Do a trivial bit of numpy work so the dependency is exercised
    at runtime, not just installed and ignored.
    """
    arr = np.arange(1, size + 1, dtype=float)
    return {
        "size": size,
        "sum": float(np.sum(arr)),
        "mean": float(np.mean(arr)),
        "std": float(np.std(arr)),
    }


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    name = argv[0] if argv else "World"

    print(greeting(name))
    print(f"Python version : {platform.python_version()}")
    print(f"numpy version  : {np.__version__}")

    stats = compute_demo_stats()
    print(f"Demo numpy stats over 1..{stats['size']}: "
          f"sum={stats['sum']}, mean={stats['mean']}, std={stats['std']:.4f}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
