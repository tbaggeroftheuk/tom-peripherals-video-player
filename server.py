from flask import Flask, send_file
from PIL import Image
import os
import cv2
from pathlib import Path
import dfpwm
import soundfile as sf
import numpy as np
from scipy.signal import resample
import moviepy.editor as mp
SOURCE_PATH = "video.mp4"
OUTPUT_DIR = "frames"
TARGET_SIZE = (256, 160)
FRAME_FILENAME = "frame.png"
MP4_MAX_SECONDS = 60

DFPWM_FILE = "current.dfpwm"
CHUNK_SIZE_SECONDS = 4

app = Flask(__name__)
frame_count = 0
frames = []

audio_chunks = []
audio_count = 0

def extract_frames():
    global frames
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    frames.clear()

    ext = os.path.splitext(SOURCE_PATH)[1].lower()

    if ext == ".gif":
        with Image.open(SOURCE_PATH) as im:
            i = 0
            try:
                while True:
                    frame = im.convert("RGBA")
                    frame = frame.resize(TARGET_SIZE, Image.LANCZOS)
                    path = os.path.join(OUTPUT_DIR, f"frame_{i}.png")
                    frame.save(path)
                    frames.append(path)
                    i += 1
                    im.seek(im.tell() + 1)
            except EOFError:
                pass
        print(f"Extracted {len(frames)} frames from GIF.")

    elif ext in [".mp4", ".mov", ".avi", ".mkv"]:
        cap = cv2.VideoCapture(SOURCE_PATH)
        if not cap.isOpened():
            raise RuntimeError(f"Cannot open video: {SOURCE_PATH}")

        fps = cap.get(cv2.CAP_PROP_FPS)
        max_frames = int(fps * MP4_MAX_SECONDS)
        i = 0

        while i < max_frames:
            ret, frame = cap.read()
            if not ret:
                break
            frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGBA)
            pil_frame = Image.fromarray(frame)
            pil_frame = pil_frame.resize(TARGET_SIZE, Image.LANCZOS)
            path = os.path.join(OUTPUT_DIR, f"frame_{i}.png")
            pil_frame.save(path)
            frames.append(path)
            i += 1

        cap.release()
        print(f"Extracted {len(frames)} frames from MP4 (first {MP4_MAX_SECONDS}s).")

    else:
        raise RuntimeError(f"Unsupported file type: {ext}")

def extract_audio_to_dfpwm():
    global audio_chunks
    audio_chunks.clear()

    ext = os.path.splitext(SOURCE_PATH)[1].lower()

    if ext in [".mp4", ".mov", ".avi", ".mkv"]:
        clip = mp.VideoFileClip(SOURCE_PATH).subclip(0, MP4_MAX_SECONDS)
        audio_path = "temp_audio.wav"
        clip.audio.write_audiofile(audio_path, fps=dfpwm.SAMPLE_RATE, nbytes=2, ffmpeg_params=["-ac", "1"])
        source_audio = audio_path
    elif ext == ".gif":
        print("GIF detected, no audio extracted.")
        return
    else:
        raise RuntimeError(f"Unsupported file type for audio: {ext}")

    data, sample_rate = sf.read(source_audio)

    if len(data.shape) > 1 and data.shape[1] > 1:
        data = data[:, 0]

    if sample_rate != dfpwm.SAMPLE_RATE:
        new_len = int(len(data) * dfpwm.SAMPLE_RATE / sample_rate)
        data = resample(data, new_len)

    data = data.astype(np.float64)
    data = np.clip(data, -1.0, 1.0)

    compressed = dfpwm.compressor(data)
    Path(DFPWM_FILE).write_bytes(compressed)

    samples_per_chunk = dfpwm.SAMPLE_RATE * CHUNK_SIZE_SECONDS
    for i in range(0, len(data), samples_per_chunk):
        chunk_data = data[i:i+samples_per_chunk]
        chunk_compressed = dfpwm.compressor(chunk_data)
        chunk_path = Path(f"chunk_{i//samples_per_chunk}.dfpwm")
        chunk_path.write_bytes(chunk_compressed)
        audio_chunks.append(str(chunk_path))

    print(f"Created {len(audio_chunks)} audio chunks.")

@app.route(f"/{FRAME_FILENAME}")
def serve_frame():
    global frame_count
    frame_index = frame_count % len(frames)
    frame_path = frames[frame_index]
    frame_count += 1
    return send_file(frame_path, mimetype="image/png")

@app.route("/audio.dfpwm")
def serve_audio():
    global audio_count
    if not audio_chunks:
        return "No audio chunks available", 404
    chunk_index = audio_count % len(audio_chunks)
    chunk_path = audio_chunks[chunk_index]
    audio_count += 1
    return send_file(chunk_path, mimetype="application/octet-stream")

@app.route("/reset_frames")
def reset_frames():
    global frame_count
    frame_count = 0
    return "Frame counter reset."


if __name__ == "__main__":
    extract_frames()
    extract_audio_to_dfpwm()
    app.run(host="0.0.0.0", port=5000)
