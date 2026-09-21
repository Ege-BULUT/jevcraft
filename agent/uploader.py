# /// script
# requires-python = ">=3.10"
# dependencies = ["huggingface_hub>=0.34"]
# ///
"""Uploads finished recorder segments to the public Hugging Face dataset, then deletes them.

    uv run --script agent/uploader.py <segments-dir> <hf-repo-id>

The HF token is read from the macOS keychain (service "hf-token", account "jevcraft"), never from
a file or an argument. Without network the upload fails, the segment stays on disk and is retried;
the recorder stops recording before the backlog can fill the disk.
"""

import subprocess
import sys
import time
from pathlib import Path

from huggingface_hub import HfApi

CARD = """---
license: cc-by-sa-4.0
tags: [video, game, voxelibre, luanti, agents]
pretty_name: JevCraft gameplay
---

# JevCraft gameplay

Screen recordings of TypeSafe's Jev model playing [VoxeLibre](https://content.luanti.org/packages/wuzzy/mineclone2/)
(a free game in the style of Minecraft, not affiliated with Mojang or Microsoft) on the
[Luanti](https://www.luanti.org/) engine, live and unattended, from 21 to 25 September 2026.

- `videos/YYYY-MM-DD/<UTC start>.mp4`: 10-minute segments, 1280x720, 30 fps, H.264, game window only.
  A gap between segments means the game was paused (the machine was offline or asleep).

VoxeLibre's art is licensed CC BY-SA 4.0 and its code GPLv3; these recordings are shared under
CC BY-SA 4.0 accordingly. Watch it with Jev's decisions at https://jevcraft.vercel.app.
"""


def token() -> str:
    return subprocess.run(
        ["security", "find-generic-password", "-a", "jevcraft", "-s", "hf-token", "-w"],
        check=True, capture_output=True, text=True,
    ).stdout.strip()


def main(segments: Path, repo: str) -> None:
    api = HfApi(token=token())
    api.create_repo(repo, repo_type="dataset", exist_ok=True)
    api.upload_file(path_or_fileobj=CARD.encode(), path_in_repo="README.md", repo_id=repo, repo_type="dataset")
    while True:
        for seg in sorted(segments.glob("*.mp4")):
            day = seg.name[:10]  # names start with the UTC start time, 2026-09-21T083543Z
            try:
                api.upload_file(path_or_fileobj=str(seg), path_in_repo=f"videos/{day}/{seg.name}",
                                repo_id=repo, repo_type="dataset", commit_message=f"Add {seg.name}")
            except Exception as e:  # offline, rate limited, HF hiccup: keep the file, retry later
                print(f"[uploader] {seg.name} not uploaded yet: {e}", flush=True)
                break
            seg.unlink()
            print(f"[uploader] uploaded and removed {seg.name}", flush=True)
        time.sleep(15)


if __name__ == "__main__":
    main(Path(sys.argv[1]), sys.argv[2])
