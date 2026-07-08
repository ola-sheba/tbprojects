# Academic Paper Insights API

Build a Python API in `/app` that lets users upload and analyze academic papers in PDF and DOCX format.

The API must be implemented with FastAPI and must expose at least these endpoints:

1. `GET /health`
   - Returns JSON showing the service is running, for example `{ "status": "ok" }`.

2. `POST /analyze`
   - Accepts multipart file upload using the form field name `file`.
   - Supports `.pdf` and `.docx` files.
   - Rejects unsupported formats with a clear 4xx response.
   - Extracts document text using local parsing libraries. Do not call external LLM APIs or network services.
   - Handles long documents exceeding 50,000 tokens/words by chunking the document before analysis.
   - Returns JSON containing:
     - `filename`
     - `file_type`
     - `token_count`
     - `chunk_count`
     - `summary`
     - `key_insights`
     - `context`
     - `chunks` or comparable chunk metadata

The NLP can be deterministic and lightweight. A high-quality extractive summarizer, keyword extraction, section detection, and chunk metadata are sufficient. Do not require GPU models.

Dependency and reproducibility requirements:

- Include a `pyproject.toml` file declaring the Python project and dependencies.
- Include a lockfile such as `requirements.lock`, `uv.lock`, `poetry.lock`, or `Pipfile.lock` with pinned versions.
- Keep the implementation self-contained and runnable without internet access once dependencies are installed in the Docker environment.

Suggested package layout inside `/app`:

```text
paper_api/
  __init__.py
  main.py
pyproject.toml
requirements.lock
```

You may add any additional files needed, but the tests will import `paper_api.main:app` and call the FastAPI app directly.
