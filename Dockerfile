FROM gradle:8.1.0-jdk17 AS build
WORKDIR /app

# 의존성 파일을 먼저 복사하여 캐시 최적화
COPY build.gradle settings.gradle ./
RUN gradle build --no-daemon

# 소스 파일을 복사한 후 빌드
COPY src ./src
RUN gradle bootJar --no-daemon

FROM openjdk:17-jdk-slim
WORKDIR /app
COPY --from=build /app/build/libs/*.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java","-jar","/app/app.jar"]