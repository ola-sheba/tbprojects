#!/usr/bin/env bash
set -euo pipefail

mkdir -p /app/paper_api
cat > /app/paper_api/__init__.py <<'PY'
"""Academic paper analysis API."""
PY
cat > /app/pyproject.toml <<'PYPROJECT'
[project]
name = "paper-api"
version = "0.1.0"
description = "FastAPI service for parsing and analyzing long academic papers."
requires-python = ">=3.11"
dependencies = [
  "fastapi==0.115.6",
  "uvicorn==0.34.0",
  "python-multipart==0.0.20",
  "pydantic==2.10.5",
  "pypdf==5.1.0",
  "python-docx==1.1.2"
]

[build-system]
requires = ["setuptools==75.8.0"]
build-backend = "setuptools.build_meta"

[tool.setuptools.packages.find]
include = ["paper_api*"]
PYPROJECT
cat > /app/requirements.lock <<'LOCK'
fastapi==0.115.6
uvicorn==0.34.0
python-multipart==0.0.20
pydantic==2.10.5
pypdf==5.1.0
python-docx==1.1.2
starlette==0.41.3
anyio==4.8.0
lxml==5.3.0
LOCK
cat > /app/paper_api/main.py <<'PY'
from __future__ import annotations

import io
import math
import re
from collections import Counter
from dataclasses import dataclass
from typing import Any

from docx import Document
from fastapi import FastAPI, File, HTTPException, UploadFile
from pydantic import BaseModel, Field
from pypdf import PdfReader

app = FastAPI(title="Academic Paper Insights API", version="0.1.0")

WORD_RE = re.compile(r"[A-Za-z][A-Za-z0-9_\-']*|\d+(?:\.\d+)?")
SENTENCE_RE = re.compile(r"(?<=[.!?])\s+|\n+")

STOPWORDS = {
    "a", "an", "and", "are", "as", "at", "be", "been", "being", "by", "can", "could",
    "did", "do", "does", "for", "from", "had", "has", "have", "having", "he", "her", "his",
    "how", "i", "if", "in", "into", "is", "it", "its", "may", "might", "more", "most", "no",
    "not", "of", "on", "or", "our", "paper", "study", "such", "than", "that", "the", "their",
    "these", "this", "those", "to", "using", "was", "we", "were", "which", "while", "with", "within",
    "without", "would", "also", "based", "between", "across", "through", "using", "used", "uses",
}


class ChunkInfo(BaseModel):
    index: int
    start_token: int
    end_token: int
    token_count: int
    preview: str
    top_terms: list[str]


class AnalysisResponse(BaseModel):
    filename: str
    file_type: str
    token_count: int
    chunk_count: int
    summary: str
    key_insights: list[str] = Field(min_length=3)
    context: dict[str, Any]
    chunks: list[ChunkInfo]


@dataclass
class ExtractedDocument:
    text: str
    sections: list[str]


def _tokens(text: str) -> list[str]:
    return WORD_RE.findall(text)


def _normalized_terms(text: str) -> list[str]:
    return [t.lower() for t in _tokens(text) if len(t) > 2 and t.lower() not in STOPWORDS]


def _sentences(text: str) -> list[str]:
    raw = [s.strip() for s in SENTENCE_RE.split(text) if s and s.strip()]
    return [re.sub(r"\s+", " ", s) for s in raw if len(s.split()) >= 5]


def _read_docx(data: bytes) -> ExtractedDocument:
    try:
        doc = Document(io.BytesIO(data))
    except Exception as exc:  # pragma: no cover - exact parser errors vary
        raise HTTPException(status_code=400, detail=f"Could not parse DOCX file: {exc}") from exc

    paragraphs: list[str] = []
    sections: list[str] = []
    for paragraph in doc.paragraphs:
        text = paragraph.text.strip()
        if not text:
            continue
        paragraphs.append(text)
        style_name = (paragraph.style.name if paragraph.style is not None else "").lower()
        if "heading" in style_name or (len(text.split()) <= 12 and text[:1].isupper()):
            sections.append(text[:120])
    return ExtractedDocument(text="\n".join(paragraphs), sections=sections[:20])


def _read_pdf(data: bytes) -> ExtractedDocument:
    try:
        reader = PdfReader(io.BytesIO(data))
        pages = [page.extract_text() or "" for page in reader.pages]
    except Exception as exc:  # pragma: no cover - exact parser errors vary
        raise HTTPException(status_code=400, detail=f"Could not parse PDF file: {exc}") from exc

    text = "\n".join(page.strip() for page in pages if page and page.strip())
    sections = []
    for line in text.splitlines():
        clean = line.strip()
        if clean and len(clean.split()) <= 14 and (clean.endswith(":") or clean.istitle()):
            sections.append(clean[:120])
    return ExtractedDocument(text=text, sections=sections[:20])


def _extract_document(filename: str, data: bytes) -> tuple[str, ExtractedDocument]:
    lower = filename.lower()
    if lower.endswith(".pdf"):
        return "pdf", _read_pdf(data)
    if lower.endswith(".docx"):
        return "docx", _read_docx(data)
    raise HTTPException(status_code=415, detail="Unsupported file type. Upload a PDF or DOCX file.")


def _top_terms(text: str, limit: int = 12) -> list[str]:
    counts = Counter(_normalized_terms(text))
    return [term for term, _ in counts.most_common(limit)]


def _chunk_text(text: str, chunk_size: int = 2500) -> list[ChunkInfo]:
    toks = _tokens(text)
    chunks: list[ChunkInfo] = []
    if not toks:
        return chunks

    for index, start in enumerate(range(0, len(toks), chunk_size)):
        end = min(start + chunk_size, len(toks))
        chunk_tokens = toks[start:end]
        chunk_text = " ".join(chunk_tokens)
        preview = chunk_text[:260].strip()
        chunks.append(
            ChunkInfo(
                index=index,
                start_token=start,
                end_token=end,
                token_count=end - start,
                preview=preview,
                top_terms=_top_terms(chunk_text, limit=6),
            )
        )
    return chunks


def _score_sentences(sentences: list[str], term_counts: Counter[str]) -> list[tuple[float, int, str]]:
    scored: list[tuple[float, int, str]] = []
    if not term_counts:
        return [(1.0, i, s) for i, s in enumerate(sentences)]

    max_count = max(term_counts.values()) or 1
    for idx, sentence in enumerate(sentences):
        terms = _normalized_terms(sentence)
        if not terms:
            continue
        # Frequency score plus light boosts for academic signal words.
        freq_score = sum(term_counts[t] / max_count for t in terms) / math.sqrt(len(terms))
        lower = sentence.lower()
        signal_boost = 0.0
        for marker in ("contribution", "finding", "method", "result", "limitation", "evaluation", "experiment"):
            if marker in lower:
                signal_boost += 0.35
        scored.append((freq_score + signal_boost, idx, sentence))
    return scored


def _summary(text: str, max_sentences: int = 8) -> str:
    sentences = _sentences(text)
    if not sentences:
        return "No readable text was extracted from the document."
    term_counts = Counter(_normalized_terms(text))
    scored = _score_sentences(sentences, term_counts)
    selected = sorted(scored, reverse=True)[:max_sentences]
    selected_in_order = [sentence for _, _, sentence in sorted(selected, key=lambda item: item[1])]
    result = " ".join(selected_in_order)
    words = result.split()
    if len(words) > 500:
        result = " ".join(words[:500]).rstrip() + "..."
    if len(result) > 5000:
        result = result[:4997].rstrip() + "..."
    return result


def _key_insights(text: str, chunks: list[ChunkInfo]) -> list[str]:
    terms = _top_terms(text, limit=10)
    sentences = _sentences(text)
    term_counts = Counter(_normalized_terms(text))
    scored = _score_sentences(sentences, term_counts)
    top_sentences = [s for _, _, s in sorted(scored, reverse=True)[:5]]

    insights: list[str] = []
    if terms:
        insights.append("Dominant themes: " + ", ".join(terms[:6]) + ".")
    if chunks:
        insights.append(f"The document was split into {len(chunks)} chunks for long-context processing.")
    for sentence in top_sentences:
        clean = sentence.strip()
        if clean and clean not in insights:
            if len(clean) > 260:
                clean = clean[:257].rstrip() + "..."
            insights.append(clean)
        if len(insights) >= 5:
            break
    while len(insights) < 3:
        insights.append("The document contains extractable academic content suitable for local NLP analysis.")
    return insights


def _context(text: str, sections: list[str], chunks: list[ChunkInfo]) -> dict[str, Any]:
    terms = _top_terms(text, limit=15)
    lower = text.lower()
    academic_markers = {
        "has_abstract": "abstract" in lower,
        "has_methods": any(word in lower for word in ("method", "methodology", "experiment")),
        "has_results": any(word in lower for word in ("result", "finding", "evaluation")),
        "has_limitations": "limitation" in lower or "limitations" in lower,
        "has_conclusion": "conclusion" in lower,
    }
    return {
        "sections": sections[:12],
        "top_keywords": terms,
        "academic_markers": academic_markers,
        "long_document_strategy": {
            "chunking_enabled": True,
            "chunk_count": len(chunks),
            "chunk_token_target": 2500,
        },
    }


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/analyze", response_model=AnalysisResponse)
async def analyze(file: UploadFile = File(...)) -> AnalysisResponse:
    filename = file.filename or "uploaded"
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")

    file_type, extracted = _extract_document(filename, data)
    text = extracted.text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="No readable text could be extracted from the document.")

    token_count = len(_tokens(text))
    chunks = _chunk_text(text)
    return AnalysisResponse(
        filename=filename,
        file_type=file_type,
        token_count=token_count,
        chunk_count=len(chunks),
        summary=_summary(text),
        key_insights=_key_insights(text, chunks),
        context=_context(text, extracted.sections, chunks),
        chunks=chunks,
    )
PY
