"""Dasha News newsroom backend.

A modular AI-newsroom pipeline (ingestion -> publishing) plus the versioned
API that the Dasha News Flutter application talks to.

The whole stack runs with zero paid credentials: SQLite by default and a
deterministic heuristic "AI" provider. External LLMs (Ollama, or any
OpenAI-compatible endpoint) can be switched on via configuration without
touching pipeline code.
"""

__version__ = "1.0.0"
__all__ = ["__version__"]
