# Quick word frequency counter for checking note corpus coverage
# Grabbed from a Stack Overflow answer and tweaked

import sys
from collections import Counter
from pathlib import Path

def count_words(directory, ext="*.org"):
    words = Counter()
    for f in Path(directory).glob(ext):
        words.update(f.read_text().lower().split())
    return words

if __name__ == "__main__":
    d = sys.argv[1] if len(sys.argv) > 1 else "."
    for word, count in count_words(d).most_common(30):
        print(f"{count:5d}  {word}")
