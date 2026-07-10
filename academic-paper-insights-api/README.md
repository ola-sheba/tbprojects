# Academic Paper Insights API

Build a Python API in `/app` that lets users upload and analyze academic papers in PDF and DOCX format.

The API must be implemented with FastAPI and must expose at least the endpoints described below. The tests import the app directly as `paper_api.main:app` and call it in-process with `fastapi.testclient.TestClient`, so the app object must be named `app` and live in `paper_api/main.py`.

## Endpoints

### 1. `GET /health`

- Returns HTTP 200 with a JSON object containing a `status` field.
- `status` must be one of `ok`, `healthy`, or `up` (case-insensitive). Example: `{ "status": "ok" }`.

### 2. `POST /analyze`

- Accepts a multipart file upload using the form field name `file`.
- Supports `.pdf` and `.docx` files, detected from the uploaded filename's extension.
- Rejects any other format (e.g. `.txt`) with a 4xx response — one of `400`, `415`, or `422`. The response body must mention that the type is unsupported, or name the supported types (`pdf` / `docx`).
- Extracts document text using **local** parsing libraries (`pypdf` for PDF, `python-docx` for DOCX). Do **not** call external LLM APIs or network services. The source under `paper_api/` must not contain the markers `openai`, `anthropic`, `cohere`, `gemini`, `api_key`, or `authorization: bearer`.
- Handles long documents (exceeding 50,000 tokens/words) by chunking the extracted text before analysis.
- On success, returns HTTP 200 with a JSON body matching the **Response schema** below.

## Response schema (`POST /analyze`, 200)

The response body is a normative JSON object. All of the following keys are **required** and must satisfy the stated types and constraints:

| Key | Type | Constraints |
| --- | --- | --- |
| `filename` | string | The uploaded filename. |
| `file_type` | string | The detected format. Return `"pdf"` for PDF uploads and `"docx"` for DOCX uploads. (The full MIME type is also accepted, but the plain extension keyword is simplest.) |
| `token_count` | integer | Total number of word-like tokens in the extracted text. Count words, not sub-word/BPE tokens — a ~60,000-word document must report `token_count >= 50000`. |
| `chunk_count` | integer | Number of chunks the document was split into. Must be `>= 1`. For a long document (over 50,000 words) it must be `>= 3`. |
| `summary` | string | An extractive summary. Must contain **at least 20 words** and be **fewer than 6000 characters** — concise, not the full document. |
| `key_insights` | array of strings | Must contain **at least 3** items; the first three must be non-empty strings. |
| `context` | object | A **structured JSON object** (not a string). Use it for structured metadata such as detected sections, top keywords, and academic markers (e.g. whether an abstract/methods/results/limitations were found) and the chunking strategy. |
| `chunks` | array | Per-chunk metadata (e.g. index, token offsets, token count, a preview, and top terms). "Comparable chunk metadata" under another key is acceptable, but including a `chunks` array is recommended. |

The values of `summary`, `key_insights`, and `context` must be **derived from the actual document text** (surface the paper's real terms, section titles, and salient sentences) rather than generic boilerplate, so that the analysis reflects the specific paper that was uploaded.

## Dependency and reproducibility requirements

- Include a `pyproject.toml` at `/app/pyproject.toml` that declares the project and its dependencies. It must reference `fastapi`, a PDF library (`pypdf`), and a DOCX library (`python-docx`).
- Include a lockfile with pinned versions — one of `requirements.lock`, `uv.lock`, `poetry.lock`, or `Pipfile.lock` (pins expressed with `==` or explicit `version` entries).
- Keep the implementation self-contained and runnable without internet access once dependencies are installed in the Docker environment.

## Suggested package layout inside `/app`

```text
paper_api/
  __init__.py
  main.py
pyproject.toml
requirements.lock
```

You may add any additional files needed. The NLP can be deterministic and lightweight — a high-quality extractive summarizer, keyword extraction, section detection, and chunk metadata are sufficient. Do not require GPU models.
