#!/usr/bin/env python3
"""LiveSpot 경계면 대조: Pydantic 응답 필드명 <-> Dart fromJson이 읽는 JSON 키.

Dart는 json['key']를 동적으로 캐스팅하므로 컴파일러가 키 오타를 잡지 못한다.
이 스크립트는 양쪽을 문자 단위로 대조해 불일치를 드러낸다.

사용법 (프로젝트 루트에서):
    python .claude/skills/livespot-contract/scripts/contract_diff.py
    python .claude/skills/livespot-contract/scripts/contract_diff.py --pair HotspotEntry=HotspotEntry
    python .claude/skills/livespot-contract/scripts/contract_diff.py --dart-only Question

정적 대조일 뿐이다. 실제 응답 JSON 확인(curl)을 대체하지 않는다 —
response_model 필터링·직렬화 설정 때문에 정의와 실제 응답은 다를 수 있다.
"""
import argparse
import re
import sys
from pathlib import Path

# Windows 콘솔 기본 인코딩(cp949)에서 한글이 깨지므로 UTF-8로 고정한다.
try:
    sys.stdout.reconfigure(encoding="utf-8")
except AttributeError:
    pass

SCHEMAS = Path("livespot_backend/app/models/schemas.py")
DART_MODELS = Path("livespot_app/lib/models")

CLASS_RE = re.compile(r"^class\s+(\w+)\s*\(([^)]*)\)\s*:")
FIELD_RE = re.compile(r"^\s{4}(\w+)\s*:\s*(.+?)(?:\s*=\s*(.*))?$")
DART_CLASS_RE = re.compile(r"^class\s+(\w+)", re.M)
JSON_KEY_RE = re.compile(r"""json\[\s*['"]([^'"]+)['"]\s*\]""")


def parse_pydantic(path: Path) -> dict:
    """{클래스명: {필드명: {"type": str, "optional": bool}}} — 상속 필드까지 펼친다."""
    if not path.exists():
        sys.exit(f"[error] 스키마 파일 없음: {path}")
    classes, bases, cur = {}, {}, None
    for line in path.read_text(encoding="utf-8").splitlines():
        m = CLASS_RE.match(line)
        if m:
            cur = m.group(1)
            classes[cur] = {}
            bases[cur] = [b.strip() for b in m.group(2).split(",") if b.strip()]
            continue
        if cur is None or (line.strip() and not line.startswith(" ")):
            if line.strip() and not line.startswith(" "):
                cur = None
            continue
        m = FIELD_RE.match(line)
        if m and not line.lstrip().startswith("#") and '"""' not in line:
            name, typ = m.group(1), m.group(2).split("#")[0].strip()
            classes[cur][name] = {
                "type": typ,
                "optional": "Optional" in typ or typ.endswith("| None"),
            }
    # 상속 펼치기 (SpotDetail(SpotBase) 등)
    def resolve(name, seen=None):
        seen = seen or set()
        if name in seen or name not in classes:
            return {}
        seen.add(name)
        out = {}
        for b in bases.get(name, []):
            out.update(resolve(b, seen))
        out.update(classes[name])
        return out

    return {c: resolve(c) for c in classes}


def parse_dart(models_dir: Path) -> dict:
    """{Dart클래스명: {"file": 경로, "keys": {키: 캐스팅줄}}}

    한 파일에 여러 클래스가 있을 수 있으므로(question.dart = Question + Answer)
    class 선언 위치로 파일을 잘라 클래스별로 키를 귀속시킨다.
    """
    if not models_dir.exists():
        sys.exit(f"[error] Dart 모델 디렉토리 없음: {models_dir}")
    out = {}
    for f in sorted(models_dir.glob("*.dart")):
        text = f.read_text(encoding="utf-8")
        marks = [(m.start(), m.group(1)) for m in DART_CLASS_RE.finditer(text)]
        if not marks:
            continue
        bounds = [(marks[i][1], marks[i][0],
                   marks[i + 1][0] if i + 1 < len(marks) else len(text))
                  for i in range(len(marks))]
        for cls, start, end in bounds:
            keys = {}
            for line in text[start:end].splitlines():
                for k in JSON_KEY_RE.findall(line):
                    keys.setdefault(k, line.strip())
            if keys:
                out[cls] = {"file": str(f), "keys": keys}
    return out


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", s.lower())


def compare(dart_cls, dart_info, py_cls, py_fields):
    dart_keys = set(dart_info["keys"])
    py_keys = set(py_fields)
    problems = []

    for k in sorted(dart_keys - py_keys):
        problems.append(("MISSING", f"Dart가 json['{k}'] 를 읽지만 {py_cls}에 없음 -> 런타임 null"))
    for k in sorted(py_keys - dart_keys):
        problems.append(("UNREAD", f"{py_cls}.{k} 를 Dart가 읽지 않음 (의도적 미사용인지 확인)"))
    for k in sorted(dart_keys & py_keys):
        if py_fields[k]["optional"]:
            cast = dart_info["keys"][k]
            # 같은 줄에서 널 가드(== null 삼항 / ?? / ?.)를 하고 있으면 안전하다
            guarded = ("== null" in cast) or ("?? " in cast) or ("?." in cast)
            if not guarded and re.search(
                rf"""json\[\s*['"]{re.escape(k)}['"]\s*\]\s+as\s+[A-Za-z<>, ]+?(?<!\?)\s*[,;)]""", cast
            ):
                problems.append(("NULLABLE", f"{py_cls}.{k} 는 Optional인데 Dart가 non-null 캐스팅: {cast[:90]}"))
        if "datetime" in py_fields[k]["type"].lower():
            src = Path(dart_info["file"]).read_text(encoding="utf-8")
            if "_parseUtc" not in src and "Z'" not in src and 'Z"' not in src:
                problems.append(("UTC", f"{py_cls}.{k} 는 naive UTC datetime인데 Dart에 Z 보정(_parseUtc)이 없음 -> 9시간 오차"))
    return problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pair", action="append", default=[], metavar="Dart=Pydantic",
                    help="자동 매칭이 안 되는 쌍을 직접 지정")
    ap.add_argument("--dart-only", default=None, help="이 Dart 클래스만 검사")
    args = ap.parse_args()

    py = parse_pydantic(SCHEMAS)
    dart = parse_dart(DART_MODELS)
    manual = dict(p.split("=", 1) for p in args.pair)
    def find_py(dart_cls, dart_keys):
        """이름이 아니라 '읽는 키가 얼마나 겹치는가'로 짝을 고른다.

        SpotBase / SpotDetail / SpotIntro 처럼 이름만으로는 어느 쪽인지 알 수 없고,
        Dart가 실제로 읽는 키 집합이 가장 잘 덮이는 클래스가 실제 계약 상대다.
        """
        if not dart_keys:
            return None
        n = norm(dart_cls)
        scored = []
        for pcls, fields in py.items():
            covered = len(dart_keys & set(fields))
            if not covered:
                continue
            coverage = covered / len(dart_keys)
            pn = norm(pcls)
            name_bonus = 0.30 if pn == n else (0.15 if pn.startswith(n) or n.startswith(pn) else 0)
            # 서버에만 있는 필드가 많을수록 과대 매칭이므로 약하게 감점
            excess = (len(fields) - covered) / max(len(fields), 1)
            scored.append((coverage + name_bonus - 0.10 * excess, coverage, pcls))
        if not scored:
            return None
        scored.sort(reverse=True)
        best = scored[0]
        return best[2] if best[1] >= 0.5 else None

    total_problems, unmatched = 0, []
    for dcls, dinfo in sorted(dart.items()):
        if args.dart_only and dcls != args.dart_only:
            continue
        pcls = manual.get(dcls) or find_py(dcls, set(dinfo["keys"]))
        if not pcls:
            unmatched.append(dcls)
            continue
        problems = compare(dcls, dinfo, pcls, py[pcls])
        status = "OK" if not problems else f"{len(problems)} issue(s)"
        print(f"\n=== {dcls}  <->  {pcls}   [{status}] ")
        print(f"    {dinfo['file']}")
        for kind, msg in problems:
            print(f"    [{kind}] {msg}")
        total_problems += len(problems)

    if unmatched:
        print("\n=== 자동 매칭 실패 (Pydantic 짝을 못 찾음) ")
        for d in unmatched:
            print(f"    {d}  -> --pair {d}=<PydanticClass> 로 지정하거나, 서버 응답이 없는 로컬 전용 모델인지 확인")

    print(f"\n합계: {total_problems} issue(s), 매칭 실패 {len(unmatched)}개")
    print("주의: 정적 대조 결과다. curl로 실제 응답 JSON을 확인해야 검증이 끝난다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
