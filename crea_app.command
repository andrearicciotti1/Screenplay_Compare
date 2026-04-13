#!/bin/bash
# crea_app.command — file autonomo, funziona da qualsiasi posizione.
# Doppio click per creare "Screenplay Compare.app" sul Desktop.

APP="$HOME/Desktop/Screenplay Compare.app"
LOG="$HOME/Desktop/screenplay_compare_log.txt"

echo "=== Creazione Screenplay Compare.app ==="

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources/modules"

# ── Info.plist ───────────────────────────────────────────────────────────────
cat << 'PLIST' > "$APP/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>        <string>run</string>
  <key>CFBundleName</key>              <string>Screenplay Compare</string>
  <key>CFBundleIdentifier</key>        <string>com.andrea.screenplay-compare</string>
  <key>CFBundleVersion</key>           <string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>NSHighResolutionCapable</key>   <true/>
  <key>LSMinimumSystemVersion</key>    <string>11.0</string>
</dict>
</plist>
PLIST

# ── modules/__init__.py ──────────────────────────────────────────────────────
touch "$APP/Contents/Resources/modules/__init__.py"

# ── modules/screenplay_diff.py ───────────────────────────────────────────────
cat << 'DIFFEOF' > "$APP/Contents/Resources/modules/screenplay_diff.py"
import os, re, difflib, html, logging, xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import date
from typing import Optional

logger = logging.getLogger("ScreenplayCompare")
LINES_PER_PAGE = 55

@dataclass
class LineEntry:
    text: str
    page: int

@dataclass
class DiffChange:
    change_type: str
    old_lines: list
    new_lines: list
    page_v1: Optional[int]
    page_v2: Optional[int]

def extract_text_with_pages(file_path):
    if not file_path or not os.path.isfile(file_path):
        raise FileNotFoundError(f"File non trovato: {file_path}")
    ext = os.path.splitext(file_path)[1].lower()
    if ext == ".pdf":      return _extract_pdf(file_path)
    elif ext == ".fdx":    return _extract_fdx(file_path)
    elif ext in (".fountain", ".beat", ".txt"): return _extract_fountain(file_path)
    else: raise ValueError(f"Formato non supportato: {ext}")

def _extract_pdf(file_path):
    try:
        import pdfplumber
    except ImportError:
        raise ImportError("pdfplumber non installato.")
    entries = []
    with pdfplumber.open(file_path) as pdf:
        for page_num, page in enumerate(pdf.pages, 1):
            for line in (page.extract_text() or "").split("\n"):
                if line.strip():
                    entries.append(LineEntry(text=line.strip(), page=page_num))
    return entries

def _extract_fdx(file_path):
    try:
        tree = ET.parse(file_path); root = tree.getroot()
    except ET.ParseError as e:
        raise ValueError(f"Errore parsing FDX: {e}")
    paragraphs = root.findall(".//Paragraph") or []
    if not paragraphs:
        for ns in ["{http://www.finaldraft.com/}", ""]:
            paragraphs = root.findall(f".//{ns}Paragraph")
            if paragraphs: break
    raw = []
    for para in paragraphs:
        parts = [e.text for e in para.iter() if e.tag.endswith("Text") and e.text]
        line = " ".join(parts).strip()
        if line: raw.append(line)
    return [LineEntry(text=l, page=max(1, i//LINES_PER_PAGE+1)) for i, l in enumerate(raw)]

def _extract_fountain(file_path):
    try:
        content = open(file_path, encoding="utf-8").read()
    except Exception as e:
        raise IOError(f"Errore lettura: {e}")
    raw = [l.strip() for l in content.split("\n") if l.strip()]
    return [LineEntry(text=l, page=max(1, i//LINES_PER_PAGE+1)) for i, l in enumerate(raw)]

def compute_diff(v1, v2):
    matcher = difflib.SequenceMatcher(None, [e.text for e in v1], [e.text for e in v2], autojunk=False)
    changes = []
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal": continue
        oe, ne = v1[i1:i2], v2[j1:j2]
        changes.append(DiffChange(
            change_type=tag,
            old_lines=[e.text for e in oe], new_lines=[e.text for e in ne],
            page_v1=oe[0].page if oe else None, page_v2=ne[0].page if ne else None,
        ))
    return changes

_TPL = """<!DOCTYPE html><html lang="it"><head><meta charset="UTF-8">
<title>Diff Sceneggiatura</title><style>
body{{font-family:'Courier New',monospace;font-size:13px;background:#1e1e1e;color:#d4d4d4;margin:0;padding:20px}}
h1{{color:#fff;font-size:18px;border-bottom:1px solid #444;padding-bottom:8px}}
.meta{{color:#888;font-size:11px;margin-bottom:20px}}
.summary{{background:#2d2d2d;border-radius:6px;padding:12px 16px;margin-bottom:24px;font-size:12px}}
.summary span{{margin-right:20px}}
.ins-count{{color:#6acc6a}}.del-count{{color:#e67e22}}.rep-count{{color:#5dade2}}
.change{{margin:6px 0;padding:4px 8px;border-radius:3px;line-height:1.6}}
.page-label{{color:#666;font-size:10px;float:right;margin-left:10px}}
.insert{{background:#1a3a1a;border-left:3px solid #6acc6a}}.insert .text{{color:#6acc6a}}
.delete{{background:#2d1a00;border-left:3px solid #e67e22}}.delete .marker{{color:#e67e22;font-weight:bold}}
.replace{{background:#1a2a3a;border-left:3px solid #5dade2}}
.replace .old{{color:#e87878;text-decoration:line-through;opacity:.8}}
.replace .arrow{{color:#888;margin:0 6px}}.replace .new{{color:#6acc6a}}
</style></head><body>
<h1>Diff Sceneggiatura</h1>
<div class="meta">V1: <strong>{file1}</strong> &nbsp;|&nbsp; V2: <strong>{file2}</strong> &nbsp;|&nbsp; {today}</div>
<div class="summary"><span>Totale: <strong>{total}</strong></span>
<span class="ins-count">&#9650; Aggiunte: <strong>{inserts}</strong></span>
<span class="del-count">&#9660; Tagli: <strong>{deletes}</strong></span>
<span class="rep-count">&#8644; Modifiche: <strong>{replaces}</strong></span></div>
{body}</body></html>"""

def generate_html_report(changes, f1, f2):
    ins = sum(1 for c in changes if c.change_type=="insert")
    dels = sum(1 for c in changes if c.change_type=="delete")
    reps = sum(1 for c in changes if c.change_type=="replace")
    parts = []
    for c in changes:
        if c.change_type == "insert":
            pg = f'<span class="page-label">p.{c.page_v2}</span>' if c.page_v2 else ""
            parts.append(f'<div class="change insert">{pg}<span class="text">+ {html.escape(chr(10).join(c.new_lines))}</span></div>')
        elif c.change_type == "delete":
            pg = f'<span class="page-label">p.{c.page_v1} (v1)</span>' if c.page_v1 else ""
            parts.append(f'<div class="change delete">{pg}<span class="marker">###blocco tagliato###</span><br><span style="color:#888;font-size:11px">{html.escape(chr(10).join(c.old_lines))}</span></div>')
        elif c.change_type == "replace":
            pg = f'<span class="page-label">p.{c.page_v1}→{c.page_v2}</span>'
            parts.append(f'<div class="change replace">{pg}<span class="old">{html.escape(" / ".join(c.old_lines))}</span><span class="arrow">&#8644;</span><span class="new">{html.escape(" / ".join(c.new_lines))}</span></div>')
    body = "\n".join(parts) or '<p style="color:#888">Nessuna modifica.</p>'
    return _TPL.format(file1=html.escape(f1), file2=html.escape(f2),
                       today=date.today().isoformat(), total=ins+dels+reps,
                       inserts=ins, deletes=dels, replaces=reps, body=body)

def generate_text_report(changes, f1, f2):
    ins = sum(1 for c in changes if c.change_type=="insert")
    dels = sum(1 for c in changes if c.change_type=="delete")
    reps = sum(1 for c in changes if c.change_type=="replace")
    lines = ["="*60,"REPORT MODIFICHE SCENEGGIATURA","="*60,
             f"V1: {f1}", f"V2: {f2}", f"Data: {date.today().isoformat()}","",
             f"Totale: {ins+dels+reps}  (Aggiunte:{ins}  Tagli:{dels}  Modifiche:{reps})",
             "="*60,""]
    last = None
    for c in changes:
        pg = c.page_v2 or c.page_v1
        if pg != last: lines.append(f"\n--- PAGINA {pg} ---"); last = pg
        if c.change_type=="insert":
            lines.append(f"\n[AGGIUNTA] (p.{c.page_v2})")
            for l in c.new_lines: lines.append(f'  + "{l}"')
        elif c.change_type=="delete":
            lines.append(f"\n[TAGLIO] (p.{c.page_v1} v1)\n  ###blocco tagliato###")
            for l in c.old_lines: lines.append(f'  - "{l}"')
        elif c.change_type=="replace":
            lines.append(f"\n[MODIFICA] (p.{c.page_v1}→{c.page_v2})")
            lines.append("  DA:"); [lines.append(f'    "{l}"') for l in c.old_lines]
            lines.append("  A:");  [lines.append(f'    "{l}"') for l in c.new_lines]
    lines += ["\n"+"="*60,"Fine report","="*60]
    return "\n".join(lines)

def compare_screenplays(file1, file2, output_dir=None):
    if output_dir is None:
        output_dir = os.path.dirname(os.path.abspath(file1))
    os.makedirs(output_dir, exist_ok=True)
    n1 = os.path.splitext(os.path.basename(file1))[0]
    n2 = os.path.splitext(os.path.basename(file2))[0]
    v1 = extract_text_with_pages(file1)
    v2 = extract_text_with_pages(file2)
    changes = compute_diff(v1, v2)
    html_path = os.path.join(output_dir, f"{n1}_vs_{n2}_diff.html")
    txt_path  = os.path.join(output_dir, f"{n1}_vs_{n2}_report.txt")
    open(html_path, "w", encoding="utf-8").write(generate_html_report(changes, os.path.basename(file1), os.path.basename(file2)))
    open(txt_path,  "w", encoding="utf-8").write(generate_text_report(changes, os.path.basename(file1), os.path.basename(file2)))
    return {"html_path":html_path,"report_path":txt_path,"changes_count":len(changes),
            "inserts":sum(1 for c in changes if c.change_type=="insert"),
            "deletes":sum(1 for c in changes if c.change_type=="delete"),
            "replaces":sum(1 for c in changes if c.change_type=="replace"),
            "lines_v1":len(v1),"lines_v2":len(v2)}
DIFFEOF

# ── screenplay_compare_gui.py ────────────────────────────────────────────────
cat << 'GUIEOF' > "$APP/Contents/Resources/screenplay_compare_gui.py"
import os, sys, threading, tkinter as tk
from tkinter import filedialog, messagebox

_HERE = os.path.dirname(os.path.abspath(__file__))
for _p in [_HERE, os.getcwd()]:
    if _p not in sys.path: sys.path.insert(0, _p)

SUPPORTED = (("Sceneggiature","*.pdf *.fdx *.fountain *.beat *.txt"),
             ("PDF","*.pdf"),("Final Draft","*.fdx"),
             ("Fountain / Beat","*.fountain *.beat"),("Tutti i file","*.*"))

BG,BG2,ACCENT,GREEN,ORANGE,FG,FG_DIM = "#1e1e1e","#2d2d2d","#5dade2","#6acc6a","#e67e22","#d4d4d4","#888888"
FONT_SM = ("Helvetica",11)

class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Screenplay Diff")
        self.configure(bg=BG)
        self.resizable(False,False)
        self._build_ui()
        self._center()

    def _build_ui(self):
        tk.Label(self,text="Screenplay Diff",font=("Helvetica",18,"bold"),fg=FG,bg=BG).pack(pady=(24,4))
        tk.Label(self,text="Confronta due versioni di sceneggiatura",font=FONT_SM,fg=FG_DIM,bg=BG).pack(pady=(0,20))
        for attr,label,cmd in [("lbl1","Versione 1  (originale)","_pick1"),("lbl2","Versione 2  (revisione)","_pick2")]:
            tk.Label(self,text=label,font=FONT_SM,fg=FG_DIM,bg=BG,anchor="w").pack(fill="x",padx=24)
            row=tk.Frame(self,bg=BG); row.pack(fill="x",padx=20,pady=(4,14))
            lbl=tk.Label(row,text="Nessun file selezionato",font=FONT_SM,fg=FG_DIM,bg=BG2,anchor="w",padx=10,width=42,relief="flat")
            lbl.pack(side="left",ipady=8,fill="x",expand=True)
            setattr(self,attr,lbl)
            tk.Button(row,text="Scegli…",font=FONT_SM,bg=ACCENT,fg="white",relief="flat",cursor="hand2",padx=12,command=getattr(self,cmd)).pack(side="left",padx=(8,0),ipady=8)
        self.btn=tk.Button(self,text="Confronta  ▶",font=("Helvetica",14,"bold"),bg=GREEN,fg="#111",relief="flat",cursor="hand2",padx=20,pady=12,command=self._run)
        self.btn.pack(pady=(0,20))
        self.result_frame=tk.Frame(self,bg=BG2,padx=16,pady=14); self.result_frame.pack(fill="x",padx=20,pady=(0,24))
        self.result_lbl=tk.Label(self.result_frame,text="Seleziona due file e premi Confronta.",font=FONT_SM,fg=FG_DIM,bg=BG2,justify="left",anchor="w",wraplength=460)
        self.result_lbl.pack(anchor="w")

    def _pick1(self):
        p=filedialog.askopenfilename(title="Seleziona Versione 1",filetypes=SUPPORTED)
        if p: self.file1=p; self.lbl1.config(text=os.path.basename(p),fg=FG)

    def _pick2(self):
        p=filedialog.askopenfilename(title="Seleziona Versione 2",filetypes=SUPPORTED)
        if p: self.file2=p; self.lbl2.config(text=os.path.basename(p),fg=FG)

    def _run(self):
        f1=getattr(self,"file1",None); f2=getattr(self,"file2",None)
        if not f1: messagebox.showwarning("File mancante","Seleziona la Versione 1."); return
        if not f2: messagebox.showwarning("File mancante","Seleziona la Versione 2."); return
        self.btn.config(state="disabled",text="Analisi in corso…",bg=FG_DIM)
        self.result_lbl.config(text="Elaborazione…",fg=FG_DIM)
        self.update_idletasks()
        threading.Thread(target=self._thread,args=(f1,f2),daemon=True).start()

    def _thread(self,f1,f2):
        try:
            from modules.screenplay_diff import compare_screenplays
            r=compare_screenplays(f1,f2,output_dir=os.path.dirname(os.path.abspath(f1)))
            self.after(0,self._ok,r)
        except Exception as e:
            self.after(0,self._err,str(e))

    def _ok(self,r):
        self.result_lbl.config(fg=GREEN,text=f"✓  {r['changes_count']} modifiche trovate\n   + Aggiunte:  {r['inserts']}\n   - Tagli:     {r['deletes']}\n   ~ Modifiche: {r['replaces']}\n\nFile salvati accanto agli originali.")
        self.btn.config(state="normal",text="Confronta  ▶",bg=GREEN)
        import webbrowser; webbrowser.open(f"file://{r['html_path']}")

    def _err(self,msg):
        self.result_lbl.config(fg=ORANGE,text=f"Errore:\n{msg}")
        self.btn.config(state="normal",text="Confronta  ▶",bg=GREEN)

    def _center(self):
        self.update_idletasks()
        w,h=self.winfo_width(),self.winfo_height()
        self.geometry(f"+{(self.winfo_screenwidth()-w)//2}+{(self.winfo_screenheight()-h)//2}")

if __name__=="__main__":
    App().mainloop()
GUIEOF

# ── Eseguibile launcher ──────────────────────────────────────────────────────
cat << 'RUNEOF' > "$APP/Contents/MacOS/run"
#!/bin/bash
exec > "$HOME/Desktop/screenplay_compare_log.txt" 2>&1
echo "=== Avvio Screenplay Compare ==="

BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"
RES="$BUNDLE/Resources"

# Cerca Python (Homebrew Apple Silicon / Intel / system)
PYTHON=""
for P in \
    "/opt/homebrew/opt/python@3.14/bin/python3.14" \
    "/opt/homebrew/opt/python@3.13/bin/python3.13" \
    "/opt/homebrew/opt/python@3.12/bin/python3.12" \
    "/opt/homebrew/opt/python@3.11/bin/python3.11" \
    "/opt/homebrew/bin/python3" \
    "/usr/local/bin/python3" \
    "/usr/bin/python3"; do
    if [ -x "$P" ]; then PYTHON="$P"; break; fi
done
echo "Python: $PYTHON"

if [ -z "$PYTHON" ]; then
    osascript -e 'display alert "Python non trovato" message "Installa Python: brew install python@3.12"'
    exit 1
fi

# Installa pdfplumber se mancante
if ! "$PYTHON" -c "import pdfplumber" 2>/dev/null; then
    echo "Installo pdfplumber..."
    "$PYTHON" -m pip install pdfplumber --break-system-packages -q 2>/dev/null \
    || "$PYTHON" -m pip install pdfplumber -q
fi

echo "Avvio GUI..."
cd "$RES"
exec "$PYTHON" screenplay_compare_gui.py
RUNEOF

chmod +x "$APP/Contents/MacOS/run"

# ── Firma e rimozione quarantena ─────────────────────────────────────────────
xattr -cr "$APP" 2>/dev/null
codesign --force --deep --sign - "$APP" 2>/dev/null && echo "✓ App firmata"

echo ""
echo "✓ Screenplay Compare.app creata sul Desktop"
echo "  Doppio click sull'app per avviarla."
open "$HOME/Desktop"
