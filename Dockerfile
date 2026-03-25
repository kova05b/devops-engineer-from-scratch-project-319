# syntax=docker/dockerfile:1
# Многоступенчатая сборка: фронт (Vite) → бэкенд (Gradle) → лёгкий рантайм с JRE.

# --- Стадия 1: production-сборка React (попадёт в Spring static)
FROM node:20-bookworm-slim AS frontend
WORKDIR /app/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

# --- Стадия 2: кладём статику в classpath и собираем executable JAR
FROM eclipse-temurin:21-jdk-jammy AS backend
WORKDIR /app
COPY gradlew gradlew.bat settings.gradle.kts build.gradle.kts versions.properties ./
COPY gradle ./gradle
COPY src ./src
COPY public ./public
# Gradle ожидает статику здесь — подменяем на свежий dist с прошлой стадии
RUN rm -rf src/main/resources/static && mkdir -p src/main/resources/static
COPY --from=frontend /app/frontend/dist/ ./src/main/resources/static/
RUN chmod +x gradlew && ./gradlew bootJar -x test --no-daemon

# --- Стадия 3: только JRE и JAR, процесс не под root
FROM eclipse-temurin:21-jre-jammy
WORKDIR /app
RUN groupadd -r spring && useradd -r -g spring spring
COPY --from=backend /app/build/libs/project-devops-deploy-0.0.1-SNAPSHOT.jar app.jar
USER spring
EXPOSE 8080 9090
ENV JAVA_OPTS=""
# exec + sh -c: PID 1 = java, корректные сигналы от docker stop
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
