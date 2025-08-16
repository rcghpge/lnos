import os
import re

# Parser
URL_FROM = r"https://github.com/uta-lug-nuts/LnOS"
URL_TO = r"https://github.com/rcghpge/lnos"
CD_PATTERN = r"\bcd\s+LnOS\b"
CD_REPLACEMENT = r"cd lnos"
LNOS_WORD_PATTERN = r"\bLnOS\b"
LNOS_WORD_REPLACEMENT = "lnos"

# File extensions
FILE_EXTS = {".md", ".sh", ".txt", ".yml", ".yaml"}

# Files to exclude (relative to repo root)
EXCLUDE_FILES = {
    ".github/workflows/ci-main.yml",
}

def write_in_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    original = content
    content = re.sub(URL_FROM + r"\.git", URL_TO + ".git", content)
    content = re.sub(URL_FROM, URL_TO, content)
    content = re.sub(CD_PATTERN, CD_REPLACEMENT, content)
    content = re.sub(LNOS_WORD_PATTERN, LNOS_WORD_REPLACEMENT, content)

    if content != original:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"✔️  Updated: {filepath}")

def parse_repo():
    for root, _, files in os.walk("."):
        for file in files:
            filepath = os.path.join(root, file)
            relpath = os.path.relpath(filepath).replace("\\", "/")
            if relpath in EXCLUDE_FILES:
                continue
            if any(file.endswith(ext) for ext in FILE_EXTS):
                write_in_file(filepath)

if __name__ == "__main__":
    parse_repo()

