# syntax=docker/dockerfile:1

# ---------- Estágio 1: build (gera o banco SQLite e o JAR) ----------
# Imagem oficial do Maven com JDK 25 (dispensa o Maven Wrapper, cujo .jar não é versionado)
FROM maven:3.9-eclipse-temurin-25 AS build
WORKDIR /workspace

COPY pom.xml lombok.config ./

# Baixa dependências em camada separada para aproveitar cache
RUN --mount=type=cache,target=/root/.m2 mvn -B -q dependency:go-offline || true

# Gera o banco de dados com o Flyway (obrigatório para o perfil offline)
COPY flyway/ flyway/
RUN --mount=type=cache,target=/root/.m2 \
    mkdir -p calculadora/db && \
    mvn -B flyway:migrate -Dflyway.configFiles=./flyway/flyway-pro.conf --errors

# Compila o JAR (testes pulados no build da imagem)
COPY src/ src/
RUN --mount=type=cache,target=/root/.m2 mvn -B clean package -DskipTests

# ---------- Estágio 2: runtime ----------
FROM eclipse-temurin:25-jre
WORKDIR /app

RUN groupadd --system app && useradd --system --gid app --home /app app

COPY --from=build /workspace/target/api-regime-geral.jar app.jar
COPY --from=build /workspace/calculadora/db/calculadora-pro.db calculadora/db/calculadora-pro.db
RUN chown -R app:app /app

USER app

ENV SPRING_PROFILES_ACTIVE=offline \
    JAVA_OPTS="-XX:MaxRAMPercentage=75"

# 8080 = API | 9101 = actuator (health/metrics)
EXPOSE 8080 9101

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
