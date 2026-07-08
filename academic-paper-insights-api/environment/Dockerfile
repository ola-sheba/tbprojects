FROM python:3.11-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential curl \
    && rm -rf /var/lib/apt/lists/*

RUN python -m pip install --upgrade pip \
    && python -m pip install --no-cache-dir \
        fastapi==0.115.6 \
        uvicorn==0.34.0 \
        python-multipart==0.0.20 \
        pydantic==2.10.5 \
        pypdf==5.1.0 \
        python-docx==1.1.2 \
        pytest==8.3.4 \
        httpx==0.28.1 \
        reportlab==4.2.5

CMD ["bash"]
