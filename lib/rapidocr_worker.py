# =============================================================================
# rapidocr_worker.py - Optional persistent background OCR worker using
# RapidOCR (PaddleOCR v4 ONNX). Communicates with RapidOcrBridge.ahk over
# stdin/stdout using raw BMP buffers encoded as single-line base64.
# =============================================================================

import base64
import sys

def main():
    try:
        from rapidocr_onnxruntime import RapidOCR
    except Exception as exc:
        sys.stdout.write(f"UNAVAILABLE: {exc}\n")
        sys.stdout.flush()
        return

    engine = RapidOCR()
    sys.stdout.write("READY\n")
    sys.stdout.flush()

    for line in sys.stdin:
        cmd = line.strip()
        if not cmd:
            continue
        if cmd == "EXIT":
            break
        try:
            bmp_bytes = base64.b64decode(cmd)
            result, _ = engine(bmp_bytes)
            if result:
                text = " ".join(item[1] for item in result if item and len(item) > 1)
            else:
                text = ""
            sys.stdout.write("OK\t" + text.replace("\r", " ").replace("\n", " ") + "\n")
        except Exception as exc:
            sys.stdout.write(f"ERR\t{exc}\n")
        sys.stdout.flush()

if __name__ == "__main__":
    main()
