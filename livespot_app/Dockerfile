FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app
COPY . .

# Railway 빌드 시 --build-arg API_BASE_URL=https://<backend-domain>/api 로 백엔드 주소 주입.
ARG API_BASE_URL=http://127.0.0.1:8000/api
RUN flutter pub get \
    && flutter build web --release --dart-define=API_BASE_URL=${API_BASE_URL}

FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/templates/default.conf.template

# nginx 엔트리포인트가 템플릿에서 ${PORT}만 치환하도록 제한 (안 하면 $uri 같은
# nginx 자체 변수까지 envsubst가 건드려 설정이 깨진다).
ENV NGINX_ENVSUBST_FILTER=^PORT$

EXPOSE 8080
