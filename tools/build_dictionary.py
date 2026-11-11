#!/usr/bin/env python3
"""RinhaBoard の かな漢字辞書 (Keyboard/Data/kana-kanji.tsv) を生成する。

元データ: Mozc の辞書 dictionary_oss (dictionary00.txt 〜 dictionary09.txt)
  https://github.com/google/mozc  (src/data/dictionary_oss/)
各行: 読み <TAB> 左ID <TAB> 右ID <TAB> コスト <TAB> 表層形

生成ルール:
- 読みが ひらがな(+ー・) で 1〜10 文字のものだけ
- 表層形は日本語文字中心のものだけ（英数字・記号混じりは除外）。
  ただし原文（読みと同じ表層形）が上位にある場合は順位情報として残す
- 読みごとにコスト昇順で最大3件、最良コスト <= 6500 の読みだけ採用
- 動詞の終止形から て形・た形 を自動生成して補う
  （Mozc 本体では活用は文法エンジン側の仕事で辞書に載っていないため）
出力: 読み <TAB> 候補1|候補2|候補3 （読みの Unicode 順にソート）
"""
import collections
import glob
import os
import sys
import urllib.request

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(BASE, "Keyboard", "Data", "kana-kanji.tsv")
CACHE = "/tmp/mozc-dict"
COST_THRESHOLD = 6500


def download():
    os.makedirs(CACHE, exist_ok=True)
    for i in range(10):
        path = os.path.join(CACHE, f"dictionary{i:02d}.txt")
        if os.path.exists(path):
            continue
        url = f"https://raw.githubusercontent.com/google/mozc/master/src/data/dictionary_oss/dictionary{i:02d}.txt"
        print("download", url)
        urllib.request.urlretrieve(url, path)


def is_kana_reading(s):
    return all(("\u3041" <= c <= "\u3096") or c in "ー・" for c in s)


def surface_ok(s, reading):
    if not s or len(s) > 12:
        return False
    if s == reading:
        return True  # 原文が上位の読みは順位を伝えるため残す
    for c in s:
        if ("\u4e00" <= c <= "\u9fff") or ("\u3041" <= c <= "\u3096") or \
           ("\u30a1" <= c <= "\u30fa") or c in "ー々〃・":
            continue
        return False
    return any(("\u4e00" <= c <= "\u9fff") or ("\u30a1" <= c <= "\u30fa") for c in s)


_LAST_BEST = [{}]


def build_base():
    by_reading = collections.defaultdict(list)
    for path in sorted(glob.glob(os.path.join(CACHE, "dictionary*.txt"))):
        for line in open(path, encoding="utf-8"):
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 5:
                continue
            reading, cost, surface = parts[0], int(parts[3]), parts[4]
            if not (1 <= len(reading) <= 10):
                continue
            if not is_kana_reading(reading):
                continue
            if not surface_ok(surface, reading):
                continue
            by_reading[reading].append((cost, surface))
    final = {}
    best_cost = {}
    _LAST_BEST[0] = best_cost
    for r, lst in by_reading.items():
        lst.sort()
        seen, out = set(), []
        for cost, surf in lst:
            if surf in seen:
                continue
            seen.add(surf)
            out.append(surf)
            if len(out) >= 3:
                break
        if lst[0][0] <= COST_THRESHOLD:
            final[r] = out
            best_cost[r] = lst[0][0]
    return final


# 五段活用の例外（イ段・エ段で終わるのに五段の動詞でよく使うもの）
GODAN_EXCEPTIONS = {
    "かえる", "はしる", "いる", "きる", "しる", "すべる", "しゃべる",
    "にぎる", "ちる", "へる", "ける", "あせる", "まいる", "かぎる",
    "つねる",  # 摘む系ではないが五段
}
TE_MAP = {
    "う": ("って", "った"), "つ": ("って", "った"),
    "む": ("んで", "んだ"), "ぶ": ("んで", "んだ"), "ぬ": ("んで", "んだ"),
    "く": ("いて", "いた"), "ぐ": ("いで", "いだ"),
    "す": ("して", "した"),
}
I_ROW = set("いきしちにひみりゐぎじぢびぴ")
E_ROW = set("えけせてねへめれゑげぜでべぺ")


def add_inflections(d, best_cost):
    supplement = collections.defaultdict(list)
    for reading, cands in d.items():
        if not (2 <= len(reading) <= 6):
            continue
        last = reading[-1]
        # 漢字を含み末尾が読みと一致する最初の候補を動詞の表層形とする
        surf = None
        for c in cands:
            if len(c) >= 2 and c[-1] == last and \
               any("\u4e00" <= ch <= "\u9fff" for ch in c):
                surf = c
                break
        if surf is None:
            continue
        # 断片的な古典語（のう→無う 等）からは活用形を作らない
        if surf in ("無う", "亡う", "無る"):
            continue
        if last == "る":
            if reading in GODAN_EXCEPTIONS:
                te_tail, ta_tail = "って", "った"
            elif len(reading) >= 2 and (reading[-2] in I_ROW or reading[-2] in E_ROW):
                te_tail, ta_tail = "て", "た"      # 一段
            else:
                te_tail, ta_tail = "って", "った"  # 五段
            pairs = [(reading[:-1] + te_tail, surf[:-1] + te_tail),
                     (reading[:-1] + ta_tail, surf[:-1] + ta_tail)]
        elif last in TE_MAP:
            te_tail, ta_tail = TE_MAP[last]
            pairs = [(reading[:-1] + te_tail, surf[:-1] + te_tail),
                     (reading[:-1] + ta_tail, surf[:-1] + ta_tail)]
        else:
            continue
        if reading == "いく" and surf == "行く":
            pairs = [("いって", "行って"), ("いった", "行った")]
        if reading == "くる" and surf == "来る":
            pairs = [("きて", "来て"), ("きた", "来た")]
        base_cost = best_cost.get(reading, 9999)
        for nr, ns in pairs:
            if ns in ("無って", "無った"):
                continue
            supplement[nr].append((base_cost, ns))
    merged = dict(d)
    for r, entries in supplement.items():
        entries.sort()
        cands = []
        for _, ns in entries:
            if ns not in cands:
                cands.append(ns)
        existing = merged.get(r, [])
        merged[r] = ([c for c in cands if c not in existing] + existing)[:3]
    return merged


def main():
    download()
    d = build_base()
    print("base readings:", len(d))
    d = add_inflections(d, getattr(build_base, "_best", {}) or _LAST_BEST[0])
    print("with inflections:", len(d))
    with open(OUT, "w", encoding="utf-8") as f:
        for r in sorted(d.keys()):
            f.write(f"{r}\t{'|'.join(d[r])}\n")
    print("wrote", OUT, "%.2f MB" % (os.path.getsize(OUT) / 1e6))
    for probe in ["のって", "いって", "たべて", "わたし", "する"]:
        print(probe, "->", d.get(probe))


if __name__ == "__main__":
    sys.exit(main())
