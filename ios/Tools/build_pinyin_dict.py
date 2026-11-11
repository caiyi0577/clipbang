#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成剪贴炸键盘用的拼音词库二进制资源。

数据来源（均为 MIT License，见 Resources/Pinyin/LICENSES.txt）：
  - fxsjy/jieba            jieba/dict.txt        中文词表 + 词频
  - mozillazg/pinyin-data  pinyin.txt            单字全部读音（含多音字）
  - pypinyin               phrases_dict.py       词组级正确读音（重庆/银行/音乐等）

输出 PYD1 格式（两个文件同构）：
  header  16B : magic 'PYD1' | count:u32le | version:u32le | reserved:u32le
  offsets     : count * u32le，每条记录相对文件头的字节偏移
  records     : keyLen:u8 | key(ASCII) | wordLen:u8 | word(UTF-8) | score:u16le
  记录按 key 字节序升序，同 key 内按 score 降序。

运行时用 Data(contentsOf:options:.mappedIfSafe) 映射，二分定位前缀起点，
顺序扫描一段后按词频取 top N，内存占用近似为零。
"""

from __future__ import annotations

import argparse
import math
import re
import struct
import sys
import unicodedata
from array import array
from pathlib import Path

from pypinyin.phrases_dict import phrases_dict

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SRC = Path(r"C:\Temp\clipbang\dictsrc")

TONE_PRE = str.maketrans({
    "ǖ": "v", "ǘ": "v", "ǚ": "v", "ǜ": "v", "ü": "v",
    "Ü": "V", "Ǖ": "V", "Ǘ": "V", "Ǚ": "V", "Ǜ": "V",
})


def tone_free(raw: str) -> str:
    """带声调拼音 -> 无声调 ASCII（ü 系转 v，与主流输入法一致）。"""
    s = raw.strip().lower().translate(TONE_PRE)
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.replace("ŋ", "n").replace("ê", "e")
    return "".join(c for c in s if "a" <= c <= "z")


def is_han(ch: str) -> bool:
    cp = ord(ch)
    return 0x4E00 <= cp <= 0x9FFF or 0x3400 <= cp <= 0x4DBF or cp == 0x3007


def pure_han(word: str) -> bool:
    return bool(word) and all(is_han(c) for c in word)


def score_of(freq: int) -> int:
    return max(1, min(65535, int(math.log2(freq + 1) * 3200)))


class Builder:
    def __init__(self) -> None:
        self.entries: dict[tuple[str, str], int] = {}
        self.char_pinyin: dict[str, list[str]] = {}
        self.word_pinyin: dict[str, list[str]] = {}
        self.syllables: set[str] = set()
        self.stats = {"words": 0, "skipped": 0, "chars": 0, "phrases": 0}

    def add(self, key: str, word: str, score: int) -> None:
        if not key or not word or len(key) > 40:
            return
        if not key.isascii() or not key.isalpha():
            return
        k = (key, word)
        old = self.entries.get(k)
        if old is None or score > old:
            self.entries[k] = score

    # ---------- 读音表 ----------

    def load_pinyin_txt(self, path: Path) -> None:
        pat = re.compile(r"^U\+([0-9A-Fa-f]+):\s*([^#]+?)\s*(?:#.*)?$")
        with path.open(encoding="utf-8") as f:
            for line in f:
                if line.startswith("#") or not line.strip():
                    continue
                m = pat.match(line.rstrip("\n"))
                if not m:
                    continue
                cp = int(m.group(1), 16)
                if not (0x4E00 <= cp <= 0x9FFF or cp == 0x3007):
                    continue
                ch = chr(cp)
                readings = [tone_free(x) for x in m.group(2).split(",")]
                readings = [x for x in readings if x]
                if not readings:
                    continue
                self.char_pinyin[ch] = list(dict.fromkeys(readings))
                self.syllables.update(readings)

    def load_phrases(self) -> None:
        for phrase, parts in phrases_dict.items():
            if not pure_han(phrase) or len(phrase) > 8:
                continue
            syl = []
            for part in parts:
                if not part:
                    break
                s = tone_free(part[0])
                if not s:
                    break
                syl.append(s)
            if len(syl) == len(phrase):
                self.word_pinyin[phrase] = syl
                self.syllables.update(syl)
        self.stats["phrases"] = len(self.word_pinyin)

    def syllables_for(self, word: str) -> list[str] | None:
        cached = self.word_pinyin.get(word)
        if cached is not None:
            return cached
        out: list[str] = []
        for ch in word:
            readings = self.char_pinyin.get(ch)
            if not readings:
                return None
            out.append(readings[0])
        return out

    # ---------- 词条 ----------

    def load_jieba(self, path: Path) -> None:
        with path.open(encoding="utf-8") as f:
            for line in f:
                parts = line.rstrip("\n").split()
                if len(parts) < 2:
                    continue
                word, raw_freq = parts[0], parts[1]
                if not pure_han(word) or len(word) > 8:
                    self.stats["skipped"] += 1
                    continue
                try:
                    freq = int(raw_freq)
                except ValueError:
                    continue
                syl = self.syllables_for(word)
                if not syl:
                    self.stats["skipped"] += 1
                    continue
                self.emit(word, syl, score_of(freq))
                self.stats["words"] += 1

    def add_extra_phrases(self) -> None:
        """pypinyin 词组表里的成语等，jieba 未收录的补进来。"""
        for phrase, syl in self.word_pinyin.items():
            if (("".join(syl), phrase) in self.entries) or len(phrase) < 2:
                continue
            self.emit(phrase, syl, 26000)

    def add_single_chars(self) -> None:
        """每个常用汉字的每一种读音都生成单字候选。"""
        for ch, readings in self.char_pinyin.items():
            for idx, py in enumerate(readings):
                s = 3000 if idx else 9000
                if (py, ch) in self.entries:
                    continue
                self.add(py, ch, s)
                self.add_variants(py, ch, s)
                self.stats["chars"] += 1

    def add_variants(self, key: str, word: str, score: int) -> None:
        if "v" in key:
            self.add(key.replace("v", "u"), word, int(score * 0.8))

    def emit(self, word: str, syl: list[str], score: int) -> None:
        full = "".join(syl)
        self.syllables.update(syl)
        # 双字词略加权，符合中文输入习惯
        adj = score + 1200 if len(word) == 2 else score
        self.add(full, word, adj)
        self.add_variants(full, word, adj)
        if 2 <= len(word) <= 6:
            abbr = "".join(s[0] for s in syl if s)
            if len(abbr) >= 2:
                self.add(abbr, word, int(adj * 0.72))
                self.add_variants(abbr, word, int(adj * 0.58))

    # ---------- 输出 ----------

    def write_bin(self, path: Path, items: list[tuple[str, str, int]]) -> int:
        items.sort(key=lambda x: (x[0].encode("ascii"), -x[2], x[1]))
        records: list[bytes] = []
        for key, word, score in items:
            kb = key.encode("ascii")
            wb = word.encode("utf-8")
            if len(kb) > 255 or len(wb) > 255:
                continue
            records.append(
                bytes([len(kb)]) + kb + bytes([len(wb)]) + wb + struct.pack("<H", score)
            )
        count = len(records)
        offsets = array("I")
        cursor = 16 + 4 * count
        for rec in records:
            offsets.append(cursor)
            cursor += len(rec)
        if sys.byteorder != "little":
            offsets.byteswap()
        with path.open("wb") as f:
            f.write(b"PYD1" + struct.pack("<III", count, 1, 0))
            f.write(offsets.tobytes())
            f.write(b"".join(records))
        return count

    def write_syllables_swift(self, path: Path) -> None:
        values = sorted(self.syllables)
        lines = [
            "// 自动生成，勿手改。由 ios/Tools/build_pinyin_dict.py 生成。",
            "import Foundation",
            "",
            "enum PinyinSyllables {",
            "    static let all: Set<String> = [",
        ]
        for i in range(0, len(values), 8):
            chunk = ", ".join('"%s"' % v for v in values[i:i + 8])
            lines.append("        " + chunk + ",")
        lines += ["    ]", "}", ""]
        path.write_text("\n".join(lines), encoding="utf-8")

    def build(self, src: Path, resources: Path, swift_out: Path) -> None:
        self.load_pinyin_txt(src / "pinyin.txt")
        self.load_phrases()
        self.load_jieba(src / "jieba_dict.txt")
        self.add_extra_phrases()
        self.add_single_chars()

        items = [(k, w, s) for (k, w), s in self.entries.items()]
        full_count = self.write_bin(resources / "pinyin_full.bin", list(items))

        hot = sorted(self.entries.items(), key=lambda kv: -kv[1])[:40000]
        hot_items = [(k, w, s) for (k, w), s in hot]
        hot_count = self.write_bin(resources / "pinyin_hot.bin", hot_items)

        self.write_syllables_swift(swift_out)

        print("词条(jieba)      :", self.stats["words"])
        print("词组读音(pypinyin):", self.stats["phrases"])
        print("单字读音条目     :", self.stats["chars"])
        print("过滤掉的非汉字行 :", self.stats["skipped"])
        print("全量条目         :", full_count, (resources / "pinyin_full.bin").stat().st_size, "bytes")
        print("高频条目         :", hot_count, (resources / "pinyin_hot.bin").stat().st_size, "bytes")
        print("音节数           :", len(self.syllables))

        # 自检：用与 Swift 端相同的「排序后前缀扫描」逻辑验证常见输入
        ordered = sorted(items, key=lambda x: (x[0].encode("ascii"), -x[2], x[1]))
        keys = [x[0] for x in ordered]
        import bisect
        for q in ["ni", "nihao", "chongqing", "yinhang", "nh", "zg", "zhongguo",
                  "wo", "nv", "nu", "yinyue", "zhangda", "dajia", "xiexie"]:
            lo = bisect.bisect_left(keys, q)
            hits = [(w, s) for k, w, s in ordered[lo:lo + 12000] if k.startswith(q)][:8]
            print("  %-10s -> %s" % (q, " ".join(w for w, _ in hits) or "(无)"))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", type=Path, default=DEFAULT_SRC)
    args = ap.parse_args()
    b = Builder()
    b.build(args.src, ROOT / "Resources" / "Pinyin", ROOT / "Sources" / "Keyboard" / "PinyinSyllables.swift")


if __name__ == "__main__":
    main()
