FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app
COPY . .

# Railway 빌드 시 --build-arg API_BASE_URL=https://<backend-domain>/api 로 백엔드 주소 주입.
ARG API_BASE_URL=http://127.0.0.1:8000/api
# 카카오 JS 키(기능 9). Railway는 서비스 변수를 빌드 시 같은 이름의 ARG로 자동 주입한다 —
# 값은 코드에 적지 않고 Railway 프론트 서비스의 KAKAO_JS_KEY 변수로만 관리한다.
ARG KAKAO_JS_KEY=""
RUN flutter pub get \
    && flutter build web --release \
       --dart-define=API_BASE_URL=${API_BASE_URL} \
       --dart-define=KAKAO_JS_KEY=${KAKAO_JS_KEY}

FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/templates/default.conf.template

# nginx 엔트리포인트가 템플릿에서 ${PORT}만 치환하도록 제한 (안 하면 $uri 같은
# nginx 자체 변수까지 envsubst가 건드려 설정이 깨진다).
ENV NGINX_ENVSUBST_FILTER=^PORT$

EXPOSE 8080
