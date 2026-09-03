"""Regenerate district aliases from a PDF that uses an unseen font encoding.

DGHS releases are produced with more than one legacy Bengali font, so the same
district can extract as 'ফরিদপুি' one day and 'ফরিদপযি' the next. The district
*order* in the table is stable, so aliases are derived positionally against the
canonical code list rather than by reading the mangled text.

    python tools_make_aliases.py .cache/20260827_dengue_all.pdf --write
    python tools_make_aliases.py .cache/*.pdf --write     # harvest a whole corpus

Prints the new pairs; merge them with --write. Run it over a year of cached
releases after a backfill to pick up every encoding DGHS used that season.
"""
import json, sys
from pathlib import Path
import pdfplumber

CANONICAL_ORDER = [
 "DHAKA","FARIDPUR","GAZIPUR","GOPALGANJ","KISHOREGANJ","MADARIPUR","MANIKGANJ",
 "MUNSHIGANJ","NARAYANGANJ","NARSINGDI","RAJBARI","SHARIATPUR","TANGAIL","MYMENSINGH",
 "JAMALPUR","SHERPUR","NETROKONA","CHATTOGRAM","COXS_BAZAR","BANDARBAN","RANGAMATI",
 "KHAGRACHHARI","FENI","NOAKHALI","CUMILLA","CHANDPUR","LAKSHMIPUR","BRAHMANBARIA",
 "KHULNA","BAGERHAT","SATKHIRA","JASHORE","JHENAIDAH","MAGURA","NARAIL","KUSHTIA",
 "CHUADANGA","MEHERPUR","RAJSHAHI","CHAPAI_NAWAB","NAOGAON","NATORE","JOYPURHAT",
 "BOGURA","SIRAJGANJ","PABNA","RANGPUR","LALMONIRHAT","KURIGRAM","NILPHAMARI",
 "DINAJPUR","GAIBANDHA","THAKURGAON","PANCHAGARH","BARISHAL","PATUAKHALI","BHOLA",
 "PIROJPUR","BARGUNA","JHALOKATI","SYLHET","SUNAMGANJ","HABIGANJ","MOULVIBAZAR",
]
BN = str.maketrans("০১২৩৪৫৬৭৮৯", "0123456789")

def num(cell):
    t = (cell or "").translate(BN).replace(",", "").strip()
    return int(t) if t.isdigit() else None

def ordered_cells(pdf_path):
    seen, order = set(), []
    with pdfplumber.open(pdf_path) as pdf:
        for page in pdf.pages:
            for table in page.extract_tables():
                for row in table:
                    c = [(x or "").replace("\n", " ").strip() for x in row]
                    if len(c) < 11:
                        continue
                    if any(num(x) is None for x in c[4:11]):
                        continue
                    name = c[2]
                    if name and name not in seen:
                        seen.add(name); order.append(name)
    return order

def main():
    paths = [Path(a) for a in sys.argv[1:] if not a.startswith("--")]
    if not paths:
        print(__doc__)
        return 2

    alias_path = Path(__file__).parent / "dghs" / "district_aliases.json"
    existing = json.loads(alias_path.read_text(encoding="utf-8"))
    discovered: dict[str, str] = {}
    skipped, conflicts = [], []

    for path in sorted(paths):
        try:
            cells = ordered_cells(path)
        except Exception as exc:
            skipped.append((path.name, f"unreadable: {exc}"))
            continue

        if len(cells) != len(CANONICAL_ORDER):
            # A release whose table does not have exactly 64 districts cannot be
            # mapped positionally; skip it rather than guess.
            skipped.append((path.name, f"{len(cells)} district cells, expected 64"))
            continue

        for cell, code in zip(cells, CANONICAL_ORDER):
            known = existing.get(cell) or discovered.get(cell)
            if known and known != code:
                conflicts.append((path.name, cell, known, code))
            elif not known:
                discovered[cell] = code

    for name, cell, known, positional in conflicts:
        print(f"CONFLICT in {name}: {cell!r} is {known} but position says {positional}")
    if conflicts:
        print("\nrefusing to write: the district order assumption does not hold")
        return 1

    print(f"scanned {len(paths)} file(s); {len(skipped)} skipped; "
          f"{len(discovered)} new aliases")
    for name, why in skipped[:10]:
        print(f"  skipped {name}: {why}")
    for cell, code in list(discovered.items())[:40]:
        print(f"  {cell!r:<26} -> {code}")

    if "--write" in sys.argv and discovered:
        existing.update(discovered)
        alias_path.write_text(json.dumps(existing, ensure_ascii=False, indent=1),
                              encoding="utf-8")
        print(f"\nmerged; alias table now has {len(existing)} entries "
              f"covering {len(set(existing.values()))} districts")
    return 0

if __name__ == "__main__":
    sys.exit(main())
