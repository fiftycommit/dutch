"""Gestion du sous-process runner Dutch'78 (binaire COMPILÉ) via NDJSON.

On pilote l'exécutable compilé `tool/rl_env_runner` (jamais `dart run`, qui pollue
stdout avec « Running build hooks… »). Protocole : un objet JSON par ligne sur
stdin/stdout. Voir documentation/RL_RUNNER.md.

Pièges adressés ici :
- lecture via ``readline()`` (jamais ``for line in proc.stdout`` : read-ahead
  bufferisé → deadlock) ;
- timeout via ``select`` avant chaque lecture (pas de blocage infini) ;
- robustesse : relance du process mort au ``reset``.
"""

from __future__ import annotations

import json
import select
import subprocess
from pathlib import Path
from typing import Any

# Racine repo = parent de rl/ ; binaire compilé attendu dans tool/.
_REPO_ROOT = Path(__file__).resolve().parent.parent
_DEFAULT_EXE = _REPO_ROOT / "tool" / "rl_env_runner"


class RunnerError(RuntimeError):
    """Erreur générique du runner."""


class RunnerCrashed(RunnerError):
    """Le sous-process s'est terminé / a fermé stdout (EOF)."""


class RunnerTimeout(RunnerError):
    """Aucune réponse du sous-process dans le délai imparti."""


class RunnerProcess:
    """Pilote un sous-process runner et échange des messages NDJSON."""

    def __init__(
        self,
        exe_path: str | Path = _DEFAULT_EXE,
        *,
        max_turns: int = 500,
        timeout: float = 30.0,
        debug: bool = False,
        _extra_args: list[str] | None = None,
    ) -> None:
        self.exe_path = Path(exe_path)
        self.max_turns = max_turns
        self.timeout = timeout
        self.debug = debug
        self._extra_args = _extra_args  # tests : permet de cibler un faux binaire
        self.proc: subprocess.Popen[str] | None = None
        if self._extra_args is None and not self.exe_path.exists():
            raise RunnerError(
                f"Binaire runner introuvable : {self.exe_path}\n"
                "Compile-le d'abord :\n"
                "  dart compile exe tool/rl_env_runner.dart -o tool/rl_env_runner"
            )

    # ── Cycle de vie du process ────────────────────────────────────────────

    def _launch(self) -> None:
        self.close(quiet=True)
        if self._extra_args is not None:
            argv = list(self._extra_args)
        else:
            argv = [str(self.exe_path), f"--max-turns={self.max_turns}"]
            if self.debug:
                argv.append("--debug")
        self.proc = subprocess.Popen(
            argv,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            bufsize=1,
        )

    def _alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def _ensure_alive(self) -> None:
        if not self._alive():
            self._launch()

    # ── E/S NDJSON ─────────────────────────────────────────────────────────

    def _send(self, msg: dict[str, Any]) -> None:
        assert self.proc is not None and self.proc.stdin is not None
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()

    def _recv(self) -> dict[str, Any]:
        assert self.proc is not None and self.proc.stdout is not None
        stdout = self.proc.stdout
        while True:
            ready, _, _ = select.select([stdout], [], [], self.timeout)
            if not ready:
                self.close(quiet=True)
                raise RunnerTimeout(
                    f"aucune réponse du runner en {self.timeout}s"
                )
            line = stdout.readline()  # JAMAIS `for line in stdout`
            if line == "":
                self.close(quiet=True)
                raise RunnerCrashed("le runner a fermé stdout (EOF)")
            line = line.strip()
            if not line:
                continue
            i = line.find("{")  # tolère un éventuel préfixe non-JSON
            if i < 0:
                continue
            try:
                return json.loads(line[i:])
            except json.JSONDecodeError:
                continue

    # ── API haut niveau ────────────────────────────────────────────────────

    def reset(self, seed: int, episode_id: str | None = None) -> dict[str, Any]:
        """(Re)démarre un épisode. Relance le process s'il est mort."""
        self._ensure_alive()
        self._send(
            {
                "type": "reset",
                "seed": int(seed),
                "episode_id": episode_id or f"ep{seed}",
                "options": {"max_turns": self.max_turns},
            }
        )
        return self._recv()

    def step(self, action_msg: dict[str, Any]) -> dict[str, Any]:
        """Envoie une action et renvoie l'observation/terminal/erreur."""
        if not self._alive():
            raise RunnerCrashed("step appelé sur un process mort (reset requis)")
        self._send({"type": "action", **action_msg})
        return self._recv()

    def close(self, quiet: bool = False) -> None:
        if self.proc is None:
            return
        try:
            if self.proc.poll() is None and self.proc.stdin is not None:
                try:
                    self.proc.stdin.write(json.dumps({"type": "close"}) + "\n")
                    self.proc.stdin.flush()
                except (BrokenPipeError, ValueError):
                    pass
            try:
                self.proc.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=2.0)
        except Exception:
            if not quiet:
                raise
        finally:
            self.proc = None

    def __enter__(self) -> "RunnerProcess":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close(quiet=True)
