"""
FastAPI MWL Helper Service — IHA Care USG Centre
Runs on localhost:8000, writes DICOM .wl files for Samsung V6 worklist.

Install:
    pip install fastapi uvicorn pydicom python-multipart

Run (development):
    uvicorn main:app --host 127.0.0.1 --port 8000

Run as Windows service via NSSM:
    nssm install MWLHelper "C:/Python/python.exe" "-m uvicorn main:app --host 127.0.0.1 --port 8000"
    nssm set MWLHelper AppDirectory "C:/mwl_helper"
    nssm start MWLHelper
"""

import io
import os
import sqlite3
from datetime import datetime

import pydicom
import requests as _requests
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from pydicom.dataset import Dataset, FileDataset
from pydicom.uid import generate_uid, ExplicitVRLittleEndian

app = FastAPI(title="IHA Care MWL Helper")

WORKLIST_DIR = os.environ.get("WORKLIST_DIR", "C:/orthanc/worklists")
DB_PATH = os.environ.get("DB_PATH", "C:/mwl_helper/mwl_helper.db")
ORTHANC_URL = os.environ.get("ORTHANC_URL", "http://127.0.0.1:8042")


class WorklistEntry(BaseModel):
    patient_id: str
    patient_name: str        # DICOM format: "FamilyName^GivenName"
    patient_dob: str         # YYYYMMDD
    patient_sex: str         # M / F / O
    accession_number: str    # Unique per scan — bill ID e.g. B-2604-0001
    scan_description: str
    scheduled_datetime: str  # YYYYMMDDHHMMSS
    referring_physician: str
    modality: str = "US"
    aet: str = "SAMSUNG_V6"


def _ensure_dirs():
    os.makedirs(WORKLIST_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)


def _write_wl_file(entry: WorklistEntry) -> str:
    ds = Dataset()
    ds.SpecificCharacterSet = "ISO_IR 100"
    ds.AccessionNumber = entry.accession_number
    ds.PatientID = entry.patient_id
    ds.PatientName = entry.patient_name
    ds.PatientBirthDate = entry.patient_dob
    ds.PatientSex = entry.patient_sex
    ds.StudyInstanceUID = generate_uid()
    ds.RequestedProcedureID = entry.accession_number
    ds.RequestedProcedureDescription = entry.scan_description
    ds.ReferringPhysicianName = entry.referring_physician

    sps = Dataset()
    sps.ScheduledStationAETitle = entry.aet
    sps.ScheduledProcedureStepStartDate = entry.scheduled_datetime[:8]
    sps.ScheduledProcedureStepStartTime = entry.scheduled_datetime[8:]
    sps.Modality = entry.modality
    sps.ScheduledPerformingPhysicianName = entry.referring_physician
    sps.ScheduledProcedureStepDescription = entry.scan_description
    sps.ScheduledProcedureStepID = entry.accession_number
    ds.ScheduledProcedureStepSequence = [sps]

    file_meta = Dataset()
    file_meta.MediaStorageSOPClassUID = "1.2.840.10008.5.1.4.31"
    file_meta.MediaStorageSOPInstanceUID = generate_uid()
    file_meta.TransferSyntaxUID = ExplicitVRLittleEndian

    filename = f"{entry.accession_number}.wl"
    filepath = os.path.join(WORKLIST_DIR, filename)

    fds = FileDataset(filepath, ds, file_meta=file_meta, preamble=b"\0" * 128)
    fds.is_little_endian = True
    fds.is_implicit_VR = False
    fds.save_as(filepath)

    return filepath


@app.on_event("startup")
def startup():
    _ensure_dirs()


@app.post("/worklist/add")
def add_to_worklist(entry: WorklistEntry):
    try:
        filepath = _write_wl_file(entry)
        return {"status": "ok", "filepath": filepath, "accession": entry.accession_number}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/worklist/{accession_number}")
def remove_from_worklist(accession_number: str):
    filepath = os.path.join(WORKLIST_DIR, f"{accession_number}.wl")
    if os.path.exists(filepath):
        os.remove(filepath)
        return {"status": "removed", "accession": accession_number}
    raise HTTPException(status_code=404, detail=f"{accession_number}.wl not found")


@app.get("/worklist")
def list_worklist():
    try:
        files = [f for f in os.listdir(WORKLIST_DIR) if f.endswith(".wl")]
        return {"count": len(files), "entries": files}
    except FileNotFoundError:
        return {"count": 0, "entries": []}


@app.get("/health")
def health():
    return {
        "status": "ok",
        "worklist_dir": WORKLIST_DIR,
        "worklist_dir_exists": os.path.isdir(WORKLIST_DIR),
        "timestamp": datetime.now().isoformat(),
    }


# ── DICOM SR measurement parsing ──────────────────────────────────────────────

def _extract_sr_measurements(seq, results: list, depth: int = 0):
    """Recursively walk a DICOM SR ContentSequence and collect NUM/TEXT items."""
    if depth > 10:
        return
    for item in seq:
        value_type = getattr(item, "ValueType", "")
        name = ""
        name_seq = getattr(item, "ConceptNameCodeSequence", [])
        if name_seq:
            name = getattr(name_seq[0], "CodeMeaning", "")

        if value_type == "NUM" and hasattr(item, "MeasuredValueSequence"):
            try:
                mvs = item.MeasuredValueSequence[0]
                value = float(getattr(mvs, "NumericValue", 0))
                unit_seq = getattr(mvs, "MeasurementUnitsCodeSequence", [])
                unit = getattr(unit_seq[0], "CodeMeaning", "") if unit_seq else ""
                results.append({"name": name, "value": value, "unit": unit})
            except Exception:
                pass

        elif value_type == "TEXT" and hasattr(item, "TextValue"):
            results.append({"name": name, "value": item.TextValue, "unit": ""})

        elif value_type == "DATE" and hasattr(item, "Date"):
            results.append({"name": name, "value": str(item.Date), "unit": "date"})

        if hasattr(item, "ContentSequence"):
            _extract_sr_measurements(item.ContentSequence, results, depth + 1)


def _get_sr_measurements_for_accession(accession: str) -> list:
    """Query Orthanc for SR instances of a study and parse their measurements."""
    # Find SR instances for this accession
    try:
        r = _requests.post(
            f"{ORTHANC_URL}/tools/find",
            json={"Level": "Instance", "Query": {"AccessionNumber": accession}},
            timeout=5,
        )
        r.raise_for_status()
        instance_ids: list = r.json()
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Orthanc unreachable: {exc}")

    measurements: list = []
    for iid in instance_ids:
        # Filter to SR modality via simplified tags before downloading the file
        try:
            tags_r = _requests.get(
                f"{ORTHANC_URL}/instances/{iid}/simplified-tags", timeout=5
            )
            tags = tags_r.json() if tags_r.ok else {}
            modality = tags.get("Modality", "")
            if modality != "SR":
                continue

            file_r = _requests.get(
                f"{ORTHANC_URL}/instances/{iid}/file", timeout=10
            )
            file_r.raise_for_status()
            ds = pydicom.dcmread(io.BytesIO(file_r.content), force=True)
            instance_results: list = []
            if hasattr(ds, "ContentSequence"):
                _extract_sr_measurements(ds.ContentSequence, instance_results)
            measurements.extend(instance_results)
        except Exception:
            continue

    return measurements


# ── Orthanc webhook handler — called by Orthanc when a study arrives
# Configure in orthanc.json: "Lua": { ... } or use the Orthanc HTTP plugin
# POST /orthanc/study-received with JSON {"AccessionNumber": "B-2604-0001"}
@app.post("/orthanc/study-received")
def study_received(data: dict):
    accession = data.get("AccessionNumber") or data.get("accession_number")
    if not accession:
        raise HTTPException(status_code=400, detail="AccessionNumber required")

    # Notify Flutter app via SQLite flag update
    # The Flutter app polls the billing DB; this endpoint updates scan_completed
    # This requires the helper service to have access to the same DB file.
    # For production, connect to the Flutter app's SQLite DB path.
    db_path = os.environ.get("FLUTTER_DB_PATH", DB_PATH)
    try:
        conn = sqlite3.connect(db_path)
        conn.execute(
            "UPDATE bills SET scan_completed = 1 WHERE accession_number = ? OR id = ?",
            (accession, accession),
        )
        conn.commit()
        conn.close()
        return {"status": "updated", "accession": accession}
    except Exception as e:
        # Non-fatal — log and return ok so Orthanc doesn't retry indefinitely
        return {"status": "db_error", "detail": str(e)}


@app.get("/measurements/{accession_number}")
def get_measurements(accession_number: str):
    """
    Return parsed DICOM SR measurements for a study identified by accession number.
    Queries Orthanc, finds SR instances, parses Content Sequence with pydicom.
    """
    measurements = _get_sr_measurements_for_accession(accession_number)
    return {
        "accession_number": accession_number,
        "count": len(measurements),
        "measurements": measurements,
    }
