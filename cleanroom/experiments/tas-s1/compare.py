#!/usr/bin/env python3
"""Compare outputs of tas_s1_change.py (rasterio) and tas_s1_change_gdal.py, file by file.

  python3 compare.py <rasterio work> <rasterio out> <gdal work> <gdal out> <report.json>
"""
import json
import sys
from pathlib import Path

import numpy as np
from osgeo import gdal

gdal.UseExceptions()


def describe(p: Path) -> dict:
    d = gdal.Open(str(p))
    b1 = d.GetRasterBand(1)
    return dict(size=[d.RasterXSize, d.RasterYSize, d.RasterCount], gt=list(d.GetGeoTransform()),
                srs_wkt_len=len(d.GetProjection()), block=b1.GetBlockSize(),
                overviews=b1.GetOverviewCount(), nodata=str(b1.GetNoDataValue()),
                desc=[d.GetRasterBand(i + 1).GetDescription() for i in range(d.RasterCount)],
                meta=d.GetMetadata(), image_structure=d.GetMetadata("IMAGE_STRUCTURE"))


def compare(a: Path, b: Path) -> dict:
    da, db = describe(a), describe(b)
    out = dict(file=a.name, same_header={k: da[k] == db[k] for k in da}, bands=[])
    for k in da:
        if da[k] != db[k]:
            out.setdefault("header_diff", {})[k] = [da[k], db[k]]
    xa, xb = gdal.Open(str(a)).ReadAsArray(), gdal.Open(str(b)).ReadAsArray()
    if xa.shape != xb.shape:
        out["shape"] = [list(xa.shape), list(xb.shape)]
        return out
    xa, xb = xa.reshape(-1, *xa.shape[-2:]), xb.reshape(-1, *xb.shape[-2:])
    for i, (u, v) in enumerate(zip(xa, xb), 1):
        fu, fv = np.isfinite(u), np.isfinite(v)
        both = fu & fv
        dif = np.abs(u[both].astype("float64") - v[both])
        out["bands"].append(dict(band=i, n_valid=[int(fu.sum()), int(fv.sum())],
                                 mask_disagree=int((fu != fv).sum()),
                                 n_differ=int((dif > 0).sum()),
                                 max_abs_diff=float(dif.max()) if dif.size else 0.0,
                                 mean=[float(u[fu].mean()) if fu.any() else None,
                                       float(v[fv].mean()) if fv.any() else None]))
    return out


def main():
    rw, ro, gw, go, rep = map(Path, sys.argv[1:6])
    pairs = [(f, gw / "bursts" / f.name) for f in sorted((rw / "bursts").glob("*.tif"))]
    pairs += [(f, go / f.name) for f in sorted(ro.glob("*.tif"))]
    res = []
    for a, b in pairs:
        res.append(compare(a, b) if b.exists() else dict(file=a.name, missing_in_gdal=True))
    extra = sorted({p.name for p in (gw / "bursts").glob("*.tif")} ^ {p.name for p in (rw / "bursts").glob("*.tif")})
    stats = {}
    for f in sorted(ro.glob("*stats*.json")):
        g = go / f.name
        stats[f.name] = [json.loads(f.read_text()), json.loads(g.read_text()) if g.exists() else None]
    Path(rep).write_text(json.dumps(dict(pairs=res, unmatched=extra, stats=stats), indent=1))
    for r in res:
        worst = max((b["max_abs_diff"] for b in r.get("bands", [])), default=None)
        mask = sum(b["mask_disagree"] for b in r.get("bands", []))
        hdr = sorted(r.get("header_diff", {}))
        print(f"{r['file']}: max|diff| {worst}  mask disagree {mask}  header diffs {hdr}")


if __name__ == "__main__":
    main()
