"""Contact sheet of the source clip: one labelled frame every <step> seconds from <start> to <end>.
Usage: python scout.py <video> <out.jpg> <start> <end> <step> [cols]
"""
import sys

import cv2
import numpy as np

video, out, start, end, step = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
cols = int(sys.argv[6]) if len(sys.argv) > 6 else 10
cap = cv2.VideoCapture(video)
cw, ch = 192, 108
times = np.arange(start, end, step)
rows = (len(times) + cols - 1) // cols
sheet = np.zeros((rows * ch, cols * cw, 3), np.uint8)
for k, t in enumerate(times):
    cap.set(cv2.CAP_PROP_POS_MSEC, t * 1000)
    ok, f = cap.read()
    if not ok:
        continue
    f = cv2.resize(f, (cw, ch), interpolation=cv2.INTER_AREA)
    cv2.putText(f, f"{t:.0f}", (3, 14), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 255, 255), 1)
    r, c = divmod(k, cols)
    sheet[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw] = f
cv2.imwrite(out, sheet, [cv2.IMWRITE_JPEG_QUALITY, 80])
print(sheet.shape)
