FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080

# Railway는 PORT 환경변수를 동적으로 주입한다 (없으면 로컬 기본값 8080).
# 배포 시 컨테이너 시작 전에 alembic 마이그레이션을 먼저 적용한다.
CMD alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}
