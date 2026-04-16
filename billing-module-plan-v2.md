# BILLING MODULE + MWL INTEGRATION — Build Plan for IHA Care

## What to Build
USG scan centre billing system + DICOM Modality Worklist (MWL) integration with Samsung V6 USG machine. New module added to the existing Flutter app — do NOT modify existing consultation/kidney/endocrine features.

---

## PART 1: BILLING MODULE

### Database: Extend existing SQLite (database_helper.dart)

**scan_types**
id TEXT PK, name TEXT, price REAL, category TEXT (OB-GYN/General/Small Parts/MSK), modality TEXT DEFAULT 'US', is_active INT DEFAULT 1

**referral_doctors**
id TEXT PK, name TEXT, phone TEXT, clinic_name TEXT, specialty TEXT, incentive_type TEXT (percentage|flat), incentive_value REAL, is_active INT DEFAULT 1

**bills**
id TEXT PK (B-YYMM-NNNN), patient_id TEXT FK→patients, scan_type_id TEXT FK, referral_doctor_id TEXT FK, sonographer_id TEXT FK→users, scan_fee REAL, discount REAL, final_amount REAL, payment_mode TEXT (Cash|UPI|Card|Credit), status TEXT (paid|pending), accession_number TEXT UNIQUE, worklist_pushed INT DEFAULT 0, scan_completed INT DEFAULT 0, notes TEXT, created_at TEXT, created_by TEXT FK→users

**pcpndt_form_f**
id TEXT PK, bill_id TEXT FK, patient_id TEXT FK, referral_doctor_id TEXT FK, indication TEXT, declaration_signed INT, created_at TEXT

**incentive_ledger**
id TEXT PK, referral_doctor_id TEXT FK, month TEXT (YYYY-MM), referral_count INT, total_billed REAL, incentive_amount REAL, payment_status TEXT (unpaid|paid), paid_date TEXT

### Seed Data — 14 scan types
- OB-GYN: OB Scan ₹800, TVS ₹1200, NT Scan ₹1500, Anomaly Scan ₹2000, Growth Scan ₹1000, Doppler ₹1800
- General: Abdomen ₹700, Pelvis ₹800, KUB ₹700
- Small Parts: Thyroid ₹600, Breast ₹800, Scrotal ₹700, Neck ₹600
- MSK: MSK USG ₹900

### Screens (lib/screens/billing/)

1. **billing_dashboard_screen.dart** — Stats cards + recent bills + worklist status indicator
2. **new_bill_screen.dart** — Patient → scan → referral doc → discount → payment → generate. **On generate: create bill + push to MWL automatically**
3. **bill_history_screen.dart** — Searchable list, scan completion status from Orthanc
4. **referral_doctors_screen.dart** — CRUD with incentive rules
5. **incentive_report_screen.dart** — Monthly doctor-wise calculation + PDF export
6. **reports_screen.dart** — Volume, payment split, PCPNDT tracker
7. **receipt_preview_screen.dart** — PDF receipt
8. **scan_types_screen.dart** — Manage catalog
9. **worklist_status_screen.dart** — Live view of MWL queue: pending/in-progress/completed scans

### Models (lib/models/billing/)
bill.dart, scan_type.dart, referral_doctor.dart, incentive_record.dart, pcpndt_form_f.dart, worklist_entry.dart

### Services
- **billing_service.dart** — Bill CRUD, incentive calc, reports
- **mwl_service.dart** — HTTP client to call local FastAPI helper for worklist push/query
- **orthanc_service.dart** — Query Orthanc REST API to check scan completion

---

## PART 2: MWL INTEGRATION

### Architecture

```
Flutter Pcare App (Windows)
       │
       │ 1. Generate bill → POST patient/scan details
       ▼
FastAPI Helper Service (Python, localhost:8000)
       │
       │ 2. Write .wl file via pydicom
       ▼
Orthanc Worklist Folder (C:/orthanc/worklists/)
       │
       │ 3. DICOM C-FIND query
       ▼
Samsung V6 USG → Patient appears in worklist → Sonographer selects → Scans
       │
       │ 4. DICOM C-STORE push images
       ▼
Orthanc DICOM Server (port 4242)
       │
       │ 5. Webhook on study received
       ▼
FastAPI updates bill.scan_completed = 1
       │
       │ 6. Flutter app polls/refreshes
       ▼
Typist sees scan ready for measurement entry
```

### Component 1: Orthanc Setup (Windows Service)

**Install:** Download Orthanc Windows installer from orthanc-server.com. Install with these plugins enabled:
- DICOM Worklist plugin
- REST API (default)

**Config file (orthanc.json):**
```json
{
  "Name": "ScanCentreOrthanc",
  "DicomAet": "ORTHANC",
  "DicomPort": 4242,
  "HttpPort": 8042,
  "Worklists": {
    "Enable": true,
    "Database": "C:/orthanc/worklists",
    "FilterIssuerAet": false
  },
  "DicomModalities": {
    "samsung_v6": ["SAMSUNG_V6", "192.168.1.50", 104]
  },
  "RegisteredUsers": { "admin": "changeme" }
}
```

**Worklist folder:** `C:/orthanc/worklists/` — drop `.wl` files here, Orthanc serves them on DICOM C-FIND queries.

### Component 2: FastAPI Helper Service (Python)

**Install:**
```bash
pip install fastapi uvicorn pydicom python-multipart
```

**File: mwl_helper/main.py**
```python
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from pydicom.dataset import Dataset, FileDataset
from pydicom.uid import generate_uid, ExplicitVRLittleEndian
import datetime, os

app = FastAPI()
WORKLIST_DIR = "C:/orthanc/worklists"

class WorklistEntry(BaseModel):
    patient_id: str        # Pcare patient ID e.g. P-2026-0001
    patient_name: str      # "Devi^Anitha" (DICOM format: family^given)
    patient_dob: str       # YYYYMMDD
    patient_sex: str       # M/F/O
    accession_number: str  # Unique per scan, e.g. bill ID B-2604-0001
    scan_description: str  # e.g. "OB Scan - 2nd Trimester"
    scheduled_datetime: str # YYYYMMDDHHMMSS
    referring_physician: str
    modality: str = "US"
    aet: str = "SAMSUNG_V6"

@app.post("/worklist/add")
def add_to_worklist(entry: WorklistEntry):
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

    # Scheduled Procedure Step Sequence
    sps = Dataset()
    sps.ScheduledStationAETitle = entry.aet
    sps.ScheduledProcedureStepStartDate = entry.scheduled_datetime[:8]
    sps.ScheduledProcedureStepStartTime = entry.scheduled_datetime[8:]
    sps.Modality = entry.modality
    sps.ScheduledPerformingPhysicianName = entry.referring_physician
    sps.ScheduledProcedureStepDescription = entry.scan_description
    sps.ScheduledProcedureStepID = entry.accession_number
    ds.ScheduledProcedureStepSequence = [sps]

    # File meta
    file_meta = Dataset()
    file_meta.MediaStorageSOPClassUID = "1.2.840.10008.5.1.4.31"
    file_meta.MediaStorageSOPInstanceUID = generate_uid()
    file_meta.TransferSyntaxUID = ExplicitVRLittleEndian

    filename = f"{entry.accession_number}.wl"
    filepath = os.path.join(WORKLIST_DIR, filename)
    fds = FileDataset(filepath, ds, file_meta=file_meta, preamble=b"\0"*128)
    fds.is_little_endian = True
    fds.is_implicit_VR = False
    fds.save_as(filepath)

    return {"status": "ok", "filepath": filepath}

@app.delete("/worklist/{accession_number}")
def remove_from_worklist(accession_number: str):
    filepath = os.path.join(WORKLIST_DIR, f"{accession_number}.wl")
    if os.path.exists(filepath):
        os.remove(filepath)
        return {"status": "removed"}
    raise HTTPException(404, "Not found")

@app.get("/worklist")
def list_worklist():
    files = [f for f in os.listdir(WORKLIST_DIR) if f.endswith(".wl")]
    return {"count": len(files), "entries": files}
```

**Run as Windows service** using NSSM (Non-Sucking Service Manager):
```bash
nssm install MWLHelper "C:/Python/python.exe" "-m uvicorn main:app --host 127.0.0.1 --port 8000"
nssm set MWLHelper AppDirectory "C:/mwl_helper"
nssm start MWLHelper
```

### Component 3: Samsung V6 Configuration

On the V6 console (usually under Setup → Connectivity → DICOM):

**MWL Server (SCP):**
- AE Title: `ORTHANC`
- IP: `<your PC IP>` (e.g., 192.168.1.10)
- Port: `4242`

**Storage Server (for image push):**
- AE Title: `ORTHANC`
- IP: same PC
- Port: `4242`

**Local AE Title (V6's own identity):** `SAMSUNG_V6`

Test connection from V6 menu (Verify/Echo). Once green, the "Worklist" button on the V6 will fetch the scheduled patients.

### Component 4: Flutter Service

**File: lib/services/mwl_service.dart**
```dart
class MwlService {
  static const baseUrl = "http://127.0.0.1:8000";

  static Future<bool> pushToWorklist(Bill bill, Patient patient, ScanType scan, ReferralDoctor doc) async {
    final body = {
      "patient_id": patient.id,
      "patient_name": "${patient.lastName}^${patient.firstName}",
      "patient_dob": _formatDob(patient.dob),
      "patient_sex": patient.gender,
      "accession_number": bill.id,
      "scan_description": scan.name,
      "scheduled_datetime": _formatDateTime(DateTime.now()),
      "referring_physician": doc.name,
    };
    final res = await http.post(
      Uri.parse("$baseUrl/worklist/add"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(body),
    );
    return res.statusCode == 200;
  }

  static Future<bool> removeFromWorklist(String accessionNumber) async {
    final res = await http.delete(Uri.parse("$baseUrl/worklist/$accessionNumber"));
    return res.statusCode == 200;
  }
}
```

### Component 5: Workflow Integration

In **new_bill_screen.dart**, after bill is saved:
```dart
final pushed = await MwlService.pushToWorklist(bill, patient, scanType, referralDoctor);
if (pushed) {
  await BillingService.markWorklistPushed(bill.id);
}
```

In **billing_dashboard_screen.dart**, show MWL queue status with periodic refresh of bills where `worklist_pushed=1` and `scan_completed=0`.

---

## INSTALLATION CHECKLIST

1. ☐ Install Orthanc on PC, enable Worklist plugin, configure orthanc.json
2. ☐ Create `C:/orthanc/worklists/` folder
3. ☐ Install Python 3.11+, create mwl_helper folder, paste main.py, install deps
4. ☐ Run FastAPI service via NSSM as Windows service
5. ☐ Configure Samsung V6: MWL server + Storage server pointing to PC IP
6. ☐ Test V6 → DICOM Echo (verify connection)
7. ☐ Add billing module to Flutter project (per Part 1)
8. ☐ Add mwl_service.dart, integrate into new_bill_screen
9. ☐ Test end-to-end: create bill → check V6 worklist → scan → verify image arrives in Orthanc

---

## LICENSE NOTE
Verify with Samsung dealer that **DICOM Worklist (MWL)** option is enabled on your V6. Some entry configs ship without it — it's a one-time activation from Samsung.

## FUTURE ENHANCEMENTS
- Multi-machine support (add more modalities in orthanc.json)
- Auto-cleanup of completed worklist entries (cron in helper service)
- Push notifications to typist app when scan arrives
- DICOM SR (Structured Reporting) for OB measurements directly from V6
