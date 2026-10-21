#!/usr/bin/env python3
"""Build character-trigram language models from frequency word lists.

Usage: build_ngram.py <corpus_dir> <out_dir> [--tune]

Input:  <corpus_dir>/<lang>_50k.txt  (hermitdave/FrequencyWords: "word count" per line)
Output: <out_dir>/ngram-<lang>.bin   (see FORMAT below)

FORMAT (little endian):
  magic   4 bytes  "NGM1"
  N       uint16   alphabet size (letters only; index 0 is the word boundary)
  alpha   N UTF-8 code points, each as uint32
  table   (N+1)^3 bytes: quantized -log2 p(c | a b) * 8, clipped to 255;
          index = (a*(N+1) + b)*(N+1) + c, where 0 = boundary, k = alpha[k-1]
"""
import math, os, struct, sys, random

ALPHABETS = {
    "ru": "абвгдежзийклмнопрстуфхцчшщъыьэюяё",
    "en": "abcdefghijklmnopqrstuvwxyz",
    "uk": "абвгґдеєжзиіїйклмнопрстуфхцчшщьюя'",
    "de": "abcdefghijklmnopqrstuvwxyzäöüß",
}
SMOOTH = 0.05
QUANT = 8.0  # fixed-point scale for -log2 p

def load_words(path, alphabet):
    allowed = set(alphabet)
    words = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) != 2:
                continue
            w, c = parts[0].lower(), int(parts[1])
            if len(w) < 2 or any(ch not in allowed for ch in w):
                continue
            words.append((w, c))
    return words

class Model:
    def __init__(self, alphabet):
        self.alpha = alphabet
        self.idx = {ch: i + 1 for i, ch in enumerate(alphabet)}
        self.n = len(alphabet) + 1
        self.counts = {}
        self.ctx = {}

    def train(self, words):
        for w, c in words:
            weight = math.log2(1 + c)
            seq = [0, 0] + [self.idx[ch] for ch in w] + [0]
            for i in range(2, len(seq)):
                key = (seq[i - 2], seq[i - 1], seq[i])
                self.counts[key] = self.counts.get(key, 0.0) + weight
                self.ctx[(seq[i - 2], seq[i - 1])] = self.ctx.get((seq[i - 2], seq[i - 1]), 0.0) + weight

    def logp(self, a, b, c):
        num = self.counts.get((a, b, c), 0.0) + SMOOTH
        den = self.ctx.get((a, b), 0.0) + SMOOTH * self.n
        return math.log2(num / den)

    def table(self):
        n = self.n
        out = bytearray(n * n * n)
        for a in range(n):
            for b in range(n):
                for c in range(n):
                    q = int(round(-self.logp(a, b, c) * QUANT))
                    out[(a * n + b) * n + c] = min(255, max(0, q))
        return bytes(out)

    def score(self, word, table=None):
        """Mean log2 p per transition, using the quantized table if given (mirrors Swift)."""
        seq = [0, 0]
        for ch in word.lower():
            i = self.idx.get(ch)
            if i is None:
                return -16.0  # unknown character: the word is not in this language
            seq.append(i)
        seq.append(0)
        total = 0.0
        for i in range(2, len(seq)):
            if table is None:
                total += self.logp(seq[i - 2], seq[i - 1], seq[i])
            else:
                n = self.n
                total -= table[(seq[i - 2] * n + seq[i - 1]) * n + seq[i]] / QUANT
        return total / (len(seq) - 2)

def write_model(path, model, table):
    with open(path, "wb") as f:
        f.write(b"NGM1")
        f.write(struct.pack("<H", len(model.alpha)))
        for ch in model.alpha:
            f.write(struct.pack("<I", ord(ch)))
        f.write(table)

# Static RU<->EN key table from the app (for simulating wrong-layout typing).
RU2EN = dict(zip("йцукенгшщзхъфывапролджэячсмитьбю.ё", "qwertyuiop[]asdfghjkl;'zxcvbnm,./`"))
EN2RU = {v: k for k, v in RU2EN.items()}

def convert(word, mapping):
    return "".join(mapping.get(ch, ch) for ch in word)

def tune(models, tables, words):
    random.seed(7)
    ru_test = [w for w, _ in words["ru"][2000:40000] if len(w) >= 3]
    en_test = [w for w, _ in words["en"][2000:40000] if len(w) >= 3]
    ru_test = random.sample(ru_test, 4000)
    en_test = random.sample(en_test, 4000)
    ru, en = models["ru"], models["en"]
    tru, ten = tables["ru"], tables["en"]

    # delta = score(converted, other model) - score(typed, current model)
    def delta(typed, cur, cur_t, other, other_t, mapping):
        conv = convert(typed, mapping)
        return other.score(conv, other_t) - cur.score(typed, cur_t)

    # Correct typing (should not trigger): Russian layout active, Russian word.
    fp_ru = [delta(w, ru, tru, en, ten, RU2EN) for w in ru_test]
    fp_en = [delta(w, en, ten, ru, tru, EN2RU) for w in en_test]
    # Wrong layout: Russian word typed while EN layout active -> looks like "ghbdtn".
    tp_ru = [delta(convert(w, RU2EN), en, ten, ru, tru, EN2RU) for w in ru_test]
    tp_en = [delta(convert(w, EN2RU), ru, tru, en, ten, RU2EN) for w in en_test]

    print("threshold  FPR_ru  FPR_en  recall_ru  recall_en")
    for th in [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]:
        f = lambda xs: sum(1 for d in xs if d > th) / len(xs)
        print(f"{th:8.1f}  {f(fp_ru):6.3%} {f(fp_en):6.3%}   {f(tp_ru):6.1%}    {f(tp_en):6.1%}")

def main():
    corpus, out = sys.argv[1], sys.argv[2]
    do_tune = "--tune" in sys.argv
    os.makedirs(out, exist_ok=True)
    models, tables, words = {}, {}, {}
    for lang, alphabet in ALPHABETS.items():
        path = os.path.join(corpus, f"{lang}_50k.txt")
        if not os.path.exists(path):
            continue
        ws = load_words(path, alphabet)
        words[lang] = ws
        train = ws if not do_tune else [w for i, w in enumerate(ws) if not (2000 <= i < 40000) or i % 3 != 0]
        m = Model(alphabet)
        m.train(train)
        t = m.table()
        models[lang], tables[lang] = m, t
        write_model(os.path.join(out, f"ngram-{lang}.bin"), m, t)
        print(f"{lang}: {len(ws)} words, alphabet {len(alphabet)}, table {len(t)} bytes")
    if do_tune and "ru" in models and "en" in models:
        # For tuning, the held-out test words must be excluded from training:
        words_held = {l: [w for i, w in enumerate(words[l]) if 2000 <= i < 40000 and i % 3 == 0] for l in ("ru", "en")}
        tune(models, tables, {l: [(0, 0)] * 2000 + words_held[l] for l in ("ru", "en")})

if __name__ == "__main__":
    main()
