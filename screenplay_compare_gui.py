"""
Screenplay Diff — Interfaccia grafica
Seleziona due file di sceneggiatura e confrontali con un click.
"""

import os
import sys
import threading
import tkinter as tk
from tkinter import filedialog, messagebox

# Assicura che il modulo diff sia trovabile (funziona sia da CLI che da .command)
_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
# Fallback: usa la cartella corrente se __file__ non è risolvibile
_CWD = os.getcwd()
if _CWD not in sys.path:
    sys.path.insert(0, _CWD)

SUPPORTED = (
    ("Sceneggiature", "*.pdf *.fdx *.fountain *.beat *.txt"),
    ("PDF", "*.pdf"),
    ("Final Draft", "*.fdx"),
    ("Fountain / Beat", "*.fountain *.beat"),
    ("Tutti i file", "*.*"),
)

BG       = "#1e1e1e"
BG2      = "#2d2d2d"
ACCENT   = "#5dade2"
GREEN    = "#6acc6a"
ORANGE   = "#e67e22"
FG       = "#d4d4d4"
FG_DIM   = "#888888"
FONT     = ("Helvetica", 13)
FONT_SM  = ("Helvetica", 11)
FONT_MONO= ("Courier New", 11)


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Screenplay Diff")
        self.configure(bg=BG)
        self.resizable(False, False)
        self._build_ui()
        self._center()

    # ------------------------------------------------------------------
    # UI
    # ------------------------------------------------------------------

    def _build_ui(self):
        pad = dict(padx=20, pady=10)

        # Titolo
        tk.Label(self, text="Screenplay Diff",
                 font=("Helvetica", 18, "bold"), fg=FG, bg=BG).pack(pady=(24, 4))
        tk.Label(self, text="Confronta due versioni di sceneggiatura",
                 font=FONT_SM, fg=FG_DIM, bg=BG).pack(pady=(0, 20))

        # ── File 1 ──
        tk.Label(self, text="Versione 1  (originale)", font=FONT_SM,
                 fg=FG_DIM, bg=BG, anchor="w").pack(fill="x", padx=24)
        f1_row = tk.Frame(self, bg=BG)
        f1_row.pack(fill="x", padx=20, pady=(4, 14))

        self.lbl1 = tk.Label(f1_row, text="Nessun file selezionato",
                             font=FONT_SM, fg=FG_DIM, bg=BG2,
                             anchor="w", padx=10, width=42, relief="flat")
        self.lbl1.pack(side="left", ipady=8, fill="x", expand=True)

        tk.Button(f1_row, text="Scegli…", font=FONT_SM,
                  bg=ACCENT, fg="white", relief="flat", cursor="hand2",
                  padx=12, command=self._pick1).pack(side="left", padx=(8, 0), ipady=8)

        # ── File 2 ──
        tk.Label(self, text="Versione 2  (revisione)", font=FONT_SM,
                 fg=FG_DIM, bg=BG, anchor="w").pack(fill="x", padx=24)
        f2_row = tk.Frame(self, bg=BG)
        f2_row.pack(fill="x", padx=20, pady=(4, 24))

        self.lbl2 = tk.Label(f2_row, text="Nessun file selezionato",
                             font=FONT_SM, fg=FG_DIM, bg=BG2,
                             anchor="w", padx=10, width=42, relief="flat")
        self.lbl2.pack(side="left", ipady=8, fill="x", expand=True)

        tk.Button(f2_row, text="Scegli…", font=FONT_SM,
                  bg=ACCENT, fg="white", relief="flat", cursor="hand2",
                  padx=12, command=self._pick2).pack(side="left", padx=(8, 0), ipady=8)

        # ── Pulsante confronta ──
        self.btn_run = tk.Button(
            self, text="Confronta  ▶", font=("Helvetica", 14, "bold"),
            bg=GREEN, fg="#111", relief="flat", cursor="hand2",
            padx=20, pady=12, command=self._run,
        )
        self.btn_run.pack(pady=(0, 20))

        # ── Area risultati ──
        self.result_frame = tk.Frame(self, bg=BG2, padx=16, pady=14)
        self.result_frame.pack(fill="x", padx=20, pady=(0, 24))

        self.result_lbl = tk.Label(
            self.result_frame,
            text="Seleziona due file e premi Confronta.",
            font=FONT_SM, fg=FG_DIM, bg=BG2, justify="left", anchor="w",
            wraplength=460,
        )
        self.result_lbl.pack(anchor="w")

    # ------------------------------------------------------------------
    # Azioni
    # ------------------------------------------------------------------

    def _pick1(self):
        path = filedialog.askopenfilename(title="Seleziona Versione 1", filetypes=SUPPORTED)
        if path:
            self.file1 = path
            self.lbl1.config(text=os.path.basename(path), fg=FG)

    def _pick2(self):
        path = filedialog.askopenfilename(title="Seleziona Versione 2", filetypes=SUPPORTED)
        if path:
            self.file2 = path
            self.lbl2.config(text=os.path.basename(path), fg=FG)

    def _run(self):
        f1 = getattr(self, "file1", None)
        f2 = getattr(self, "file2", None)

        if not f1:
            messagebox.showwarning("File mancante", "Seleziona la Versione 1.")
            return
        if not f2:
            messagebox.showwarning("File mancante", "Seleziona la Versione 2.")
            return

        self.btn_run.config(state="disabled", text="Analisi in corso…", bg=FG_DIM)
        self.result_lbl.config(text="Elaborazione…", fg=FG_DIM)
        self.update_idletasks()

        threading.Thread(target=self._run_in_thread, args=(f1, f2), daemon=True).start()

    def _run_in_thread(self, f1, f2):
        try:
            from modules.screenplay_diff import compare_screenplays
            output_dir = os.path.dirname(os.path.abspath(f1))
            result = compare_screenplays(f1, f2, output_dir=output_dir)
            self.after(0, self._show_success, result)
        except ImportError as e:
            self.after(0, self._show_error,
                       f"Libreria mancante:\n{e}\n\nEsegui: pip install pdfplumber")
        except Exception as e:
            self.after(0, self._show_error, str(e))

    def _show_success(self, result):
        lines = [
            f"✓  {result['changes_count']} modifiche trovate",
            f"   + Aggiunte:   {result['inserts']}",
            f"   - Tagli:      {result['deletes']}",
            f"   ~ Modifiche:  {result['replaces']}",
            "",
            f"File salvati in:",
            f"  {os.path.basename(result['html_path'])}",
            f"  {os.path.basename(result['report_path'])}",
        ]
        self.result_lbl.config(text="\n".join(lines), fg=GREEN)
        self.btn_run.config(state="normal", text="Confronta  ▶", bg=GREEN)

        # Apre automaticamente l'HTML nel browser
        import webbrowser
        webbrowser.open(f"file://{result['html_path']}")

    def _show_error(self, msg):
        self.result_lbl.config(text=f"Errore:\n{msg}", fg=ORANGE)
        self.btn_run.config(state="normal", text="Confronta  ▶", bg=GREEN)

    # ------------------------------------------------------------------

    def _center(self):
        self.update_idletasks()
        w, h = self.winfo_width(), self.winfo_height()
        x = (self.winfo_screenwidth()  - w) // 2
        y = (self.winfo_screenheight() - h) // 2
        self.geometry(f"+{x}+{y}")


if __name__ == "__main__":
    app = App()
    app.mainloop()
