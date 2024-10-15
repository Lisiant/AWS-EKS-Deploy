# 🌤️ Deploying a Spring Boot Application on AWS EKS

## 개요

AWS EKS를 사용하여 Spring boot Application을 배포하기

### 준비 사항

- Docker 설치
- AWS CLI 및 kubectl, eksctl 설치
- AWS 계정 생성

## Springboot app

`Dockerfile`

```docker
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
```

`build.gradle`

```docker
plugins {
	id 'java'
	id 'org.springframework.boot' version '3.3.4'
	id 'io.spring.dependency-management' version '1.1.6'
}

group = 'com.example'
version = '0.0.1-SNAPSHOT'

java {
	toolchain {
		languageVersion = JavaLanguageVersion.of(17)
	}
}

configurations {
	compileOnly {
		extendsFrom annotationProcessor
	}
}

repositories {
	mavenCentral()
}

dependencies {
	implementation 'org.springframework.boot:spring-boot-starter-web'
	compileOnly 'org.projectlombok:lombok'
	annotationProcessor 'org.projectlombok:lombok'
	testImplementation 'org.springframework.boot:spring-boot-starter-test'
	testRuntimeOnly 'org.junit.platform:junit-platform-launcher'
}

tasks.named('test') {
	useJUnitPlatform()
}

bootJar {
	mainClass = 'com.example.eksdemo.EksdemoApplication'  // 메인 클래스 이름을 설정
}
```

## AWS ECR

Elastic Container Registry

- 프라이빗 리포지토리 생성

![image](https://github.com/user-attachments/assets/c7e958b9-38f4-486a-aa23-8e2df27620eb)

생성 후 푸시 명령 보기 클릭

![image](https://github.com/user-attachments/assets/20fdc407-f8d9-4f87-8350-1506934c651a)

![image](https://github.com/user-attachments/assets/a199b3b4-8dc8-46c6-bf0c-aec52915bd0a)

### 멀티 아키텍처 빌드

본인의 경우 계속해서 amd64/arm64 관련 아키텍처 오류가 발생하였기에 (하단 트러블슈팅 참고) image를 멀티 아키텍처로 빌드하고 바로 ECR에 Push하였다.

<aside>
💡

buildx를 통한 멀티 아키텍처 빌드를 사용해야 하는 경우

```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  -t 646580111040.dkr.ecr.ap-northeast-2.amazonaws.com/ce09-springboot-eks:latest \
  --push .
```

</aside>

위 사진의 2~4 번 과정을 한번에 진행.

ECR 리프레시 하면 새로운 항목 생김
![image](https://github.com/user-attachments/assets/a8e3078a-46a1-4849-b619-e97a711673b8)

## Elastic Kubernetes Service(EKS) Setup

- EKS 클러스터 생성

```docker
eksctl create cluster --name ce09-cluster --version 1.30 --nodes=1 --node-type=t2.small --region ap-northeast-2
```

- kubectl configure

```docker
aws eks --region ap-northeast-2 update-kubeconfig --name ce09-cluster
```
![image](https://github.com/user-attachments/assets/80fa7c47-70a6-410d-a471-fab05fe5fb3a)

- k8s.yaml 작성

```docker
apiVersion: apps/v1
kind: Deployment
metadata:
  name: newapp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: newapp
  template:
    metadata:
      labels:
        app: newapp
    spec:
      containers:
        - name: newapp
          image: 646580111040.dkr.ecr.ap-northeast-2.amazonaws.com/ce09-springboot-eks:latest
          ports:
            - containerPort: 8080

---
apiVersion: v1
kind: Service
metadata:
  name: newapp-service
spec:
  selector:
    app: newapp
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
  type: LoadBalancer
```

- 적용 및 확인

```docker
kubectl apply -f k8s.yaml

kubectl get svc
kubectl get deployment
kubectl get pods
```
![image](https://github.com/user-attachments/assets/d95af766-3ff0-4222-a2e0-37278b5522d2)
![image](https://github.com/user-attachments/assets/23565095-4dcb-4348-bcc8-23532fe2b25b)
![image](https://github.com/user-attachments/assets/4ca13a91-7263-4cb2-a839-2aac223ec694)


- External IP로 이동
![image](https://github.com/user-attachments/assets/d8e4ee94-58f8-4bae-8494-cd406601510e)

## Teardown

```bash
eksctl delete cluster ce09-cluster
```

## 트러블슈팅

```bash
kubectl get pods

NAME                      READY   STATUS             RESTARTS      AGE
newapp-55d4c975b4-jxkcs   0/1     CrashLoopBackOff   4 (59s ago)   2m31s
newapp-55d4c975b4-x7k8m   0/1     CrashLoopBackOff   4 (44s ago)   2m31s
newapp-55d4c975b4-x826z   0/1     Error   4 (46s ago)   2m31s
```

Pod 상태가 지속적으로 `CrashLoopBackOff` 상태와 `Error` 상태로 반복되어 log을 찾아보았다.

```bash
kubectl logs newapp-55d4c975b4-jxkcs

exec /usr/local/openjdk-17/bin/java: exec format error
```

`exec format error` 는 아키텍처가 맞지 않을 경우 발생하는 문제이다. build를 다시 해야 한다.

### Docker buildkit 활성화

- docker buildx가 특정 플러그인에서 동작하지 않아서, setting을 변경해야 한다.

docker desktop  → settings → docker engine 내용 수정

```bash
{
  "builder": {
    "gc": {
      "defaultKeepStorage": "20GB",
      "enabled": true
    },
    "features": {
      "containerd": true,
      "buildkit": true
    }
  },
  "experimental": true
}
```
![image](https://github.com/user-attachments/assets/07bc864c-4ac7-4e5a-a8ae-808ac4f24992)
